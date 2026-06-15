import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/route_node.dart';
import '../repositories/ide_repository.dart';
import 'ide_index_provider.dart';

/// Lazy children cache for exposed-routes tree (workspace menu only).
class LazyRouteTreeState {
  const LazyRouteTreeState({
    this.childrenByPath = const {},
    this.loadingPaths = const {},
    this.loadedEmptyPaths = const {},
    this.error,
  });

  final Map<String, List<RouteNode>> childrenByPath;
  final Set<String> loadingPaths;
  final Set<String> loadedEmptyPaths;
  final String? error;

  bool isLoading(String path) => loadingPaths.contains(path);

  bool hasLoaded(String path) =>
      childrenByPath.containsKey(path) || loadedEmptyPaths.contains(path);

  List<RouteNode> childrenFor(String path, {List<RouteNode> fallback = const []}) {
    return childrenByPath[path] ?? fallback;
  }

  LazyRouteTreeState copyWith({
    Map<String, List<RouteNode>>? childrenByPath,
    Set<String>? loadingPaths,
    Set<String>? loadedEmptyPaths,
    String? error,
    bool clearError = false,
  }) {
    return LazyRouteTreeState(
      childrenByPath: childrenByPath ?? this.childrenByPath,
      loadingPaths: loadingPaths ?? this.loadingPaths,
      loadedEmptyPaths: loadedEmptyPaths ?? this.loadedEmptyPaths,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final lazyRouteTreeProvider =
    NotifierProvider<LazyRouteTreeNotifier, LazyRouteTreeState>(
  LazyRouteTreeNotifier.new,
);

class LazyRouteTreeNotifier extends Notifier<LazyRouteTreeState> {
  @override
  LazyRouteTreeState build() {
    ref.listen(ideIndexProvider.select((s) => s.exposedTree), (previous, next) {
      if (previous != next) {
        state = const LazyRouteTreeState();
      }
    });
    return const LazyRouteTreeState();
  }

  void clear() {
    state = const LazyRouteTreeState();
  }

  Future<List<RouteNode>> loadExposedChildren(
    String folderPath, {
    List<RouteNode> fallback = const [],
  }) async {
    if (state.hasLoaded(folderPath)) {
      return state.childrenFor(folderPath, fallback: fallback);
    }
    if (state.isLoading(folderPath)) {
      return state.childrenFor(folderPath, fallback: fallback);
    }

    state = state.copyWith(
      loadingPaths: {...state.loadingPaths, folderPath},
      clearError: true,
    );

    try {
      final repo = await ref.read(ideRepositoryProvider.future);
      final children = await repo.fetchExposedChildren(folderPath);

      final nextChildren = Map<String, List<RouteNode>>.from(state.childrenByPath);
      final nextEmpty = Set<String>.from(state.loadedEmptyPaths);
      if (children.isEmpty) {
        nextEmpty.add(folderPath);
      } else {
        nextChildren[folderPath] = children;
      }
      final nextLoading = Set<String>.from(state.loadingPaths)..remove(folderPath);
      state = state.copyWith(
        childrenByPath: nextChildren,
        loadedEmptyPaths: nextEmpty,
        loadingPaths: nextLoading,
      );
      return children;
    } catch (error) {
      final nextLoading = Set<String>.from(state.loadingPaths)..remove(folderPath);
      state = state.copyWith(
        loadingPaths: nextLoading,
        error: error.toString(),
      );
      rethrow;
    }
  }
}
