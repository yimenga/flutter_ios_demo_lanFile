import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../state/transfer_manager.dart';
import '../utils/format.dart';
import '../utils/platform_open.dart';
import '../widgets/image_preview_dialog.dart';

String _fmtTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class TransfersPage extends ConsumerWidget {
  const TransfersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(managerProvider);
    final tasks = manager.tasks;
    final active =
        tasks.where((t) => t.status == TransferStatus.transferring).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('传输'),
        centerTitle: true,
        actions: [
          if (tasks.any((t) => t.status != TransferStatus.transferring &&
              t.status != TransferStatus.waitingConfirm))
            TextButton(
              onPressed: () => ref.read(managerProvider).clearFinished(),
              child: const Text('清除记录'),
            ),
        ],
      ),
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.swap_vert, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    active > 0 ? '正在传输 $active 个任务' : '暂无传输任务',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text('在首页选择设备发送文件',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: tasks.length,
              itemBuilder: (_, i) => _TaskCard(task: tasks[i]),
            ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  final TransferTask task;

  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = task.totalBytes;
    final done = task.doneBytes;
    final progress = total > 0 ? done / total : 0.0;
    final incoming = task.direction == TransferDirection.incoming;
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    // 已完成的任务：取得可操作的目录与首个有效文件路径
    final canOpen = task.status == TransferStatus.completed;
    String? openDir;
    String? firstFilePath;
    if (canOpen) {
      firstFilePath = task.items
          .firstWhereOrNull((i) => i.path != null)
          ?.path;
      openDir = task.saveDir;
      if (openDir == null && firstFilePath != null) {
        openDir = File(firstFilePath).parent.path;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  incoming ? Icons.download : Icons.upload,
                  size: 18,
                  color: Colors.indigo,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${incoming ? '来自' : '发往'} ${task.peerName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                _statusChip(context, task.status),
              ],
            ),
            const SizedBox(height: 8),
            if (task.items.length == 1)
              Text(
                task.items.first.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              )
            else
              Text('${task.items.length} 个文件',
                  style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 2),
            Text(
              _fmtTime(task.startTime),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task.status == TransferStatus.completed ? 1 : progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${formatBytes(done)} / ${formatBytes(total)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),
                if (task.status == TransferStatus.transferring)
                  Text(
                    formatSpeed(task.speedBps),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
            if (task.error != null) ...[
              const SizedBox(height: 6),
              Text(
                task.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.red.shade400),
              ),
            ],
            if (task.status == TransferStatus.completed &&
                incoming &&
                task.saveDir != null) ...[
              const SizedBox(height: 6),
              Text(
                '已保存至：${task.saveDir}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (canOpen) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('打开目录'),
                    onPressed: openDir == null
                        ? null
                        : () => _openDir(context, openDir!),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('预览'),
                    onPressed: () => _preview(context, task),
                  ),
                  const Spacer(),
                  if (firstFilePath != null && isDesktop)
                    IconButton(
                      tooltip: '在文件管理器中定位',
                      icon: const Icon(Icons.my_location, size: 18),
                      onPressed: () => revealInFolder(firstFilePath!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openDir(BuildContext context, String dir) async {
    if (!await Directory(dir).exists()) {
      if (!context.mounted) return;
      _toast(context, '目录不存在：$dir');
      return;
    }
    try {
      await openDirectory(dir);
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, '打开目录失败：$e');
    }
  }

  Future<void> _preview(BuildContext context, TransferTask task) async {
    final items = task.items.where((i) => i.path != null).toList();
    if (items.isEmpty) {
      _toast(context, '暂无可预览文件');
      return;
    }
    if (items.length == 1) {
      await _previewOne(context, items.first.path!);
      return;
    }
    // 多文件：弹出选择
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: items.length,
          itemBuilder: (_, i) {
            final p = items[i].path!;
            final kind = classifyFile(p);
            return ListTile(
              leading: Icon(_iconFor(kind)),
              title: Text(items[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(formatBytes(items[i].size)),
              onTap: () => Navigator.pop(context, p),
            );
          },
        ),
      ),
    );
    if (pick != null && context.mounted) {
      await _previewOne(context, pick);
    }
  }

  Future<void> _previewOne(BuildContext context, String path) async {
    if (!await File(path).exists()) {
      if (!context.mounted) return;
      _toast(context, '文件已不存在：$path');
      return;
    }
    final kind = classifyFile(path);
    switch (kind) {
      case PreviewKind.image:
        if (!context.mounted) return;
        await showDialog(
          context: context,
          builder: (_) => ImagePreviewDialog(imagePath: path),
        );
        return;
      case PreviewKind.video:
      case PreviewKind.document:
        try {
          final r = await openWithDefault(path);
          if (r.type != ResultType.done && context.mounted) {
            _toast(context, '未找到可打开此文件的程序');
          }
        } catch (e) {
          if (!context.mounted) return;
          _toast(context, '打开失败：$e');
        }
        return;
      case PreviewKind.unknown:
        if (context.mounted) _toast(context, '未知文件,无法预览');
        return;
    }
  }

  IconData _iconFor(PreviewKind k) {
    switch (k) {
      case PreviewKind.image:
        return Icons.image_outlined;
      case PreviewKind.video:
        return Icons.movie_outlined;
      case PreviewKind.document:
        return Icons.description_outlined;
      case PreviewKind.unknown:
        return Icons.help_outline;
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _statusChip(BuildContext context, TransferStatus status) {
    (String, Color) info;
    switch (status) {
      case TransferStatus.waitingConfirm:
        info = ('等待对方确认', Colors.orange);
      case TransferStatus.transferring:
        info = ('传输中', Colors.blue);
      case TransferStatus.completed:
        info = ('已完成', Colors.green);
      case TransferStatus.failed:
        info = ('失败', Colors.red);
      case TransferStatus.rejected:
        info = ('被拒绝', Colors.red);
      case TransferStatus.timeout:
        info = ('超时', Colors.grey);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: info.$2.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        info.$1,
        style: TextStyle(fontSize: 11, color: info.$2),
      ),
    );
  }
}

extension _IterFirstWhere<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
