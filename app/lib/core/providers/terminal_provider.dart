import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/terminal_repository.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';

final terminalRepositoryProvider = FutureProvider<TerminalRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return TerminalRepository(api);
});

class TerminalState {
  const TerminalState({
    this.sessions = const [],
    this.activeId,
    this.output = '',
    this.connected = false,
    this.loading = false,
    this.error,
  });

  final List<TerminalSession> sessions;
  final int? activeId;
  final String output;
  final bool connected;
  final bool loading;
  final String? error;

  TerminalState copyWith({
    List<TerminalSession>? sessions,
    int? activeId,
    String? output,
    bool? connected,
    bool? loading,
    String? error,
  }) {
    return TerminalState(
      sessions: sessions ?? this.sessions,
      activeId: activeId ?? this.activeId,
      output: output ?? this.output,
      connected: connected ?? this.connected,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

final terminalProvider =
    NotifierProvider<TerminalNotifier, TerminalState>(TerminalNotifier.new);

class TerminalNotifier extends Notifier<TerminalState> {
  WsClient? _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  TerminalState build() {
    ref.onDispose(_disconnect);
    return const TerminalState();
  }

  Future<TerminalRepository> _repo() =>
      ref.read(terminalRepositoryProvider.future);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final repo = await _repo();
      final sessions = await repo.list();
      state = state.copyWith(sessions: sessions, loading: false);
      if (state.activeId == null && sessions.isNotEmpty) {
        await select(sessions.first.id);
      }
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  Future<void> create() async {
    final repo = await _repo();
    final session = await repo.create();
    await refresh();
    await select(session.id);
  }

  Future<void> deleteActive() async {
    final id = state.activeId;
    if (id == null) {
      return;
    }
    await _disconnect();
    final repo = await _repo();
    await repo.delete(id);
    state = const TerminalState();
    await refresh();
  }

  Future<void> select(int id) async {
    await _disconnect();
    state = state.copyWith(activeId: id, output: '', connected: false);

    final config = ref.read(appConfigProvider);
    final session = ref.read(sessionProvider).valueOrNull;
    _ws = WsClient(
      config: config,
      readHeaders: () => (
        apiKey: session?.apiKey ?? config.apiKey,
        deviceHash: session?.deviceHash,
        workspaceId: session?.activeWorkspaceId,
      ),
    );

    await _ws!.connect('terminals/$id/');
    _sub = _ws!.messages.listen((frame) {
      final type = frame['type'] as String? ?? '';
      if (type == 'attached') {
        state = state.copyWith(connected: true);
      } else if (type == 'output') {
        final chunk = decodeTerminalOutput(frame);
        if (chunk != null) {
          state = state.copyWith(output: state.output + chunk);
        }
      } else if (type == 'exit') {
        state = state.copyWith(connected: false);
      } else if (type == 'error') {
        state = state.copyWith(
          error: frame['message'] as String? ?? 'Terminal error',
          connected: false,
        );
      }
    });
  }

  void sendInput(String text) {
    _ws?.send({
      'type': 'input',
      'data': encodeTerminalInput(text),
    });
  }

  Future<void> _disconnect() async {
    await _sub?.cancel();
    await _ws?.disconnect();
    _sub = null;
    _ws = null;
  }
}
