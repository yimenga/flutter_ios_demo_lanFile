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

  /// 本机所有可用 IPv4 地址（定时刷新）
  List<String> interfaceIps = [];

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
    return auto.isNotEmpty ? auto.first : '0.0.0.0';
  }

  Future<void> start() async {
    await _refreshInterfaces();
    await _startServer();
    await _startDiscovery();

    _lastPort = settings.port;
    _lastInterfaceIp = settings.interfaceIp;
    settings.addListener(_onSettingsChanged);

    _maintenanceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshInterfaces();
      registry.sweep();
    });
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
    await _discovery!.start(settings.interfaceIp);
  }

  Future<void> _refreshInterfaces() async {
    try {
      final list = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final set = <String>{};
      for (final nic in list) {
        for (final addr in nic.addresses) {
          set.add(addr.address);
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
