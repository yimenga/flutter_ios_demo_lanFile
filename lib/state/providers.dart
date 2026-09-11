import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_core.dart';
import '../core/identity.dart';
import '../core/models.dart';
import '../core/trust.dart';
import '../state/registry.dart';
import '../state/settings.dart';
import '../state/transfer_manager.dart';

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);

final settingsProvider = ChangeNotifierProvider<AppSettings>(
  (ref) => throw UnimplementedError(),
);

final identityProvider = Provider<DeviceIdentity>(
  (ref) => throw UnimplementedError(),
);

final trustProvider = Provider<TrustStore>(
  (ref) => throw UnimplementedError(),
);

final managerProvider = ChangeNotifierProvider<TransferManager>(
  (ref) => throw UnimplementedError(),
);

final registryProvider = ChangeNotifierProvider<DeviceRegistry>(
  (ref) => throw UnimplementedError(),
);

final coreProvider = Provider<AppCore>(
  (ref) => throw UnimplementedError(),
);

/// 本机档案（设置变化时自动刷新）
final myProfileProvider = Provider<DeviceProfile>((ref) {
  ref.watch(settingsProvider);
  return ref.watch(coreProvider).currentProfile();
});
