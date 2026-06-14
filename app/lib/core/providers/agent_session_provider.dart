import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_session.dart';
import '../repositories/agent_repository.dart';
import 'app_providers.dart';
import 'global_loader_provider.dart';

final agentRepositoryProvider = FutureProvider<AgentRepository>((ref) async {
  final api = ref.watch(apiClientProvider);
  return AgentRepository(api);
});

class AgentSessionsState {
  const AgentSessionsState({
    this.sessions = const [],
    this.activeId,
    this.loading = false,
    this.error,
  });

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
    List<AgentSessionInfo>? sessions,
    int? activeId,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return AgentSessionsState(
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
  bool _initialized = false;

  @override
  AgentSessionsState build() {
    ref.listen(sessionProvider, (previous, next) {
      final wasReady = previous?.valueOrNull?.isReady ?? false;
      final isReady = next.valueOrNull?.isReady ?? false;
      if (!wasReady && isReady) {
        _initialized = false;
        Future.microtask(ensureDefaultSession);
      }
    });
    Future.microtask(() {
      final session = ref.read(sessionProvider).valueOrNull;
      if (session?.isReady ?? false) {
        ensureDefaultSession();
      }
    });
    return const AgentSessionsState(loading: true);
  }

  Future<void> ensureDefaultSession() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await refresh();
    if (state.sessions.isEmpty) {
      await createSession(select: true);
    } else if (state.activeId == null) {
      state = state.copyWith(activeId: state.sessions.first.id);
    }
  }

  Future<void> refresh() async {
    final showLoader = state.sessions.isEmpty;
    state = state.copyWith(loading: true, clearError: true);
    final handle = showLoader
        ? ref.read(globalLoaderProvider.notifier).acquire('Loading agent sessions…')
        : null;
    try {
      final repo = await ref.read(agentRepositoryProvider.future);
      final sessions = await repo.fetchSessions();
      state = state.copyWith(
        sessions: sessions,
        loading: false,
        activeId:
            state.activeId ?? (sessions.isNotEmpty ? sessions.first.id : null),
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    } finally {
      handle?.release();
    }
  }

  Future<AgentSessionInfo?> createSession({bool select = true}) async {
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
      );
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
  }
}
