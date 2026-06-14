import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../models/route_node.dart';
import '../repositories/ide_repository.dart';
import 'app_providers.dart';
import 'global_loader_provider.dart';

final ideRepositoryProvider = FutureProvider<IdeRepository>((ref) async {
  final api = ref.watch(apiClientProvider);
  return IdeRepository(api);
});

class IdeIndexState {
  const IdeIndexState({
    this.exposedTree = const [],
    this.exposedFlat = const [],
    this.workspaceTree,
    this.workspaceFlat = const [],
    this.loading = false,
    this.refreshing = false,
    this.loadedFromCache = false,
    this.error,
  });

  final List<RouteNode> exposedTree;
  final List<RouteNode> exposedFlat;
  final RouteNode? workspaceTree;
  final List<RouteNode> workspaceFlat;
  final bool loading;
  final bool refreshing;
  final bool loadedFromCache;
  final String? error;

  bool get hasData => exposedFlat.isNotEmpty || workspaceFlat.isNotEmpty;

  List<RouteNode> get searchable =>
      workspaceFlat.isNotEmpty ? workspaceFlat : exposedFlat;

  IdeIndexState copyWith({
    List<RouteNode>? exposedTree,
    List<RouteNode>? exposedFlat,
    RouteNode? workspaceTree,
    List<RouteNode>? workspaceFlat,
    bool? loading,
    bool? refreshing,
    bool? loadedFromCache,
    String? error,
    bool clearError = false,
    bool clearWorkspaceTree = false,
  }) {
    return IdeIndexState(
      exposedTree: exposedTree ?? this.exposedTree,
      exposedFlat: exposedFlat ?? this.exposedFlat,
      workspaceTree:
          clearWorkspaceTree ? null : (workspaceTree ?? this.workspaceTree),
      workspaceFlat: workspaceFlat ?? this.workspaceFlat,
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      loadedFromCache: loadedFromCache ?? this.loadedFromCache,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final ideIndexProvider =
    NotifierProvider<IdeIndexNotifier, IdeIndexState>(IdeIndexNotifier.new);

class IdeIndexNotifier extends Notifier<IdeIndexState> {
  bool _hydrated = false;
  bool _refreshInFlight = false;

  @override
  IdeIndexState build() {
    ref.listen(sessionProvider, (previous, next) {
      if (next.isLoading) {
        return;
      }
      final prevSession = previous?.valueOrNull;
      final nextSession = next.valueOrNull;

      final wasAuth = prevSession?.isAuthenticated ?? false;
      final isAuth = nextSession?.isAuthenticated ?? false;
      if (!wasAuth && isAuth) {
        _refreshInFlight = false;
      } else if (wasAuth && !isAuth) {
        state = const IdeIndexState();
      }

      final wasReady = prevSession?.isReady ?? false;
      final isReady = nextSession?.isReady ?? false;
      if (!wasReady && isReady) {
        refreshAll(background: state.hasData);
      }
    });
    Future.microtask(_hydrateFromCache);
    return const IdeIndexState(loading: true);
  }

  Future<void> _hydrateFromCache() async {
    if (_hydrated) {
      return;
    }
    _hydrated = true;

    try {
      final db = await ref.read(appDatabaseProvider.future);
      final session = ref.read(sessionProvider).valueOrNull;
      final workspaceId = int.tryParse(session?.activeWorkspaceId ?? '');

      final exposed = await db.loadRouteCache(AppDatabase.cacheKeyExposed);
      ({List<RouteNode> tree, List<RouteNode> flat})? workspace;
      if (workspaceId != null) {
        workspace = await db.loadRouteCache(
          AppDatabase.workspaceCacheKey(workspaceId),
        );
      }

      if (exposed != null || workspace != null) {
        state = state.copyWith(
          exposedTree: exposed?.tree ?? state.exposedTree,
          exposedFlat: exposed?.flat ?? state.exposedFlat,
          workspaceTree: workspace?.tree.isNotEmpty == true
              ? workspace!.tree.first
              : state.workspaceTree,
          workspaceFlat: workspace?.flat ?? state.workspaceFlat,
          loading: false,
          loadedFromCache: true,
          clearError: true,
        );
      } else {
        state = state.copyWith(loading: false);
      }
    } catch (_) {
      state = state.copyWith(loading: false);
    }

    final session = ref.read(sessionProvider).valueOrNull;
    if (session?.isReady ?? false) {
      await refreshAll(background: state.hasData);
    } else if (session?.isAuthenticated ?? false) {
      await refreshExposed(background: state.hasData);
    }
  }

  Future<void> forceRefresh() async {
    _refreshInFlight = false;
    await refreshAll(background: state.hasData);
  }

  Future<void> refreshAll({bool background = false}) async {
    await refreshExposed(background: background);
    final session = ref.read(sessionProvider).valueOrNull;
    final workspaceId = int.tryParse(session?.activeWorkspaceId ?? '');
    if (workspaceId != null) {
      await refreshWorkspace(workspaceId, background: background);
    }
  }

  Future<void> refreshExposed({
    bool background = false,
    bool force = false,
    String? loaderMessage,
  }) async {
    if (_refreshInFlight && !force) {
      return;
    }
    _refreshInFlight = true;
    final showLoader =
        !background && (loaderMessage != null || !state.hasData);
    final message = loaderMessage ?? 'Loading exposed paths…';
    LoaderHandle? handle;
    if (showLoader) {
      handle = ref.read(globalLoaderProvider.notifier).acquire(message);
    }
    state = state.copyWith(
      loading: !background && !state.hasData,
      refreshing: background || state.hasData,
      clearError: true,
    );
    try {
      final repo = await ref.read(ideRepositoryProvider.future);
      final roots = await repo.fetchExposedRoutesTree();
      final flat = flattenRouteTree(roots);
      final keepCached = background &&
          roots.isEmpty &&
          state.exposedFlat.isNotEmpty;
      if (keepCached) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
        );
      } else {
        state = state.copyWith(
          exposedTree: roots,
          exposedFlat: flat,
          loading: false,
          refreshing: false,
          loadedFromCache: false,
        );
        final db = await ref.read(appDatabaseProvider.future);
        await db.saveRouteCache(
          cacheKey: AppDatabase.cacheKeyExposed,
          tree: roots,
          flat: flat,
        );
      }
    } catch (error) {
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: state.hasData ? null : error.toString(),
      );
    } finally {
      _refreshInFlight = false;
      handle?.release();
    }
  }

