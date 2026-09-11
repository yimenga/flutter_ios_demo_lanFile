import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _portCtrl;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _nicknameCtrl = TextEditingController(text: settings.nickname ?? '');
    _portCtrl = TextEditingController(text: settings.port.toString());
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final trust = ref.watch(trustProvider);
    final grants = trust.grants;
    final isDesktop = Platform.isWindows || Platform.isMacOS;

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionTitle(context, '本机'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('设备昵称'),
                  subtitle: const Text('其他设备看到的名称，留空使用系统默认', style: TextStyle(fontSize: 12)),
                  trailing: SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _nicknameCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: '默认',
                      ),
                      textAlign: TextAlign.end,
                      onChanged: (v) => settings.setNickname(v),
                      onSubmitted: (v) => settings.setNickname(v),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: const Text('服务端口'),
                  subtitle: const Text('修改后立即生效，其他设备需重新发现',
                      style: TextStyle(fontSize: 12)),
                  trailing: SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _portCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      textAlign: TextAlign.end,
                      keyboardType: TextInputType.number,
                      onSubmitted: (v) {
                        final port = int.tryParse(v.trim());
                        if (port != null && port > 1024 && port < 65536) {
                          settings.setPort(port);
                        } else {
                          _toast('端口无效，需在 1024-65535 之间');
                        }
                      },
                    ),
                  ),
                ),
                if (isDesktop) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: const Text('接收目录'),
                    subtitle: Text(
                      settings.receiveDir ?? '默认：下载/LanFile',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final dir = await FilePicker.getDirectoryPath(
                            initialDirectory: settings.receiveDir);
                        if (dir != null) settings.setReceiveDir(dir);
                      },
                      child: const Text('选择'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, '接收安全'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('仅接受已信任设备'),
                  subtitle: const Text('开启后，未信任设备的请求将被静默拒绝',
                      style: TextStyle(fontSize: 12)),
                  trailing: Switch(
                    value: settings.onlyTrusted,
                    onChanged: (v) => settings.setOnlyTrusted(v),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: const Text('默认信任时长'),
                  subtitle: const Text('勾选"信任此设备"时的默认有效期', style: TextStyle(fontSize: 12)),
                  trailing: DropdownButton<int>(
                    value: settings.defaultTrustDays,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 天')),
                      DropdownMenuItem(value: 7, child: Text('7 天')),
                      DropdownMenuItem(value: 30, child: Text('30 天')),
                      DropdownMenuItem(value: 0, child: Text('永久')),
                    ],
                    onChanged: (v) =>
                        v != null ? settings.setDefaultTrustDays(v) : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, '已信任设备 (${grants.length})'),
          if (grants.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    '暂无信任设备\n接收时勾选"信任此设备"后自动出现',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final g in grants)
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined,
                          color: Colors.green),
                      title: Text(g.deviceName),
                      subtitle: Text(
                        g.isForever
                            ? '永久信任'
                            : '有效期至 ${_fmtDate(g.expiryDate)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          trust.revokeDevice(g.deviceId);
                          setState(() {});
                        },
                        child: const Text('吊销'),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '闪传 LanDrop v1.0.0 · 局域网文件传输',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 6),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Colors.grey.shade700),
        ),
      );

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
