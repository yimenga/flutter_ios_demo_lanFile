import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/client.dart';
import '../core/discovery.dart';
import '../core/identity.dart';
import '../core/models.dart';
import '../core/server.dart';
import '../core/trust.dart';
import '../state/registry.dart';
import '../state/settings.dart';
import '../state/transfer_manager.dart';

/// 应用核心：装配服务端、发现服务、客户端，统一生命周期管理
class AppCore {
  final AppSettings settings;
  final DeviceIdentity identity;
  final TrustStore trust;
  final TransferManager manager;
  final DeviceRegistry registry;

  TransferServer? _server;
  DiscoveryService? _discovery;
  Timer? _maintenanceTimer;
  int _lastPort = 0;
  String? _lastInterfaceIp;
  String _lastInterfaceKey = '';

  /// 本机所有可用 IPv4 地址（定时刷新）
  List<String> interfaceIps = [];
  final Map<String, String> _ipNicName = {};

  AppCore({
    required this.settings,
    required this.identity,
    required this.trust,
    required this.manager,
    required this.registry,
  });

  late final TransferClient client = TransferClient(
    manager: manager,
    trust: trust,
    profileGetter: currentProfile,
  );

  /// 当前对外广播的本机档案
  DeviceProfile currentProfile() {
    final name = (settings.nickname == null || settings.nickname!.isEmpty)
        ? identity.autoName
        : settings.nickname!;
    return DeviceProfile(
      id: identity.id,
      name: name,
      type: identity.type,
      ip: effectiveIp,
      port: settings.port,
    );
  }

  String get effectiveIp {
    final selected = settings.interfaceIp;
    if (selected != null && interfaceIps.contains(selected)) return selected;
    final auto = interfaceIps
        .where((ip) => !ip.startsWith('169.254'))
        .toList();
    if (auto.isEmpty) return '0.0.0.0';
    // 优先真实局域网网卡：蜂窝数据(国内常见 10.x)与 VPN 虚拟网卡的地址，
    // 对同一 Wi-Fi 下的其他设备不可达，选错会报 "No route to host"
    auto.sort((a, b) => _ipPreference(b).compareTo(_ipPreference(a)));
    return auto.first;
  }

  int _ipPreference(String ip) {
    var score = 0;
    final nic = (_ipNicName[ip] ?? '').toLowerCase();
    if (nic.startsWith('en') ||
        nic.startsWith('wlan') ||
        nic.startsWith('eth')) {
      score += 100;
    }
    if (RegExp(r'^(rmnet|ccmni|pdp_ip|wwan|radio|ppp|tun|utun|ipsec|tap|wg|vpn)')
        .hasMatch(nic)) {
      score -= 100;
    }
    if (ip.startsWith('192.168.')) {
      score += 30;
    } else if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
      score += 20;
    } else if (ip.startsWith('10.')) {
      score += 5;
    }
    return score;
  }

  Future<void> start() async {
    await _refreshInterfaces();
    // iOS：首次启动就主动触发“本地网络”授权弹窗。没有授权时系统会静默丢弃
    // 所有局域网收发（表现为扫不到设备、连接报 No route to host）。
    unawaited(_triggerLocalNetworkPermission());
    await _startServer();
    await _startDiscovery();

    _lastPort = settings.port;
    _lastInterfaceIp = settings.interfaceIp;
    settings.addListener(_onSettingsChanged);

    _maintenanceTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _refreshInterfaces();
      registry.sweep();
      // 网卡列表发生变化（插拔网线、切换 Wi-Fi）时重建发现服务，
      // 否则旧的 socket 会一直绑定在失效的网卡上，设备列表再也刷不出来
      final key =
          interfaceIps.where((ip) => !ip.startsWith('169.254')).join(',');
      if (_lastInterfaceKey.isEmpty) {
        _lastInterfaceKey = key;
      } else if (key != _lastInterfaceKey) {
        _lastInterfaceKey = key;
        _startDiscovery();
      }
    });
  }

  /// iOS：向同网段的网关发起一次 TCP 连接尝试，用来让系统弹出"本地网络"授权框。
  /// 用户点"允许"之前系统会直接拒绝这次请求，所以这里不关心成败。
  Future<void> _triggerLocalNetworkPermission() async {
    if (!Platform.isIOS) return;
    try {
      final ip = effectiveIp;
      final dot = ip.lastIndexOf('.');
      if (dot <= 0) return;
      final prefix = ip.substring(0, dot);
      for (final candidate in <String>['$prefix.1', '$prefix.254']) {
        try {
          final socket = await Socket.connect(
            candidate,
            80,
            timeout: const Duration(milliseconds: 1500),
          );
          socket.destroy();
          return;
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _onSettingsChanged() {
    if (settings.port != _lastPort) {
      _lastPort = settings.port;
      _startServer();
      _startDiscovery();
    }
    if (settings.interfaceIp != _lastInterfaceIp) {
      _lastInterfaceIp = settings.interfaceIp;
      _startDiscovery();
    }
  }

  Future<void> _startServer() async {
    try {
      _server ??= TransferServer(
        manager: manager,
        trust: trust,
        settings: settings,
        identity: identity,
        profileGetter: currentProfile,
      );
      await _server!.start();
    } catch (e) {
      debugPrint('[core] server start failed: $e');
    }
  }

  Future<void> _startDiscovery() async {
    _discovery ??= DiscoveryService(
      profileGetter: currentProfile,
      onDeviceFound: registry.seen,
    );
    // 只在选项仍然有效时使用手动指定；否则回退到自动（避免遗留的旧值把广播锁死）
    final selected = settings.interfaceIp;
    await _discovery!.start(
      (selected != null && interfaceIps.contains(selected)) ? selected : null,
    );
  }

  Future<void> _refreshInterfaces() async {
    try {
      final list = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final set = <String>{};
      for (final nic in list) {
        // 跳过蜂窝数据 / VPN 虚拟网卡：它们的地址对同一 Wi-Fi 下的其它设备
        // 不可达，一旦被选中，广播会从错误的网卡发出去，对端完全看不到本机
        final nicName = nic.name.toLowerCase();
        if (RegExp(r'^(rmnet|ccmni|pdp_ip|wwan|radio|ppp|tun|utun|ipsec|tap|wg|vpn)')
            .hasMatch(nicName)) {
          continue;
        }
        for (final addr in nic.addresses) {
          set.add(addr.address);
          _ipNicName[addr.address] = nic.name;
        }
      }
      interfaceIps = set.toList()..sort();
    } catch (_) {}
  }

  Future<void> dispose() async {
    _maintenanceTimer?.cancel();
    settings.removeListener(_onSettingsChanged);
    await _server?.stop();
    await _discovery?.stop();
  }
}
