import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models.dart';

enum TransferDirection { incoming, outgoing }

enum TransferStatus {
  waitingConfirm,
  transferring,
  completed,
  failed,
  rejected,
  timeout,
}

class TransferItem {
  final String name;
  final int size;
  int sent;
  String? path; // 接收端：保存路径；发送端：原始文件路径

  TransferItem({required this.name, required this.size, this.sent = 0, this.path});
}

class TransferTask {
  final String id;
  final String peerName;
  final String peerId;
  final TransferDirection direction;
  final List<TransferItem> items;
  TransferStatus status;
  String? saveDir;
  String? error;
  final DateTime startTime = DateTime.now();
  // 速度估算
  int _lastBytes = 0;
  DateTime _lastAt = DateTime.now();
  double speedBps = 0;

  TransferTask({
    required this.id,
    required this.peerName,
    required this.peerId,
    required this.direction,
    required this.items,
    this.status = TransferStatus.transferring,
  });

  int get totalBytes => items.fold(0, (s, i) => s + i.size);
  int get doneBytes => items.fold(0, (s, i) => s + i.sent);

  void tick(int bytesNow) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastAt).inMilliseconds;
    if (elapsed >= 500) {
      speedBps = (bytesNow - _lastBytes) / (elapsed / 1000);
      _lastBytes = bytesNow;
      _lastAt = now;
    }
  }
}

/// 接收方的确认结果
class ConfirmResult {
  final bool accepted;
  final int? trustDays; // null = 不信任；0 = 永久；>0 = 天数

  const ConfirmResult({required this.accepted, this.trustDays});
}

/// 待确认的接收请求
class PendingRequest {
  final String id;
  final DeviceProfile sender;
  final List<TransferItem> files;
  final DateTime createdAt = DateTime.now();
  final Completer<ConfirmResult> completer = Completer<ConfirmResult>();

  PendingRequest({
    required this.id,
    required this.sender,
    required this.files,
  });

  int get totalBytes => files.fold(0, (s, f) => s + f.size);
}

/// 传输任务与待确认请求的全局状态
class TransferManager extends ChangeNotifier {
  final List<TransferTask> tasks = [];
  final List<PendingRequest> pending = [];

  // ---------- 任务 ----------

  void addTask(TransferTask t) {
    tasks.insert(0, t);
    notifyListeners();
  }

  TransferTask? _byId(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void markTransferring(String id) {
    final t = _byId(id);
    if (t != null) {
      t.status = TransferStatus.transferring;
      notifyListeners();
    }
  }

  void completeTask(String id) {
    final t = _byId(id);
    if (t != null) {
      t.status = TransferStatus.completed;
      notifyListeners();
    }
  }

  void failTask(String id, String err) {
    final t = _byId(id);
    if (t != null) {
      t.status = TransferStatus.failed;
      t.error = err;
      notifyListeners();
    }
  }

  void rejectTask(String id) {
    final t = _byId(id);
    if (t != null) {
      t.status = TransferStatus.rejected;
      notifyListeners();
    }
  }

  void timeoutTask(String id) {
    final t = _byId(id);
    if (t != null) {
      t.status = TransferStatus.timeout;
      notifyListeners();
    }
  }

  void updateItemProgress(String taskId, int index, int bytes) {
    final t = _byId(taskId);
    if (t == null || index < 0 || index >= t.items.length) return;
    t.items[index].sent = bytes;
    t.tick(t.doneBytes);
    notifyListeners();
  }

  void setSaveDir(String taskId, String dir) {
    final t = _byId(taskId);
    if (t != null) {
      t.saveDir = dir;
      notifyListeners();
    }
  }

  void setItemPath(String taskId, int index, String path) {
    final t = _byId(taskId);
    if (t == null || index < 0 || index >= t.items.length) return;
    t.items[index].path = path;
    notifyListeners();
  }

  void clearFinished() {
    tasks.removeWhere(
      (t) =>
          t.status == TransferStatus.completed ||
          t.status == TransferStatus.failed ||
          t.status == TransferStatus.rejected ||
          t.status == TransferStatus.timeout,
    );
    notifyListeners();
  }

  // ---------- 待确认请求 ----------

  void addPending(PendingRequest p) {
    pending.add(p);
    notifyListeners();
  }

  void removePending(String id) {
    PendingRequest? p;
    for (final x in pending) {
      if (x.id == id) p = x;
    }
    if (p != null) {
      pending.remove(p);
      notifyListeners();
    }
  }

  void resolvePending(String id, ConfirmResult result) {
    PendingRequest? p;
    for (final x in pending) {
      if (x.id == id) p = x;
    }
    if (p == null) return;
    pending.remove(p);
    if (!p.completer.isCompleted) p.completer.complete(result);
    notifyListeners();
  }
}
