import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_session.dart';
import '../repositories/agent_repository.dart';
import '../db/app_database.dart';
import 'app_providers.dart';
import 'global_loader_provider.dart';

final agentRepositoryProvider = FutureProvider<AgentRepository>((ref) async {
  final api = ref.watch(apiClientProvider);
  return AgentRepository(api);
});

class AgentSessionsState {
  const AgentSessionsState({
    this.workspaceId,
    this.sessions = const [],
    this.activeId,
    this.loading = false,
    this.error,
  });

  final int? workspaceId;
  final List<AgentSessionInfo> sessions;
  final int? activeId;
  final bool loading;
  final String? error;

  AgentSessionInfo? get active {
    if (activeId == null) {
      return null;
    }
    for (final session in sessions) {
      if (session.id == activeId) {
        return session;
      }
    }
    return null;
  }

  AgentSessionsState copyWith({
    int? workspaceId,
    List<AgentSessionInfo>? sessions,
    int? activeId,
    bool? loading,
    String? error,
    bool clearError = false,
    bool clearWorkspace = false,
  }) {
    return AgentSessionsState(
      workspaceId: clearWorkspace ? null : (workspaceId ?? this.workspaceId),
      sessions: sessions ?? this.sessions,
      activeId: activeId ?? this.activeId,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final agentSessionsProvider =
    NotifierProvider<AgentSessionsNotifier, AgentSessionsState>(
  AgentSessionsNotifier.new,
);

class AgentSessionsNotifier extends Notifier<AgentSessionsState> {
  @override
  AgentSessionsState build() {
    ref.listen(sessionProvider, (previous, next) {
      final prevWs = _parseWorkspaceId(previous?.valueOrNull?.activeWorkspaceId);
      final nextWs = _parseWorkspaceId(next.valueOrNull?.activeWorkspaceId);
      final nextReady = next.valueOrNull?.isReady ?? false;
      if (prevWs != nextWs) {
        if (nextWs != null && nextReady) {
          unawaited(loadForWorkspace(nextWs));
        } else {
          state = const AgentSessionsState();
        }
      }
    });
    return const AgentSessionsState();
  }

  int? _parseWorkspaceId(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return int.tryParse(raw);
  }

  Future<void> ensureDefaultSession() async {
    final workspaceId =
        _parseWorkspaceId(ref.read(sessionProvider).valueOrNull?.activeWorkspaceId);
    if (workspaceId == null) {
      return;
    }
    await loadForWorkspace(workspaceId);
  }

  /// Fetch sessions for [workspaceId], restore last active, load its messages.
  Future<void> loadForWorkspace(int workspaceId) async {
    if (state.loading && state.workspaceId == workspaceId) {
      return;
    }

    final showLoader = state.sessions.isEmpty || state.workspaceId != workspaceId;
    state = AgentSessionsState(
      workspaceId: workspaceId,
      loading: true,
    );
    final handle = showLoader
        ? ref
            .read(globalLoaderProvider.notifier)
            .acquire('Loading agent sessions…')
        : null;
    try {
      final repo = await ref.read(agentRepositoryProvider.future);
      final sessions = await repo.fetchWorkspaceSessions(workspaceId);
      final activeId = await _resolveActiveSessionId(workspaceId, sessions);
      state = state.copyWith(
        sessions: sessions,
        loading: false,
        activeId: activeId,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    } finally {
      handle?.release();
    }
  }

  Future<int?> _resolveActiveSessionId(
    int workspaceId,
    List<AgentSessionInfo> sessions,
  ) async {
    if (sessions.isEmpty) {
      return null;
    }
    final db = await ref.read(appDatabaseProvider.future);
    final stored = int.tryParse(
      await db.getSetting(AppDatabase.activeAgentSessionKey(workspaceId)) ?? '',
    );
    if (stored != null && sessions.any((s) => s.id == stored)) {
      return stored;
    }
    final fallback = sessions.first.id;
    await db.setSetting(
      AppDatabase.activeAgentSessionKey(workspaceId),
      fallback.toString(),
    );
    return fallback;
  }

  Future<void> _persistActiveSession(int workspaceId, int sessionId) async {
    final db = await ref.read(appDatabaseProvider.future);
    await db.setSetting(
      AppDatabase.activeAgentSessionKey(workspaceId),
      sessionId.toString(),
    );
  }

  Future<AgentSessionInfo?> createSession({bool select = true}) async {
    final workspaceId = state.workspaceId ??
        _parseWorkspaceId(
          ref.read(sessionProvider).valueOrNull?.activeWorkspaceId,
        );
    if (workspaceId == null) {
      return null;
    }

    state = state.copyWith(loading: true, clearError: true);
    final handle =
        ref.read(globalLoaderProvider.notifier).acquire('Creating session…');
    try {
      final repo = await ref.read(agentRepositoryProvider.future);
      final created = await repo.createSession();
      final sessions = [created, ...state.sessions];
      state = state.copyWith(
        sessions: sessions,
        loading: false,
        activeId: select ? created.id : state.activeId,
        workspaceId: workspaceId,
      );
      if (select) {
        await _persistActiveSession(workspaceId, created.id);
      }
      return created;
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
      return null;
    } finally {
      handle.release();
    }
  }

  void selectSession(int id) {
    if (state.activeId == id) {
      return;
    }
    state = state.copyWith(activeId: id);
    final workspaceId = state.workspaceId;
    if (workspaceId != null) {
      unawaited(_persistActiveSession(workspaceId, id));
    }
  }
}
