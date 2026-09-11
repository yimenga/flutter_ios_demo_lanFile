import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置（持久化到 SharedPreferences）
class AppSettings extends ChangeNotifier {
  final SharedPreferences prefs;

  String? nickname; // 空 = 使用自动设备名
  int port = 45671; // HTTP 服务端口
  String? interfaceIp; // 空 = 自动选择网卡
  String? receiveDir; // 空 = 默认下载目录
  int defaultTrustDays = 7; // 默认信任时长
  bool onlyTrusted = false; // 仅接受已信任设备

  AppSettings(this.prefs);

  Future<void> load() async {
    nickname = prefs.getString('nickname');
    port = prefs.getInt('port') ?? 45671;
    interfaceIp = prefs.getString('interface_ip');
    receiveDir = prefs.getString('receive_dir');
    defaultTrustDays = prefs.getInt('trust_days') ?? 7;
    onlyTrusted = prefs.getBool('only_trusted') ?? false;
  }

  Future<void> setNickname(String? v) async {
    nickname = (v == null || v.trim().isEmpty) ? null : v.trim();
    await prefs.setString('nickname', nickname ?? '');
    notifyListeners();
  }

  Future<void> setPort(int v) async {
    port = v;
    await prefs.setInt('port', v);
    notifyListeners();
  }

  Future<void> setInterfaceIp(String? v) async {
    interfaceIp = v;
    await prefs.setString('interface_ip', v ?? '');
    notifyListeners();
  }

  Future<void> setReceiveDir(String? v) async {
    receiveDir = v;
    await prefs.setString('receive_dir', v ?? '');
    notifyListeners();
  }

  Future<void> setDefaultTrustDays(int v) async {
    defaultTrustDays = v;
    await prefs.setInt('trust_days', v);
    notifyListeners();
  }

  Future<void> setOnlyTrusted(bool v) async {
    onlyTrusted = v;
    await prefs.setBool('only_trusted', v);
    notifyListeners();
  }
}
