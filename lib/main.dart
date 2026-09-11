import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_core.dart';
import 'core/identity.dart';
import 'core/trust.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/transfers_page.dart';
import 'state/providers.dart';
import 'state/registry.dart';
import 'state/settings.dart';
import 'state/transfer_manager.dart';
import 'widgets/incoming_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final settings = AppSettings(prefs);
  await settings.load();
  final identity = DeviceIdentity();
  await identity.init(prefs);
  final trust = TrustStore();
  await trust.load();

  // 安卓：申请存储权限（保存到 /storage/emulated/0/lanFile）+ 组播锁（接收 UDP 广播必需）
  if (Platform.isAndroid) {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
    try {
      await const MethodChannel('lanfile/native')
          .invokeMethod<bool>('acquireMulticastLock');
    } catch (e) {
      debugPrint('[main] multicast lock failed: $e');
    }
  }

  final manager = TransferManager();
  final registry = DeviceRegistry(myId: identity.id);
  final core = AppCore(
    settings: settings,
    identity: identity,
    trust: trust,
    manager: manager,
    registry: registry,
  );
  await core.start();

  runApp(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      settingsProvider.overrideWith((ref) => settings),
      identityProvider.overrideWithValue(identity),
      trustProvider.overrideWithValue(trust),
      managerProvider.overrideWith((ref) => manager),
      registryProvider.overrideWith((ref) => registry),
      coreProvider.overrideWithValue(core),
    ],
    child: const LanDropApp(),
  ));
}

class LanDropApp extends StatelessWidget {
  const LanDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '闪传',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3D5AFE),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  final _pages = const [
    HomePage(),
    TransfersPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _pages),
          const IncomingRequestGate(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wifi_tethering_outlined),
            selectedIcon: Icon(Icons.wifi_tethering),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_vert_outlined),
            selectedIcon: Icon(Icons.swap_vert),
            label: '传输',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
