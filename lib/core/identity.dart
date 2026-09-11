import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机身份：稳定设备 ID + 自动设备名（电脑显示用户名，手机显示型号）
class DeviceIdentity {
  late final String id;
  late final String type;
  late final String autoName;

  Future<void> init(SharedPreferences prefs) async {
    var saved = prefs.getString('device_id');
    if (saved == null || saved.isEmpty) {
      saved = randomToken(8);
      await prefs.setString('device_id', saved);
    }
    id = saved;
    type = Platform.operatingSystem; // windows | macos | android | ios

    // 自动设备名：首次运行计算后缓存，后续运行直接读取，避免每次启动变化
    final cached = prefs.getString('auto_name');
    if (cached != null && cached.isNotEmpty) {
      autoName = cached;
    } else {
      autoName = await _detectName();
      await prefs.setString('auto_name', autoName);
    }
  }

  Future<String> _detectName() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        final user = Platform.environment['USERNAME'] ?? '';
        if (user.isNotEmpty) return '$user 的电脑';
        return info.computerName;
      }
      if (Platform.isMacOS) {
        final info = await plugin.macOsInfo;
        return info.computerName;
      }
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final m = '${info.manufacturer} ${info.model}'.trim();
        return m.isNotEmpty ? m : 'Android 设备';
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final node = info.utsname.nodename;
        final model = _iosModelName(info.utsname.machine);
        if (node.isNotEmpty && node != 'localhost' && !node.contains('.')) {
          return '$node ($model)';
        }
        return model;
      }
    } catch (_) {}
    return Platform.localHostname;
  }

  static const _iosModels = {
    'iPhone10,1': 'iPhone 8',
    'iPhone10,3': 'iPhone X',
    'iPhone11,2': 'iPhone XS',
    'iPhone12,1': 'iPhone 11',
    'iPhone12,3': 'iPhone 11 Pro',
    'iPhone13,2': 'iPhone 12',
    'iPhone13,3': 'iPhone 12 Pro',
    'iPhone14,2': 'iPhone 13 Pro',
    'iPhone14,4': 'iPhone 13 mini',
    'iPhone14,5': 'iPhone 13',
    'iPhone14,7': 'iPhone 14',
    'iPhone14,8': 'iPhone 14 Plus',
    'iPhone15,2': 'iPhone 14 Pro',
    'iPhone15,3': 'iPhone 14 Pro Max',
    'iPhone15,4': 'iPhone 15',
    'iPhone15,5': 'iPhone 15 Plus',
    'iPhone16,1': 'iPhone 15 Pro',
    'iPhone16,2': 'iPhone 15 Pro Max',
    'iPhone17,1': 'iPhone 16 Pro',
    'iPhone17,2': 'iPhone 16 Pro Max',
    'iPhone17,3': 'iPhone 16',
    'iPhone17,4': 'iPhone 16 Plus',
    'iPhone17,5': 'iPhone 16e',
    'iPad13,1': 'iPad Air 4',
    'iPad13,4': 'iPad Pro 11 (M1)',
    'iPad14,1': 'iPad mini 6',
  };

  String _iosModelName(String machine) => _iosModels[machine] ?? machine;
}

/// 生成加密随机令牌
String randomToken(int bytes) {
  final r = Random.secure();
  final data = List<int>.generate(bytes, (_) => r.nextInt(256));
  return base64Url.encode(data).replaceAll('=', '');
}
