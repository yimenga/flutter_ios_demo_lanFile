
import 'package:flutter/foundation.dart';

import '../core/models.dart';

/// 发现的设备（含在线状态；手动添加的设备离线后仍保留）
class DiscoveredDevice {
  DeviceProfile profile;
  DateTime lastSeen;
  final bool manual;

  DiscoveredDevice({
    required this.profile,
    required this.lastSeen,
    this.manual = false,
  });

  bool get isOnline =>
      manual ||
      DateTime.now().difference(lastSeen).inSeconds < 8;
}

/// 设备注册表：合并自动发现与手动添加
class DeviceRegistry extends ChangeNotifier {
  final String myId;
  final Map<String, DiscoveredDevice> _devices = {};

  DeviceRegistry({required this.myId});

  void seen(DeviceProfile p) {
    if (p.id == myId || p.ip.isEmpty) return;
    final existing = _devices[p.id];
    if (existing == null) {
      _devices[p.id] = DiscoveredDevice(
        profile: p,
        lastSeen: DateTime.now(),
      );
      notifyListeners();
    } else {
      existing.lastSeen = DateTime.now();
      if (existing.profile.ip != p.ip ||
          existing.profile.name != p.name ||
          existing.profile.port != p.port) {
        existing.profile = p;
        notifyListeners();
      }
    }
  }

  void addManual(DeviceProfile p) {
    if (p.id == myId) return;
    final existing = _devices[p.id];
    _devices[p.id] = DiscoveredDevice(
      profile: p,
      lastSeen: existing?.lastSeen ?? DateTime.now(),
      manual: true,
    );
    notifyListeners();
  }

  void remove(String id) {
    if (_devices.remove(id) != null) notifyListeners();
  }

  /// 定期清理过期设备，返回是否有变化
  bool sweep() {
    final before = _devices.length;
    _devices.removeWhere(
      (_, d) => !d.manual && DateTime.now().difference(d.lastSeen).inSeconds >= 8,
    );
    if (_devices.length != before) {
      notifyListeners();
      return true;
    }
    return false;
  }

  List<DiscoveredDevice> get devices {
    final list = _devices.values.toList()
      ..sort((a, b) {
        final cmp = (b.isOnline ? 1 : 0).compareTo(a.isOnline ? 1 : 0);
        if (cmp != 0) return cmp;
        return a.profile.name.compareTo(b.profile.name);
      });
    return list;
  }

  DiscoveredDevice? byId(String id) => _devices[id];
}
