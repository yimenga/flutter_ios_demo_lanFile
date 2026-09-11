import 'dart:convert';
import 'dart:io';


import '../core/models.dart';
import '../core/trust.dart';
import '../core/identity.dart';
import '../state/transfer_manager.dart';

/// 发送端：握手 → 逐文件上传 → 完成通知
class TransferClient {
  final TransferManager manager;
  final TrustStore trust;
  final DeviceProfile Function() profileGetter;

  TransferClient({
    required this.manager,
    required this.trust,
    required this.profileGetter,
  });

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  Future<void> sendFiles({
    required DeviceProfile target,
    required List<File> files,
  }) async {
    final taskId = randomToken(8);
    final items = files
        .map((f) => TransferItem(
              name: _basename(f.path),
              size: f.lengthSync(),
              path: f.absolute.path,
            ))
        .toList();
    final task = TransferTask(
      id: taskId,
      peerName: target.name,
      peerId: target.id,
      direction: TransferDirection.outgoing,
      items: items,
      status: TransferStatus.waitingConfirm,
    );
    manager.addTask(task);

    try {
      final ok = await _handshake(target, taskId, items);
      if (!ok) return;

      for (var i = 0; i < files.length; i++) {
        await _uploadFile(target, taskId, i, files[i], items[i]);
      }
      await _postJson(target.uri('/api/complete'), {'requestId': taskId});
      manager.completeTask(taskId);
    } catch (e) {
      manager.failTask(taskId, e.toString());
    }
  }

  /// 探测手动添加的设备（GET /api/info）
  Future<DeviceProfile?> probe(String ip, int port) async {
    try {
      final req = await _http
          .openUrl('GET', Uri.parse('http://$ip:$port/api/info'))
          .timeout(const Duration(seconds: 3));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) return null;
      final text = await utf8.decoder.bind(resp).join();
      final data = jsonDecode(text);
      if (data is Map<String, dynamic>) {
        return DeviceProfile.fromJson(data).copyWith(ip: ip, port: port);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------- 握手 ----------

  Future<bool> _handshake(
    DeviceProfile target,
    String taskId,
    List<TransferItem> items,
  ) async {
    final token = trust.tokenFor(target.id);
    final body = {
      'requestId': taskId,
      'sender': profileGetter().toJson(),
      'files': items.map((i) => {'name': i.name, 'size': i.size}).toList(),
    };
    HttpClientResponse resp;
    try {
      final req = await _http.openUrl('POST', target.uri('/api/request'));
      req.headers.contentType = ContentType.json;
      if (token != null) req.headers.set('x-auth-token', token);
      req.write(jsonEncode(body));
      resp = await req.close();
    } on SocketException {
      // 目标不可达：令牌可能失效，清掉
      await trust.clearToken(target.id);
      rethrow;
    }

    final text = await utf8.decoder.bind(resp).join();
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (resp.statusCode == 200) {
      // 保存新令牌（接受并信任时服务端返回）
      final newToken = data['token'] as String?;
      if (newToken != null && newToken.isNotEmpty) {
        await trust.saveToken(target.id, newToken);
      }
      manager.markTransferring(taskId);
      return true;
    }
    if (resp.statusCode == 403) {
      await trust.clearToken(target.id); // 令牌被吊销/无效
      manager.rejectTask(taskId);
      return false;
    }
    if (resp.statusCode == 408) {
      manager.timeoutTask(taskId);
      return false;
    }
    throw Exception('握手失败 (HTTP ${resp.statusCode})');
  }

  // ---------- 上传 ----------

  Future<void> _uploadFile(
    DeviceProfile target,
    String taskId,
    int index,
    File file,
    TransferItem item,
  ) async {
    final uri = target.uri(
      '/api/file?requestId=$taskId&index=$index',
    );
    final req = await _http.openUrl('POST', uri);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');
    req.headers.set('x-file-name', Uri.encodeComponent(item.name));
    req.headers.set('x-file-size', item.size.toString());
    req.headers.contentLength = item.size;

    var sent = 0;
    var lastNotify = DateTime.now();
    final stream = file.openRead().map<List<int>>((chunk) {
      sent += chunk.length;
      final now = DateTime.now();
      if (now.difference(lastNotify).inMilliseconds >= 100) {
        manager.updateItemProgress(taskId, index, sent);
        lastNotify = now;
      }
      return chunk;
    });

    await req.addStream(stream);
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw Exception('上传失败: ${item.name} (HTTP ${resp.statusCode})');
    }
    manager.updateItemProgress(taskId, index, item.size);
  }

  Future<void> _postJson(Uri uri, Map<String, dynamic> body) async {
    final req = await _http.openUrl('POST', uri);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final resp = await req.close();
    await resp.drain<void>();
  }

  String _basename(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isEmpty || parts.last.isEmpty ? 'file' : parts.last;
  }
}
