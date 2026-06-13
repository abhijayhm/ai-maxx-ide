import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../config/app_config.dart';
import '../db/app_database.dart';
import '../device_identifier.dart';
import 'sync_provider.dart';

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
    final snapshot = await _loadSessionSnapshot();
    _kickoffBackgroundSync(snapshot);
    return snapshot;
  }

  /// Loads session from local storage without depending on [authRepositoryProvider].
  ///
  /// [refresh] must not set [AsyncLoading]: [apiClientProvider] awaits
  /// [sessionProvider.future], so loading state would deadlock refresh and
  /// leave workspace open/select stuck on the spinner.
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

  Future<void> setWorkspace(int workspaceId) async {
    final auth = await ref.read(authRepositoryProvider.future);
    await auth.setActiveWorkspace(workspaceId);
    await refresh();
    ref.read(workspaceSyncProvider.notifier).start(workspaceId);
  }

  Future<void> openWorkspace(String absolutePath) async {
    final auth = await ref.read(authRepositoryProvider.future);
    final workspace = await auth.openWorkspace(absolutePath);
    await refresh();
    ref.read(workspaceSyncProvider.notifier).start(workspace.id);
  }

  void _kickoffBackgroundSync(SessionSnapshot snapshot) {
    final workspaceId = int.tryParse(snapshot.activeWorkspaceId ?? '');
    if (!snapshot.isReady || workspaceId == null) {
      return;
    }

    final syncState = ref.read(workspaceSyncProvider);
    if (syncState.isActive && syncState.workspaceId == workspaceId) {
      return;
    }

    Future.microtask(
      () => ref.read(workspaceSyncProvider.notifier).start(workspaceId),
    );
  }
}
