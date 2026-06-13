import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_models.dart';
import '../sync/workspace_sync_service.dart';
import '../config/app_config.dart';
import 'app_providers.dart';

final workspaceSyncProvider =
    NotifierProvider<WorkspaceSyncNotifier, SyncProgress>(
  WorkspaceSyncNotifier.new,
);

class WorkspaceSyncNotifier extends Notifier<SyncProgress> {
  WorkspaceSyncService? _service;
  Timer? _dismissTimer;

  @override
  SyncProgress build() {
    ref.onDispose(() {
      _dismissTimer?.cancel();
      _service?.cancel();
    });
    return const SyncProgress(phase: SyncPhase.idle);
  }

  /// Clears transient complete banner; keeps error state until retry.
  void dismissStatus() {
    if (state.phase == SyncPhase.complete) {
      state = const SyncProgress(phase: SyncPhase.idle);
    }
  }

  void retry() {
    final workspaceId = state.workspaceId;
    if (workspaceId != null) {
      start(workspaceId);
    }
  }

  /// Starts background sync; returns immediately (does not block UI).
  void start(int workspaceId) {
    if (state.isActive && state.workspaceId == workspaceId) {
      return;
    }

    _dismissTimer?.cancel();
    _service?.cancel();
    unawaited(_runSync(workspaceId));
  }

  Future<void> _runSync(int workspaceId) async {
    final database = await ref.read(appDatabaseProvider.future);
    final session = await ref.read(sessionProvider.future);
    final config = ref.read(appConfigProvider);
    config.serverUrl = AppConfig.normalizeServerUrl(session.serverUrl);
    config.apiKey = session.apiKey;

    final service = WorkspaceSyncService(
      config: config,
      readHeaders: () => (
        apiKey: session.apiKey,
        deviceHash: session.deviceHash,
        workspaceId: workspaceId.toString(),
      ),
      database: database,
      onProgress: (progress) {
        state = progress;
      },
    );
    _service = service;

    state = SyncProgress(
      phase: SyncPhase.metadata,
      workspaceId: workspaceId,
    );

    await service.syncWorkspace(workspaceId);

    if (state.phase == SyncPhase.complete) {
      _dismissTimer?.cancel();
      _dismissTimer = Timer(const Duration(seconds: 3), () {
        if (state.phase == SyncPhase.complete) {
          dismissStatus();
        }
      });
    }
  }
}
