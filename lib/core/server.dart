import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';
import '../core/trust.dart';
import '../core/identity.dart';
import '../state/settings.dart';
import '../state/transfer_manager.dart';

/// 接收端 HTTP 服务：
/// GET  /api/info                 → 本机档案（手动添加设备时探测用）
/// POST /api/request              → 传输握手（令牌校验 / 弹窗确认）
/// POST /api/file?requestId&index → 分文件上传（流式落盘）
/// POST /api/complete             → 全部完成
class TransferServer {
  final TransferManager manager;
  final TrustStore trust;
  final AppSettings settings;
  final DeviceIdentity identity;
  final DeviceProfile Function() profileGetter;

  TransferServer({
    required this.manager,
    required this.trust,
    required this.settings,
    required this.identity,
    required this.profileGetter,
  });

  HttpServer? _server;

  Future<void> start() async {
    await stop();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, settings.port);
    _server!.listen(_handle, onError: (Object e) => debugPrint('[server] $e'));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/api/info') {
        _json(req, 200, profileGetter().toJson());
        return;
      }
      if (req.method == 'POST' && path == '/api/request') {
        await _handleRequest(req);
        return;
      }
      if (req.method == 'POST' && path == '/api/file') {
        await _handleFile(req);
        return;
      }
      if (req.method == 'POST' && path == '/api/complete') {
        await _handleComplete(req);
        return;
      }
      _json(req, 404, {'status': 'not_found'});
    } catch (e) {
      try {
        _json(req, 500, {'status': 'error', 'message': e.toString()});
      } catch (_) {}
    }
  }

  // ---------- 握手 ----------

  Future<void> _handleRequest(HttpRequest req) async {
    final body = await _readJson(req);
    final senderRaw = body['sender'];
    if (senderRaw is! Map<String, dynamic>) {
      _json(req, 400, {'status': 'bad_request'});
      return;
    }
    final sender = DeviceProfile.fromJson(senderRaw);
    final requestId = (body['requestId'] as String?) ?? randomToken(8);
    final files = <TransferItem>[];
    for (final f in (body['files'] as List? ?? [])) {
      if (f is Map<String, dynamic>) {
        files.add(TransferItem(
          name: (f['name'] as String?) ?? 'file',
          size: (f['size'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    if (files.isEmpty) {
      _json(req, 400, {'status': 'bad_request'});
      return;
    }

    // 1) 令牌路径：有效令牌直接免确认接收
    final token = req.headers.value('x-auth-token');
    if (token != null && token.isNotEmpty) {
      final grant = trust.checkToken(token, sender.id);
      if (grant != null) {
        _startReceiveTask(requestId, sender, files);
        _json(req, 200, {
          'status': 'accepted',
          'token': token,
          'requestId': requestId,
        });
        return;
      }
    }

    // 2) 仅信任模式：非信任设备静默拒绝
    if (settings.onlyTrusted) {
      _json(req, 403, {'status': 'rejected', 'reason': 'only_trusted'});
      return;
    }

    // 3) 弹窗确认
    final pendingReq = PendingRequest(
      id: requestId,
      sender: sender,
      files: files,
    );
    manager.addPending(pendingReq);
    try {
      final result = await pendingReq.completer.future
          .timeout(const Duration(seconds: 60));
      if (!result.accepted) {
        _json(req, 403, {'status': 'rejected'});
        return;
      }
      String? newToken;
      if (result.trustDays != null) {
        newToken = await trust.issueGrant(
          sender.id,
          sender.name,
          result.trustDays!,
        );
      }
      _startReceiveTask(requestId, sender, files);
      _json(req, 200, {
        'status': 'accepted',
        if (newToken != null) 'token': newToken,
        'requestId': requestId,
      });
    } on TimeoutException {
      manager.removePending(requestId);
      _json(req, 408, {'status': 'timeout'});
    }
  }

  void _startReceiveTask(
    String requestId,
    DeviceProfile sender,
    List<TransferItem> files,
  ) {
    manager.addTask(TransferTask(
      id: requestId,
      peerName: sender.name,
      peerId: sender.id,
      direction: TransferDirection.incoming,
      items: files,
    ));
  }

  // ---------- 文件上传 ----------

  Future<void> _handleFile(HttpRequest req) async {
    final requestId = req.uri.queryParameters['requestId'] ?? '';
    final index = int.tryParse(req.uri.queryParameters['index'] ?? '') ?? 0;
    final name = _sanitize(Uri.decodeFull(
      req.headers.value('x-file-name') ?? 'file',
    ));
    final size = int.tryParse(req.headers.value('x-file-size') ?? '') ?? 0;

    final root = await _receiveRoot();
    // 安卓直接存到 lanFile/日期/；桌面端为 下载/LanFile/日期/
    final dir = Directory(
      Platform.isAndroid
          ? p.join(root, _dateFolder())
          : p.join(root, 'LanFile', _dateFolder()),
    );
    await dir.create(recursive: true);
    final file = await _dedupe(dir, name);

    manager.setSaveDir(requestId, dir.path);
    manager.updateItemProgress(requestId, index, 0);

    var received = 0;
    var lastNotify = DateTime.now();
    final sink = file.openWrite();
    try {
      await for (final chunk in req) {
        received += chunk.length;
        sink.add(chunk);
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds >= 100) {
          manager.updateItemProgress(requestId, index, received);
          lastNotify = now;
        }
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close().catchError((_) {});
      manager.failTask(requestId, '接收中断: $e');
      _json(req, 500, {'status': 'error'});
      return;
    }
    manager.updateItemProgress(requestId, index, received);
    manager.setItemPath(requestId, index, file.path);
    _json(req, 200, {'status': 'ok', 'path': file.path, 'size': size});
  }

  Future<void> _handleComplete(HttpRequest req) async {
    final body = await _readJson(req);
    final requestId = body['requestId'] as String? ?? '';
    manager.completeTask(requestId);
    _json(req, 200, {'status': 'ok'});
  }

  // ---------- 工具 ----------

  Future<String> _receiveRoot() async {
    // 安卓：固定存到 /storage/emulated/0/lanFile/
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/lanFile');
      try {
        if (await dir.exists()) return dir.path;
        await dir.create(recursive: true);
        return dir.path;
      } catch (e) {
        debugPrint('[server] cannot use /storage/emulated/0/lanFile: $e');
      }
    }
    final configured = settings.receiveDir;
    if (configured != null && configured.isNotEmpty) return configured;
    if (Platform.isWindows || Platform.isMacOS) {
      final d = await getDownloadsDirectory();
      if (d != null) return d.path;
    }
    final appDoc = await getApplicationDocumentsDirectory();
    return appDoc.path;
  }

  String _dateFolder() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  String _sanitize(String name) {
    final base = p.basename(name).trim();
    return base.isEmpty ? 'file' : base;
  }

  Future<File> _dedupe(Directory dir, String name) async {
    var file = File(p.join(dir.path, name));
    if (!await file.exists()) return file;
    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    for (var i = 1; i < 1000; i++) {
      file = File(p.join(dir.path, '$stem ($i)$ext'));
      if (!await file.exists()) return file;
    }
    return File(p.join(dir.path, '${randomToken(4)}-$name'));
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
    if (text.isEmpty) return {};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  void _json(HttpRequest req, int status, Map<String, dynamic> data) {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(data));
    req.response.close();
  }
}
