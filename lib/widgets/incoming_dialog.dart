import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../state/transfer_manager.dart';
import '../utils/format.dart';

/// 监听待确认请求并弹出接收确认对话框
class IncomingRequestGate extends ConsumerStatefulWidget {
  const IncomingRequestGate({super.key});

  @override
  ConsumerState<IncomingRequestGate> createState() =>
      _IncomingRequestGateState();
}

class _IncomingRequestGateState extends ConsumerState<IncomingRequestGate> {
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<TransferManager>(managerProvider, (prev, next) {
      if (!_showing && next.pending.isNotEmpty) {
        _showing = true;
        _showDialog(next.pending.first);
      }
    });
    return const SizedBox.shrink();
  }

  Future<void> _showDialog(PendingRequest request) async {
    final result = await showDialog<ConfirmResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncomingConfirmDialog(request: request),
    );
    _showing = false;
    ref
        .read(managerProvider)
        .resolvePending(request.id, result ?? const ConfirmResult(accepted: false));
  }
}

/// 接收确认弹窗：接受 / 拒绝 / 接受并信任
class IncomingConfirmDialog extends ConsumerStatefulWidget {
  final PendingRequest request;

  const IncomingConfirmDialog({super.key, required this.request});

  @override
  ConsumerState<IncomingConfirmDialog> createState() =>
      _IncomingConfirmDialogState();
}

class _IncomingConfirmDialogState extends ConsumerState<IncomingConfirmDialog> {
  int _trustDays = 7;
  bool _trust = false;
  bool _trustForever = false;

  @override
  Widget build(BuildContext context) {
    // 请求被移除（如超时）时自动关闭
    final stillPending =
        ref.watch(managerProvider).pending.any((p) => p.id == widget.request.id);
    if (!stillPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    }

    final sender = widget.request.sender;
    final files = widget.request.files;

    return AlertDialog(
      title: const Text('收到传输请求'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(deviceTypeIcon(sender.type), color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sender.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${sender.ip}:${sender.port}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const Divider(height: 20),
            Text(
              '${files.length} 个文件 · 共 ${formatBytes(widget.request.totalBytes)}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            ...files.take(5).map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file_outlined,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatBytes(f.size),
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
            if (files.length > 5)
              Text('…及其他 ${files.length - 5} 个文件',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _trust,
              onChanged: (v) => setState(() => _trust = v ?? false),
              title: const Text('信任此设备，期间免确认',
                  style: TextStyle(fontSize: 14)),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
            if (_trust)
              DropdownButtonFormField<int>(
                initialValue: _trustForever ? -1 : _trustDays,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('信任 1 天')),
                  DropdownMenuItem(value: 7, child: Text('信任 7 天')),
                  DropdownMenuItem(value: 30, child: Text('信任 30 天')),
                  DropdownMenuItem(value: -1, child: Text('永久信任')),
                ],
                onChanged: (v) => setState(() {
                  if (v == -1) {
                    _trustForever = true;
                  } else {
                    _trustForever = false;
                    _trustDays = v ?? 7;
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context)
              .pop(const ConfirmResult(accepted: false)),
          child: const Text('拒绝'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ConfirmResult(
            accepted: true,
            trustDays: _trust ? (_trustForever ? 0 : _trustDays) : null,
          )),
          child: const Text('接受'),
        ),
      ],
    );
  }
}
