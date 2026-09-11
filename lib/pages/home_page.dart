import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../state/providers.dart';
import '../state/registry.dart';
import '../utils/format.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(registryProvider).devices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('闪传'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const _MyDeviceCard(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '发现的设备 (${devices.where((d) => d.isOnline).length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: devices.isEmpty
                ? const _EmptyDevices()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: devices.length,
                    itemBuilder: (_, i) => _DeviceTile(device: devices[i]),
                  ),
          ),
          const _ManualAddBar(),
        ],
      ),
    );
  }
}

/// 本机信息卡片：设备名 + 网卡/IP 选择 + 端口
class _MyDeviceCard extends ConsumerWidget {
  const _MyDeviceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(coreProvider);
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(myProfileProvider);

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(deviceTypeIcon(profile.type),
                    size: 40, color: Colors.indigo),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '本机 · ${deviceTypeLabel(profile.type)} · 端口 ${profile.port}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('传输网络：',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                const SizedBox(width: 4),
                Expanded(
                  child: Builder(builder: (context) {
                    // 去重并剔除无效保留值（防止下拉框断言失败）
                    final validIps = <String>{
                      for (final ip in core.interfaceIps)
                        if (!ip.startsWith('169.254')) ip,
                    };
                    final currentValue = settings.interfaceIp;
                    final safeValue = currentValue != null && validIps.contains(currentValue)
                        ? currentValue
                        : null;
                    return DropdownButtonFormField<String>(
                      initialValue: safeValue,
                      isDense: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('自动选择'),
                        ),
                        ...validIps.map((ip) => DropdownMenuItem(
                              value: ip,
                              child: Text(ip, style: const TextStyle(fontSize: 13)),
                            )),
                      ],
                      onChanged: (v) => settings.setInterfaceIp(v),
                    );
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_find, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('正在搜索附近设备…',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text('请确认对方也已打开闪传，且处于同一局域网',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

class _DeviceTile extends ConsumerStatefulWidget {
  final DiscoveredDevice device;

  const _DeviceTile({required this.device});

  @override
  ConsumerState<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends ConsumerState<_DeviceTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.device.profile;
    final online = widget.device.isOnline;

    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      color: _hovering ? Colors.indigo.shade100 : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              online ? Colors.indigo.shade50 : Colors.grey.shade200,
          child: Icon(
            deviceTypeIcon(p.type),
            color: online ? Colors.indigo : Colors.grey,
          ),
        ),
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${p.ip}:${p.port} · ${deviceTypeLabel(p.type)}'
          '${widget.device.manual ? ' · 手动添加' : ''}'
          '${(Platform.isWindows || Platform.isMacOS) && online ? ' · 可拖拽文件到此' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: online
            ? const Icon(Icons.send_outlined)
            : Text('离线',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        onTap: online ? () => _pickAndSend(context, ref, p) : null,
        onLongPress: () => _showActions(context, ref, widget.device),
      ),
    );

    // 桌面端支持拖拽文件直接发送
    if ((Platform.isWindows || Platform.isMacOS) && online) {
      return DropTarget(
        onDragEntered: (_) => setState(() => _hovering = true),
        onDragExited: (_) => setState(() => _hovering = false),
        onDragDone: (details) {
          setState(() => _hovering = false);
          final files = details.files
              .where((f) => f.path.isNotEmpty)
              .map((f) => File(f.path))
              .toList();
          if (files.isNotEmpty) _sendFiles(context, ref, p, files);
        },
        child: card,
      );
    }
    return card;
  }

  void _sendFiles(BuildContext context, WidgetRef ref, DeviceProfile target,
      List<File> files) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('正在向 ${target.name} 发送 ${files.length} 个文件…'),
      duration: const Duration(seconds: 1),
    ));
    ref.read(coreProvider).client.sendFiles(target: target, files: files);
  }

  Future<void> _pickAndSend(
      BuildContext context, WidgetRef ref, DeviceProfile target) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('发送图片 / 视频'),
              onTap: () => Navigator.pop(context, 'media'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('发送任意文件'),
              onTap: () => Navigator.pop(context, 'any'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    final picked = choice == 'media'
        ? await FilePicker.pickFiles(
            type: FileType.media,
            allowMultiple: true,
          )
        : await FilePicker.pickFiles(allowMultiple: true);
    if (picked.isEmpty) return;

    final files = picked
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();
    if (files.isEmpty || !context.mounted) return;
    _sendFiles(context, ref, target, files);
  }

  void _showActions(BuildContext context, WidgetRef ref, DiscoveredDevice d) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(d.profile.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    '${d.profile.ip}:${d.profile.port}\n设备ID: ${d.profile.id}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (d.manual)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('移除此设备'),
                onTap: () {
                  ref.read(registryProvider).remove(d.profile.id);
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('关闭'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// 手动添加设备（跨网段 / 广播被禁用时）
class _ManualAddBar extends ConsumerStatefulWidget {
  const _ManualAddBar();

  @override
  ConsumerState<_ManualAddBar> createState() => _ManualAddBarState();
}

class _ManualAddBarState extends ConsumerState<_ManualAddBar> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    var ip = raw;
    var port = 45671;
    if (raw.contains(':')) {
      final parts = raw.split(':');
      ip = parts[0];
      port = int.tryParse(parts[1]) ?? 45671;
    }
    final ipObj = InternetAddress.tryParse(ip);
    if (ipObj == null || ipObj.type != InternetAddressType.IPv4) {
      _toast('IP 格式不正确');
      return;
    }

    setState(() => _busy = true);
    final core = ref.read(coreProvider);
    final profile = await core.client.probe(ip, port);
    setState(() => _busy = false);

    if (profile == null) {
      _toast('无法连接 $ip:$port，请确认对方已开启闪传');
      return;
    }
    ref.read(registryProvider).addManual(profile);
    _controller.clear();
    _toast('已添加 ${profile.name}');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: '手动添加：输入对方 IP 或 IP:端口',
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _busy ? null : _add,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('添加'),
          ),
        ],
      ),
    );
  }
}

