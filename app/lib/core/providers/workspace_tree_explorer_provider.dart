import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';

/// In-memory workspace tree exploration (expanded folders) for the projects tab.
class WorkspaceTreeExplorerState {
  const WorkspaceTreeExplorerState({
    this.expandedPaths = const {},
    this.workspaceId,
  });

  final Set<String> expandedPaths;
  final String? workspaceId;

  bool isExpanded(String path) => expandedPaths.contains(path);

  WorkspaceTreeExplorerState copyWith({
    Set<String>? expandedPaths,
    String? workspaceId,
    bool clearPaths = false,
  }) {
    return WorkspaceTreeExplorerState(
      expandedPaths: clearPaths ? const {} : (expandedPaths ?? this.expandedPaths),
      workspaceId: workspaceId ?? this.workspaceId,
    );
  }
}

final workspaceTreeExplorerProvider =
    NotifierProvider<WorkspaceTreeExplorerNotifier, WorkspaceTreeExplorerState>(
  WorkspaceTreeExplorerNotifier.new,
);

class WorkspaceTreeExplorerNotifier extends Notifier<WorkspaceTreeExplorerState> {
  @override
  WorkspaceTreeExplorerState build() {
    ref.listen(sessionProvider, (previous, next) {
      final prevId = previous?.valueOrNull?.activeWorkspaceId;
      final nextId = next.valueOrNull?.activeWorkspaceId;
      if (prevId != nextId) {
        state = WorkspaceTreeExplorerState(workspaceId: nextId, expandedPaths: const {});
      }
    });
    final workspaceId = ref.read(sessionProvider).valueOrNull?.activeWorkspaceId;
    return WorkspaceTreeExplorerState(workspaceId: workspaceId);
  }

  void toggleExpanded(String path) {
    final next = Set<String>.from(state.expandedPaths);
    if (next.contains(path)) {
      next.remove(path);
    } else {
      next.add(path);
    }
    state = state.copyWith(expandedPaths: next);
  }

  void setExpanded(String path, bool expanded) {
    final next = Set<String>.from(state.expandedPaths);
    if (expanded) {
      next.add(path);
    } else {
      next.remove(path);
    }
    state = state.copyWith(expandedPaths: next);
  }
}
