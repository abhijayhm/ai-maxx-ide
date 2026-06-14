import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminals/terminal_client.dart';
import '../terminals/terminal_models.dart';
import '../terminals/terminal_output_sanitizer.dart';
import '../terminals/terminal_repository.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';
import 'global_loader_provider.dart';

class TerminalsState {
  const TerminalsState({
    this.loading = false,
    this.sessions = const [],
    this.activeId,
    this.transcript = '',
    this.attached = false,
    this.executing = false,
    this.error,
    this.shell,
    this.cwd,
    this.pid,
  });

  final bool loading;
  final List<TerminalSession> sessions;
  final int? activeId;
  final String transcript;
  final bool attached;
  final bool executing;
  final String? error;
  final String? shell;
  final String? cwd;
  final int? pid;

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
    String? transcript,
    bool? attached,
    bool? executing,
    String? error,
    String? shell,
    String? cwd,
    int? pid,
    bool clearPid = false,
    bool clearError = false,
  }) {
    return TerminalsState(
      loading: loading ?? this.loading,
      sessions: sessions ?? this.sessions,
      activeId: clearActiveId ? null : (activeId ?? this.activeId),
      transcript: transcript ?? this.transcript,
      attached: attached ?? this.attached,
      executing: executing ?? this.executing,
      error: clearError ? null : (error ?? this.error),
      shell: shell ?? this.shell,
      cwd: cwd ?? this.cwd,
      pid: clearPid ? null : (pid ?? this.pid),
    );
  }
}

final terminalsProvider =
    NotifierProvider<TerminalsNotifier, TerminalsState>(TerminalsNotifier.new);

class TerminalsNotifier extends Notifier<TerminalsState> {
  TerminalRepository? _repo;
  TerminalClient? _client;
  LoaderHandle? _loader;
  Timer? _executeTimeout;

  int _batchTranscriptStart = 0;
  String _liveBatchRaw = '';

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

  String _prefix() {
    final len = state.transcript.length;
    final start = _batchTranscriptStart.clamp(0, len);
    return state.transcript.substring(0, start);
  }

  String _displayRaw(String raw) => sanitizeTerminalOutput(raw);

  void _setBatchTranscript(String raw) {
    final display = _displayRaw(raw);
    final prefix = _prefix();
    state = state.copyWith(transcript: '$prefix$display');
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
        state = state.copyWith(
          clearActiveId: true,
          transcript: '',
          attached: false,
        );
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

  Future<void> createSession({required String shell}) async {
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
      final created = await _repository().create(shell: shell);
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
    if (state.activeId == id && _client?.isReady == true) {
      return;
    }

    await _disconnect();
    _batchTranscriptStart = 0;
    _liveBatchRaw = '';
    state = state.copyWith(
      activeId: id,
      transcript: '',
      attached: false,
      executing: false,
      clearError: true,
      clearPid: true,
    );

    final config = ref.read(appConfigProvider);
    _client = TerminalClient(
      config: config,
      readHeaders: _headers,
      onOutput: _appendOutput,
      onOutputFull: _bootstrapOutput,
      onBatchStarted: () {
        _clearExecuteTimeout();
        _batchTranscriptStart = state.transcript.length;
        _liveBatchRaw = '';
        state = state.copyWith(executing: true, clearError: true);
        debugPrint('[Terminals] batch_started');
      },
      onBatchComplete: ({
        int exitCode = 0,
        bool timedOut = false,
        String batchOutput = '',
        String batchText = '',
      }) {
        _clearExecuteTimeout();
        _finishBatch(
          exitCode: exitCode,
          timedOut: timedOut,
          batchOutput: batchOutput,
        );
        state = state.copyWith(executing: false);
        debugPrint('[Terminals] batch_complete exit=$exitCode');
      },
      onReady: (info) {
        state = state.copyWith(
          attached: true,
          shell: info.shell,
          cwd: info.cwd,
          pid: info.pid,
        );
      },
      onExit: (code) {
        _clearExecuteTimeout();
        _finishBatch();
        state = state.copyWith(attached: false, executing: false, clearPid: true);
      },
      onError: (code, message) {
        final fatal = TerminalClient.isFatalError(code);
        _clearExecuteTimeout();
        _finishBatch();
        state = state.copyWith(
          attached: fatal ? false : state.attached,
          executing: false,
          clearPid: fatal,
          error: '$code: $message',
        );
      },
    );

    try {
      await _client!.connect(id);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  void _bootstrapOutput(String text) {
    if (text.isEmpty) {
      return;
    }
    final cleaned = _displayRaw(text);
    if (cleaned.isEmpty) {
      return;
    }
    state = state.copyWith(transcript: cleaned);
    _batchTranscriptStart = state.transcript.length;
  }

  void _appendOutput(String chunk) {
    if (chunk.isEmpty || !state.executing) {
      return;
    }
    _liveBatchRaw += chunk;
    _setBatchTranscript(_liveBatchRaw);
  }

  void _finishBatch({
    int exitCode = 0,
    bool timedOut = false,
    String batchOutput = '',
  }) {
    if (!state.executing && _liveBatchRaw.isEmpty && batchOutput.isEmpty) {
      return;
    }

    final raw = batchOutput.length >= _liveBatchRaw.length
        ? batchOutput
        : _liveBatchRaw;

    if (raw.isNotEmpty) {
      _setBatchTranscript(raw);
    } else if (timedOut) {
      state = state.copyWith(transcript: '${state.transcript}(timed out)\n');
    } else if (exitCode != 0) {
      state = state.copyWith(transcript: '${state.transcript}(command failed)\n');
    }

    // Ensure each batch ends on a new line in the scrollback.
    if (state.transcript.isNotEmpty && !state.transcript.endsWith('\n')) {
      state = state.copyWith(transcript: '${state.transcript}\n');
    }

    _liveBatchRaw = '';
    _batchTranscriptStart = state.transcript.length;
  }

  void _clearExecuteTimeout() {
    _executeTimeout?.cancel();
    _executeTimeout = null;
  }

  void sendInput(String text) {
    if (text.isEmpty || _client?.isReady != true) {
      return;
    }
    state = state.copyWith(executing: true, clearError: true);
    _client!.execute(text);
    _clearExecuteTimeout();
    _executeTimeout = Timer(const Duration(seconds: 125), () {
      if (state.executing) {
        debugPrint('[Terminals] execute timeout — forcing executing=false');
        _finishBatch();
        state = state.copyWith(
          executing: false,
          error: 'Command timed out waiting for server',
        );
      }
    });
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
        transcript: '',
        attached: false,
        executing: false,
        clearPid: true,
      );
      if (nextId != null) {
        await selectSession(nextId);
      }
    } else {
      state = state.copyWith(sessions: sessions);
    }
  }

  Future<void> _disconnect() async {
    _clearExecuteTimeout();
    await _client?.disconnect();
    _client = null;
    _liveBatchRaw = '';
    _batchTranscriptStart = 0;
  }

  Future<void> disconnect() async {
    await _disconnect();
    state = state.copyWith(attached: false, clearPid: true);
  }
}
