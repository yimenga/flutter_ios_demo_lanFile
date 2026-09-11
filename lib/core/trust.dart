import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'identity.dart';

/// 一次信任授权（接收方颁发给发送方）
class TrustedGrant {
  final String token;
  final String deviceId;
  final String deviceName;
  final int expiresAt; // 毫秒时间戳；0 = 永久

  TrustedGrant({
    required this.token,
    required this.deviceId,
    required this.deviceName,
    required this.expiresAt,
  });

  bool get isForever => expiresAt == 0;
  bool get isExpired =>
      !isForever && DateTime.now().millisecondsSinceEpoch > expiresAt;

  DateTime get expiryDate =>
      DateTime.fromMillisecondsSinceEpoch(expiresAt);

  Map<String, dynamic> toJson() => {
        'token': token,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'expiresAt': expiresAt,
      };

  factory TrustedGrant.fromJson(Map<String, dynamic> j) => TrustedGrant(
        token: j['token'] as String,
        deviceId: j['deviceId'] as String,
        deviceName: (j['deviceName'] as String?) ?? '',
        expiresAt: (j['expiresAt'] as num?)?.toInt() ?? 0,
      );
}

/// 信任管理：
/// - 接收方：颁发 / 校验 / 吊销令牌（grants）
/// - 发送方：保存各设备令牌（tokens）
class TrustStore {
  static const _grantsKey = 'trust_grants';
  static const _tokensKey = 'trust_tokens';

  final _storage = const FlutterSecureStorage();

  final Map<String, TrustedGrant> _grants = {}; // token -> grant
  final Map<String, String> _tokens = {}; // deviceId -> token

  Future<void> load() async {
    try {
      final g = await _storage.read(key: _grantsKey);
      if (g != null) {
        final list = jsonDecode(g) as List;
        for (final e in list) {
          final grant = TrustedGrant.fromJson(e as Map<String, dynamic>);
          if (!grant.isExpired) _grants[grant.token] = grant;
        }
      }
      final t = await _storage.read(key: _tokensKey);
      if (t != null) {
        final m = jsonDecode(t) as Map<String, dynamic>;
        m.forEach((k, v) => _tokens[k] = v as String);
      }
    } catch (_) {}
  }

  Future<void> _persistGrants() async {
    await _storage.write(
      key: _grantsKey,
      value: jsonEncode(_grants.values.map((g) => g.toJson()).toList()),
    );
  }

  Future<void> _persistTokens() async {
    await _storage.write(key: _tokensKey, value: jsonEncode(_tokens));
  }

  // ---------- 接收方 ----------

  Future<String> issueGrant(String deviceId, String deviceName, int days) async {
    final token = randomToken(24);
    final expiresAt = days <= 0
        ? 0
        : DateTime.now()
            .add(Duration(days: days))
            .millisecondsSinceEpoch;
    // 同一设备旧令牌作废
    _grants.removeWhere((_, g) => g.deviceId == deviceId);
    _grants[token] = TrustedGrant(
      token: token,
      deviceId: deviceId,
      deviceName: deviceName,
      expiresAt: expiresAt,
    );
    await _persistGrants();
    return token;
  }

  /// 校验令牌：设备匹配且未过期才放行
  TrustedGrant? checkToken(String token, String deviceId) {
    final g = _grants[token];
    if (g == null || g.deviceId != deviceId) return null;
    if (g.isExpired) {
      _grants.remove(token);
      _persistGrants();
      return null;
    }
    return g;
  }

  Future<void> revokeDevice(String deviceId) async {
    _grants.removeWhere((_, g) => g.deviceId == deviceId);
    await _persistGrants();
  }

  List<TrustedGrant> get grants {
    final expired = _grants.values.where((g) => g.isExpired).toList();
    if (expired.isNotEmpty) {
      for (final g in expired) {
        _grants.remove(g.token);
      }
      _persistGrants();
    }
    return _grants.values.toList()
      ..sort((a, b) => a.deviceName.compareTo(b.deviceName));
  }

  // ---------- 发送方 ----------

  String? tokenFor(String deviceId) => _tokens[deviceId];

  Future<void> saveToken(String deviceId, String token) async {
    _tokens[deviceId] = token;
    await _persistTokens();
  }

  Future<void> clearToken(String deviceId) async {
    _tokens.remove(deviceId);
    await _persistTokens();
  }
}
