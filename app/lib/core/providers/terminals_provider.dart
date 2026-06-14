import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminals/terminal_client.dart';
import '../terminals/terminal_models.dart';
import '../terminals/terminal_repository.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';
import 'global_loader_provider.dart';

class TerminalsState {
  const TerminalsState({
    this.loading = false,
    this.sessions = const [],
    this.activeId,
    this.output = '',
    this.attached = false,
    this.error,
    this.shell,
    this.cwd,
  });

  final bool loading;
  final List<TerminalSession> sessions;
  final int? activeId;
  final String output;
  final bool attached;
  final String? error;
  final String? shell;
  final String? cwd;

  TerminalSession? get activeSession {
    if (activeId == null) {
      return null;
    }
    for (final s in sessions) {
      if (s.id == activeId) {
        return s;
      }
    }
    return null;
  }

  TerminalsState copyWith({
    bool? loading,
    List<TerminalSession>? sessions,
    int? activeId,
    bool clearActiveId = false,
    String? output,
    bool? attached,
    String? error,
    String? shell,
    String? cwd,
    bool clearError = false,
  }) {
    return TerminalsState(
      loading: loading ?? this.loading,
      sessions: sessions ?? this.sessions,
      activeId: clearActiveId ? null : (activeId ?? this.activeId),
      output: output ?? this.output,
      attached: attached ?? this.attached,
      error: clearError ? null : (error ?? this.error),
      shell: shell ?? this.shell,
      cwd: cwd ?? this.cwd,
    );
  }
}

final terminalsProvider =
    NotifierProvider<TerminalsNotifier, TerminalsState>(TerminalsNotifier.new);

class TerminalsNotifier extends Notifier<TerminalsState> {
  TerminalRepository? _repo;
  TerminalClient? _client;
  LoaderHandle? _loader;

  @override
  TerminalsState build() {
    ref.onDispose(_disconnect);
    return const TerminalsState();
  }

  TerminalRepository _repository() {
    return _repo ??= TerminalRepository(apiClient: ref.read(apiClientProvider));
  }

  WsSessionHeaders _headers() {
    final session = ref.read(sessionProvider).valueOrNull;
    final config = ref.read(appConfigProvider);
    return (
      apiKey: session?.apiKey.isNotEmpty == true
          ? session!.apiKey
          : config.apiKey,
      deviceHash: session?.deviceHash,
      workspaceId: session?.activeWorkspaceId,
    );
  }

  void _releaseLoader() {
    _loader?.release();
    _loader = null;
  }

  Future<void> refresh() async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session?.isReady != true) {
      return;
    }

    _releaseLoader();
    state = state.copyWith(loading: true, clearError: true);
    _loader = ref
        .read(globalLoaderProvider.notifier)
        .acquire('Loading terminals…');
    try {
      final sessions = await _repository().listActive();
      state = state.copyWith(loading: false, sessions: sessions);
      if (state.activeId == null && sessions.isNotEmpty) {
        await selectSession(sessions.first.id);
      } else if (state.activeId != null &&
          !sessions.any((s) => s.id == state.activeId)) {
        await _disconnect();
        state = state.copyWith(clearActiveId: true, output: '', attached: false);
      }
    } catch (error) {
      state = state.copyWith(
        loading: false,
        error: error.toString(),
      );
    } finally {
      _releaseLoader();
    }
  }

  Future<void> createSession() async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session?.isReady != true) {
      return;
    }

    _releaseLoader();
    state = state.copyWith(loading: true, clearError: true);
    _loader = ref
        .read(globalLoaderProvider.notifier)
        .acquire('Starting terminal…');
    try {
      final created = await _repository().create();
      final sessions = [...state.sessions, created];
      state = state.copyWith(loading: false, sessions: sessions);
      await selectSession(created.id);
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    } finally {
      _releaseLoader();
    }
  }

  Future<void> selectSession(int id) async {
    if (state.activeId == id && _client?.isAttached == true) {
      return;
    }

    await _disconnect();
    state = state.copyWith(
      activeId: id,
      output: '',
      attached: false,
      clearError: true,
    );

    final config = ref.read(appConfigProvider);
    _client = TerminalClient(
      config: config,
      readHeaders: _headers,
      onOutput: _appendOutput,
      onHistory: _applyHistory,
      onAttached: (info) {
        state = state.copyWith(
          attached: true,
          shell: info.shell,
          cwd: info.cwd,
        );
        _client?.resize(cols: info.cols, rows: info.rows);
      },
      onExit: (code) {
        state = state.copyWith(
          attached: false,
          output: '${state.output}\n[Process exited ($code)]\n',
        );
      },
      onError: (code, message) {
        state = state.copyWith(attached: false, error: '$code: $message');
      },
    );

    try {
      await _client!.connect(id);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  void _appendOutput(String chunk) {
    state = state.copyWith(output: state.output + chunk);
  }

  void _applyHistory(List<TerminalIOLine> lines) {
    final buffer = StringBuffer();
    for (final line in lines) {
      if (!line.isOutput || line.data.isEmpty) {
        continue;
      }
      try {
        buffer.write(utf8.decode(base64Decode(line.data), allowMalformed: true));
      } catch (_) {
        buffer.write(line.data);
      }
    }
    state = state.copyWith(output: buffer.toString());
  }

  void sendInput(String text) {
    _client?.sendInput(text);
  }

  void sendBackspace() {
    _client?.sendBytes([0x08]);
  }

  void resize({required int cols, required int rows}) {
    _client?.resize(cols: cols, rows: rows);
  }

  Future<void> closeSession(int id) async {
    try {
      await _repository().close(id);
    } catch (_) {}

    final sessions = state.sessions.where((s) => s.id != id).toList();
    if (state.activeId == id) {
      await _disconnect();
      final nextId = sessions.isNotEmpty ? sessions.first.id : null;
      state = state.copyWith(
        sessions: sessions,
        clearActiveId: nextId == null,
        activeId: nextId,
        output: '',
        attached: false,
      );
      if (nextId != null) {
        await selectSession(nextId);
      }
    } else {
      state = state.copyWith(sessions: sessions);
    }
  }

  Future<void> _disconnect() async {
    await _client?.disconnect();
    _client = null;
  }

  Future<void> disconnect() async {
    await _disconnect();
    state = state.copyWith(attached: false);
  }
}
