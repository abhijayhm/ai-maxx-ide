import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../config/app_config.dart';
import '../db/app_database.dart';
import '../device_identifier.dart';

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig());

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  return AppDatabase.open();
});

final deviceIdentifierProvider = Provider<DeviceIdentifierService>((ref) {
  return DeviceIdentifierService();
});

final sessionProvider =
    AsyncNotifierProvider<SessionNotifier, SessionSnapshot>(
  SessionNotifier.new,
);

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final config = ref.watch(appConfigProvider);
  final deviceIdentifier = ref.watch(deviceIdentifierProvider);
  final session = await ref.watch(sessionProvider.future);

  final apiClient = ApiClient(
    config: config,
    readHeaders: () => (
      apiKey: session.apiKey,
      deviceHash: session.deviceHash,
      workspaceId: session.activeWorkspaceId,
    ),
  );

  return AuthRepository(
    apiClient: apiClient,
    database: database,
    deviceIdentifier: deviceIdentifier,
    config: config,
  );
});

class SessionNotifier extends AsyncNotifier<SessionSnapshot> {
  @override
  Future<SessionSnapshot> build() async {
    final database = await ref.watch(appDatabaseProvider.future);
    final config = ref.watch(appConfigProvider);
    final deviceIdentifier = ref.watch(deviceIdentifierProvider);
    final apiClient = ApiClient(
      config: config,
      readHeaders: () {
        final current = state.valueOrNull;
        return (
          apiKey: current?.apiKey ?? config.apiKey,
          deviceHash: current?.deviceHash,
          workspaceId: current?.activeWorkspaceId,
        );
      },
    );
    final auth = AuthRepository(
      apiClient: apiClient,
      database: database,
      deviceIdentifier: deviceIdentifier,
      config: config,
    );
    return auth.loadSession();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final auth = await ref.read(authRepositoryProvider.future);
      return auth.loadSession();
    });
  }

  Future<void> register(String apiKey) async {
    final auth = await ref.read(authRepositoryProvider.future);
    final snapshot = await auth.registerDevice(apiKey);
    state = AsyncData(snapshot);
    ref.invalidate(authRepositoryProvider);
  }

  Future<void> setWorkspace(int workspaceId) async {
    final auth = await ref.read(authRepositoryProvider.future);
    await auth.setActiveWorkspace(workspaceId);
    await refresh();
  }

  Future<void> openWorkspace(String absolutePath) async {
    final auth = await ref.read(authRepositoryProvider.future);
    await auth.openWorkspace(absolutePath);
    await refresh();
  }
}
