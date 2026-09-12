import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';

/// 设备发现服务：
/// - 监听 UDP 45670 接收局域网广播
/// - 每个网卡各建一个发送 socket 广播本机档案（多网卡环境下全覆盖）
/// - 收到别人的广播后，立即单播回自己的档案（即使对方收不到广播也能发现我）
class DiscoveryService {
  static const int discoveryPort = 45670;

  final DeviceProfile Function() profileGetter;
  final void Function(DeviceProfile) onDeviceFound;

  DiscoveryService({
    required this.profileGetter,
    required this.onDeviceFound,
  });

  RawDatagramSocket? _listener;
  final List<RawDatagramSocket> _senders = [];
  final Map<RawDatagramSocket, String> _senderIps = {};
  Timer? _timer;

  Future<void> start(String? bindIp) async {
    await stop();
    try {
      _listener = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _listener!.broadcastEnabled = true;
      _listener!.listen(_onData, onError: (_) {});
    } on SocketException {
      // 端口被占用（例如本应用第二个实例）：仍尝试监听
      try {
        _listener = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
          reuseAddress: true,
        );
        _listener!.listen(_onData, onError: (_) {});
      } catch (e) {
        debugPrint('[discovery] listen failed: $e');
        return;
      }
    }

    // 发送端：为每个网卡建 socket，广播从对应网卡出去
    final ips = await _localIps();
    final targets = bindIp != null ? [bindIp] : ips;
    for (final ip in targets) {
      try {
        final s = await RawDatagramSocket.bind(
          InternetAddress(ip),
          0,
          reuseAddress: true,
        );
        s.broadcastEnabled = true;
        _senders.add(s);
        _senderIps[s] = ip;
      } catch (e) {
        debugPrint('[discovery] sender bind $ip failed: $e');
      }
    }
    if (_senders.isEmpty) {
      // 兜底：绑定任意地址
      try {
        final s = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
          reuseAddress: true,
        );
        s.broadcastEnabled = true;
        _senders.add(s);
      } catch (_) {}
    }

    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _broadcast());
    _broadcast();
  }

  Future<List<String>> _localIps() async {
    try {
      final list = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final ips = <String>{};
      for (final nic in list) {
        for (final addr in nic.addresses) {
          if (!addr.address.startsWith('169.254')) ips.add(addr.address);
        }
      }
      return ips.toList();
    } catch (_) {
      return [];
    }
  }

  void _broadcast() {
    if (_senders.isEmpty) return;
    try {
      final base = profileGetter();
      for (final s in _senders) {
        try {
          // 每张网卡用自己这一侧可达的 IP 广播：多网卡(Wi-Fi + 蜂窝/VPN)时，
          // 对端拿到的才是能连回来的地址
          final ip = _senderIps[s];
          final profile =
              (ip == null || ip.isEmpty) ? base : base.copyWith(ip: ip);
          final data = utf8.encode(jsonEncode(profile.toJson()));
          s.send(data, InternetAddress('255.255.255.255'), discoveryPort);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _onData(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _listener?.receive();
    if (datagram == null) return;
    final profile = DeviceProfile.tryParse(
      utf8.decode(datagram.data, allowMalformed: true),
    );
    if (profile == null) return;
    onDeviceFound(profile);

    // 单播回执：让对方无需能收到广播也能发现我
    final my = profileGetter();
    if (profile.id != my.id) {
      final reply = utf8.encode(
        jsonEncode(my.copyWith(ip: _replyIp(datagram.address.address)).toJson()),
      );
      // 优先用绑定在 0.0.0.0 的监听 socket 发回执：系统会自动选择正确的网卡与源地址。
      // iOS 上 _senders 里可能混有 VPN/蜂窝网卡的 socket，直接用 _senders.first 可能发不出去。
      final listener = _listener;
      if (listener != null) {
        try {
          listener.send(reply, datagram.address, discoveryPort);
          return;
        } catch (_) {
          // 发失败时继续走下面的兜底
        }
      }
      _senders.firstOrNull?.send(reply, datagram.address, discoveryPort);
    }
  }

  /// 回执里应填的本地 IP：优先选与对方同网段的网卡地址
  String _replyIp(String peerIp) {
    final dot = peerIp.lastIndexOf('.');
    if (dot > 0) {
      final prefix = peerIp.substring(0, dot + 1);
      for (final ip in _senderIps.values) {
        if (ip.startsWith(prefix)) return ip;
      }
    }
    return profileGetter().ip;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _listener?.close();
    _listener = null;
    for (final s in _senders) {
      s.close();
    }
    _senders.clear();
  }
}
