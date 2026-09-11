import 'dart:convert';

/// 设备档案：四端统一格式，用于 UDP 广播与 HTTP 握手
class DeviceProfile {
  final String id;
  final String name;
  final String type; // windows | macos | android | ios
  final String ip;
  final int port;
  final int ts;

  DeviceProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.ip,
    required this.port,
    int? ts,
  }) : ts = ts ?? DateTime.now().millisecondsSinceEpoch;

  bool get isDesktop => type == 'windows' || type == 'macos';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'ip': ip,
        'port': port,
        'ts': ts,
      };

  factory DeviceProfile.fromJson(Map<String, dynamic> j) => DeviceProfile(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '未知设备',
        type: (j['type'] as String?) ?? 'unknown',
        ip: (j['ip'] as String?) ?? '',
        port: (j['port'] as num?)?.toInt() ?? 45671,
        ts: (j['ts'] as num?)?.toInt(),
      );

  static DeviceProfile? tryParse(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) return DeviceProfile.fromJson(m);
    } catch (_) {}
    return null;
  }

  DeviceProfile copyWith({String? name, String? ip, int? port}) => DeviceProfile(
        id: id,
        name: name ?? this.name,
        type: type,
        ip: ip ?? this.ip,
        port: port ?? this.port,
      );

  Uri uri(String path) => Uri.parse('http://$ip:$port$path');
}
