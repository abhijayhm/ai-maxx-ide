import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_models.dart';
import '../sync/workspace_sync_service.dart';
import 'app_providers.dart';

final workspaceSyncProvider =
    NotifierProvider<WorkspaceSyncNotifier, SyncProgress>(
  WorkspaceSyncNotifier.new,
);

class WorkspaceSyncNotifier extends Notifier<SyncProgress> {
  WorkspaceSyncService? _service;

  @override
  SyncProgress build() {
    ref.onDispose(() {
      _service?.cancel();
    });
    return const SyncProgress(phase: SyncPhase.idle);
  }

  Future<void> start(int workspaceId) async {
    _service?.cancel();

    final database = await ref.read(appDatabaseProvider.future);
    final apiClient = await ref.read(apiClientProvider.future);

    final service = WorkspaceSyncService(
      apiClient: apiClient,
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

    // Cursor agent bind runs in parallel; workspace unlock does not wait on it.
    unawaited(service.bindCursorInBackground(workspaceId));
    await service.syncWorkspace(workspaceId);
  }
}