  Future<void> refreshWorkspace(
    int workspaceId, {
    bool background = false,
    String? loaderMessage,
  }) async {
    final showLoader =
        !background && (loaderMessage != null || !state.hasData);
    final message = loaderMessage ?? 'Indexing workspace…';
    LoaderHandle? handle;
    if (showLoader) {
      handle = ref.read(globalLoaderProvider.notifier).acquire(message);
    }
    state = state.copyWith(
      loading: !background && !state.hasData,
      refreshing: background || state.hasData,
      clearError: true,
    );
    try {
      final repo = await ref.read(ideRepositoryProvider.future);
      final tree = await repo.fetchWorkspaceTree(workspaceId);
      final flat = flattenRouteTree([tree]);
      state = state.copyWith(
        workspaceTree: tree,
        workspaceFlat: flat,
        loading: false,
        refreshing: false,
        loadedFromCache: false,
      );
      final db = await ref.read(appDatabaseProvider.future);
      await db.saveRouteCache(
        cacheKey: AppDatabase.workspaceCacheKey(workspaceId),
        tree: [tree],
        flat: flat,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: state.hasData ? null : error.toString(),
      );
    } finally {
      handle?.release();
    }
  }

  Future<void> refreshAfterWatchdog() async {
    await refreshExposed(background: true);
    final session = ref.read(sessionProvider).valueOrNull;
    final workspaceId = int.tryParse(session?.activeWorkspaceId ?? '');
    if (workspaceId != null) {
      await refreshWorkspace(workspaceId, background: true);
    }
  }
}
