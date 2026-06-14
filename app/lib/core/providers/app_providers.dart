import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../config/app_config.dart';
import '../db/app_database.dart';
import '../device_identifier.dart';
import 'ide_index_provider.dart';
import 'watchdog_provider.dart';

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

final apiClientProvider = FutureProvider<ApiClient>((ref) async {
  final config = ref.watch(appConfigProvider);
  final session = await ref.watch(sessionProvider.future);

  return ApiClient(
    config: config,
    readHeaders: () => (
      apiKey: session.apiKey,
      deviceHash: session.deviceHash,
      workspaceId: session.activeWorkspaceId,
    ),
  );
});

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final config = ref.watch(appConfigProvider);
  final deviceIdentifier = ref.watch(deviceIdentifierProvider);
  final apiClient = await ref.watch(apiClientProvider.future);

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
    var snapshot = await _loadSessionSnapshot();
    if (!snapshot.isRegistered && snapshot.apiKey.isNotEmpty) {
      snapshot = await _tryAutoRegister(snapshot);
    }
    _kickoffIdeServices(snapshot);
    return snapshot;
  }

  Future<SessionSnapshot> _tryAutoRegister(SessionSnapshot snapshot) async {
    try {
      final database = await ref.read(appDatabaseProvider.future);
      final config = ref.read(appConfigProvider);
      config.apiKey = snapshot.apiKey;
      config.serverUrl = snapshot.serverUrl;
      final deviceIdentifier = ref.read(deviceIdentifierProvider);
      final apiClient = ApiClient(
        config: config,
        readHeaders: () => (
          apiKey: snapshot.apiKey,
          deviceHash: snapshot.deviceHash,
          workspaceId: snapshot.activeWorkspaceId,
        ),
      );
      final auth = AuthRepository(
        apiClient: apiClient,
        database: database,
        deviceIdentifier: deviceIdentifier,
        config: config,
      );
      return await auth.registerDevice(snapshot.apiKey);
    } catch (_) {
      return snapshot;
    }
  }

  Future<SessionSnapshot> _loadSessionSnapshot() async {
    final database = await ref.read(appDatabaseProvider.future);
    final config = ref.read(appConfigProvider);
    final deviceIdentifier = ref.read(deviceIdentifierProvider);
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
    final snapshot = await _loadSessionSnapshot();
    state = AsyncData(snapshot);
    ref.invalidate(apiClientProvider);
    ref.invalidate(authRepositoryProvider);
  }

  Future<void> register(String apiKey) async {
    final auth = await ref.read(authRepositoryProvider.future);
    final snapshot = await auth.registerDevice(apiKey);
    state = AsyncData(snapshot);
    ref.invalidate(authRepositoryProvider);
    ref.invalidate(apiClientProvider);
  }

  Future<void> openWorkspace(String folderPath) async {
    final auth = await ref.read(authRepositoryProvider.future);
    final workspace = await auth.openWorkspace(folderPath);
    await refresh();
    await ref.read(ideIndexProvider.notifier).refreshWorkspace(
          workspace.id,
          background: true,
        );
    await ref.read(watchdogProvider.notifier).connect();
  }

  void _kickoffIdeServices(SessionSnapshot snapshot) {
    if (!snapshot.isReady) {
      return;
    }
    Future.microtask(() async {
      await ref.read(watchdogProvider.notifier).connect();
    });
  }
}
