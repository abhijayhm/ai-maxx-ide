import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_models.dart';
import '../repositories/search_repository.dart';
import '../providers/app_providers.dart';
import 'search_provider.dart';
import 'sync_provider.dart';

final fileSearchProvider =
    FutureProvider.family<List<IndexedFileRow>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const [];
  }

  final session = await ref.watch(sessionProvider.future);
  final workspaceId = int.tryParse(session.activeWorkspaceId ?? '');
  if (workspaceId == null) {
    return const [];
  }

  final database = await ref.watch(appDatabaseProvider.future);
  final local = await database.searchFiles(workspaceId: workspaceId, query: trimmed);
  if (local.isNotEmpty) {
    return local;
  }

  final repo = await ref.watch(searchRepositoryProvider.future);
  final serverHits = await repo.searchFiles(trimmed);
  return serverHits
      .map(
        (hit) => IndexedFileRow(
          path: hit.path,
          name: hit.name,
          type: 'file',
          size: 0,
          syncPolicy: 'metadata_only',
          syncedAt: '',
        ),
      )
      .toList();
});

final indexedFileStatsProvider = FutureProvider<({int total, int withContent})>(
  (ref) async {
    final session = await ref.watch(sessionProvider.future);
    final workspaceId = int.tryParse(session.activeWorkspaceId ?? '');
    if (workspaceId == null) {
      return (total: 0, withContent: 0);
    }

    final database = await ref.watch(appDatabaseProvider.future);
    ref.watch(workspaceSyncProvider);

    final total = await database.countIndexedFiles(workspaceId);
    final withContent = await database.countSyncedContents(workspaceId);
    return (total: total, withContent: withContent);
  },
);
