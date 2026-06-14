import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_repository.dart';
import '../config/app_config.dart';
import '../db/app_database.dart';
import '../device_identifier.dart';
import 'ide_index_provider.dart';
import 'ide_file_provider.dart';
import 'ide_search_provider.dart';
import 'watchdog_provider.dart';
import 'agent_session_provider.dart';
import 'composer_settings_provider.dart';
import 'global_loader_provider.dart';

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

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  ref.watch(sessionProvider);
  final session = ref.read(sessionProvider).valueOrNull;

  return ApiClient(
    config: config,
    readHeaders: () => (
      apiKey: session?.apiKey.isNotEmpty == true
          ? session!.apiKey
          : config.apiKey,
      deviceHash: session?.deviceHash,
      workspaceId: session?.activeWorkspaceId,
    ),
  );
});

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final config = ref.watch(appConfigProvider);
  final deviceIdentifier = ref.watch(deviceIdentifierProvider);
  final apiClient = ref.watch(apiClientProvider);

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
    if (!snapshot.isRegistered &&
        snapshot.hasStoredApiKey &&
        snapshot.apiKey.isNotEmpty) {
      snapshot = await _tryAutoRegister(snapshot);
    }
    Future.microtask(() => _kickoffIdeServices(snapshot));
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
  }

  Future<void> persistServerUrl(String serverUrl) async {
    final normalized = AppConfig.normalizeServerUrl(serverUrl);
    final database = await ref.read(appDatabaseProvider.future);
    await database.setSetting('server_url', normalized);
    ref.read(appConfigProvider).serverUrl = normalized;
  }

  Future<void> register(String apiKey, {required String serverUrl}) async {
    final normalizedUrl = AppConfig.normalizeServerUrl(serverUrl);
    final database = await ref.read(appDatabaseProvider.future);
    final config = ref.read(appConfigProvider);
    final deviceIdentifier = ref.read(deviceIdentifierProvider);

    await database.setSetting('server_url', normalizedUrl);
    config.serverUrl = normalizedUrl;
    config.apiKey = apiKey;

    final deviceHash = await deviceIdentifier.computeHash();
    final apiClient = ApiClient(
      config: config,
      readHeaders: () => (
        apiKey: apiKey,
        deviceHash: deviceHash,
        workspaceId: null,
      ),
    );
    final auth = AuthRepository(
      apiClient: apiClient,
      database: database,
      deviceIdentifier: deviceIdentifier,
      config: config,
    );

    final snapshot = await auth.registerDevice(apiKey, serverUrl: normalizedUrl);
    state = AsyncData(snapshot);
    Future.microtask(() => _kickoffIdeServices(snapshot));
  }

  Future<void> logout() async {
    final database = await ref.read(appDatabaseProvider.future);
    final config = ref.read(appConfigProvider);
    final deviceIdentifier = ref.read(deviceIdentifierProvider);
    final apiClient = ApiClient(
      config: config,
      readHeaders: () => (
        apiKey: config.apiKey,
        deviceHash: null,
        workspaceId: null,
      ),
    );
    final auth = AuthRepository(
      apiClient: apiClient,
      database: database,
      deviceIdentifier: deviceIdentifier,
      config: config,
    );
    final snapshot = await auth.logout();
    state = AsyncData(snapshot);
    await ref.read(watchdogProvider.notifier).disconnect();
    ref.read(globalLoaderProvider.notifier).reset();
    ref.read(ideFileProvider.notifier).close();
    ref.read(ideSearchProvider.notifier).search('');
  }

  Future<void> openWorkspace(String folderPath) async {
    final current = state.valueOrNull;
    if (current == null || !current.isAuthenticated) {
      throw StateError('Authenticate before opening a workspace.');
    }

    final database = await ref.read(appDatabaseProvider.future);
    final config = ref.read(appConfigProvider);
    final deviceIdentifier = ref.read(deviceIdentifierProvider);
    final apiClient = ApiClient(
      config: config,
      readHeaders: () => (
        apiKey: current.apiKey,
        deviceHash: current.deviceHash,
        workspaceId: current.activeWorkspaceId,
      ),
    );
    final auth = AuthRepository(
      apiClient: apiClient,
      database: database,
      deviceIdentifier: deviceIdentifier,
      config: config,
    );

    final workspace = await auth.openWorkspace(folderPath);
    final snapshot = await _loadSessionSnapshot();
    state = AsyncData(snapshot);
    Future.microtask(() async {
      await ref.read(ideIndexProvider.notifier).refreshWorkspace(
            workspace.id,
            background: true,
          );
      await _kickoffIdeServices(snapshot);
    });
  }

  Future<void> _kickoffIdeServices(SessionSnapshot snapshot) async {
    if (!snapshot.isAuthenticated) {
      return;
    }
    await ref.read(watchdogProvider.notifier).connect(session: snapshot);
    await ref.read(ideIndexProvider.notifier).refreshExposed(
          background: ref.read(ideIndexProvider).hasData,
          force: true,
        );
    if (snapshot.isReady) {
      await ref.read(agentSessionsProvider.notifier).ensureDefaultSession();
      await ref.read(composerSettingsProvider.notifier).loadModels();
    }
  }
}
