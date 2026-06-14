import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_client.dart';
import '../config/app_config.dart';
import 'agent_session_provider.dart';
import 'composer_settings_provider.dart';
import 'app_providers.dart';

export '../agent/agent_client.dart' show AgentEvent, AgentEventType;

class AgentState {
  const AgentState({
    this.messagesBySession = const {},
    this.running = false,
    this.runningSessionId,
    this.error,
  });

  final Map<int, List<AgentEvent>> messagesBySession;
  final bool running;
  final int? runningSessionId;
  final String? error;

  List<AgentEvent> messagesFor(int? sessionId) {
    if (sessionId == null) {
      return const [];
    }
    return messagesBySession[sessionId] ?? const [];
  }

  AgentState copyWith({
    Map<int, List<AgentEvent>>? messagesBySession,
    bool? running,
    int? runningSessionId,
    String? error,
    bool clearError = false,
    bool clearRunningSession = false,
  }) {
    return AgentState(
      messagesBySession: messagesBySession ?? this.messagesBySession,
      running: running ?? this.running,
      runningSessionId:
          clearRunningSession ? null : (runningSessionId ?? this.runningSessionId),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final agentProvider = NotifierProvider<AgentNotifier, AgentState>(
  AgentNotifier.new,
);

class AgentNotifier extends Notifier<AgentState> {
  AgentClient? _client;

  @override
  AgentState build() {
    ref.onDispose(_disconnect);
    return const AgentState();
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final sessionId = ref.read(agentSessionsProvider).activeId;
    if (sessionId == null) {
      await ref.read(agentSessionsProvider.notifier).ensureDefaultSession();
      final retryId = ref.read(agentSessionsProvider).activeId;
      if (retryId == null) {
        return;
      }
      return send(text);
    }

    await _ensureConnected();
    final settings = ref.read(composerSettingsProvider);
    final userEvent = AgentEvent(
      type: AgentEventType.stream,
      raw: const {},
      text: trimmed,
    );
    final bucket = [...state.messagesFor(sessionId), userEvent];
    state = state.copyWith(
      running: true,
      runningSessionId: sessionId,
      clearError: true,
      messagesBySession: {...state.messagesBySession, sessionId: bucket},
    );
    await _client!.sendMessage(
      trimmed,
      sessionId: sessionId,
      model: settings.effectiveModelId,
      agentMode: settings.agentModeForSend,
    );
  }

  Future<void> stop() async {
    final sessionId = ref.read(agentSessionsProvider).activeId;
    _client?.stop(sessionId: sessionId);
    state = state.copyWith(running: false, clearRunningSession: true);
  }

  Future<void> _ensureConnected() async {
    if (_client != null && _client!.isConnected) {
      return;
    }

    final session = await ref.read(sessionProvider.future);
    final config = ref.read(appConfigProvider);
    config.serverUrl = AppConfig.normalizeServerUrl(session.serverUrl);
    config.apiKey = session.apiKey;

    _client = AgentClient(
      config: config,
      readHeaders: () => (
        apiKey: session.apiKey,
        deviceHash: session.deviceHash,
        workspaceId: session.activeWorkspaceId,
      ),
    );
    _client!.listen(_onEvent);
    await _client!.connect();
  }

  void _onEvent(AgentEvent event) {
    final sessionId = ref.read(agentSessionsProvider).activeId;
    if (sessionId == null) {
      return;
    }

    final text = event.text;
    if (text != null && text.isNotEmpty) {
      final bucket = [...state.messagesFor(sessionId), event];
      state = state.copyWith(
        messagesBySession: {...state.messagesBySession, sessionId: bucket},
        running: _client?.isRunning ?? state.running,
        runningSessionId: sessionId,
      );
      return;
    }

    if (event.type == AgentEventType.runStarted) {
      state = state.copyWith(running: true, runningSessionId: sessionId);
      return;
    }

    if (event.type == AgentEventType.runFinished ||
        event.type == AgentEventType.stopped ||
        event.type == AgentEventType.error) {
      final bucket = state.messagesFor(sessionId);
      final nextBucket = text != null && text.isNotEmpty
          ? [...bucket, event]
          : bucket;
      state = state.copyWith(
        running: false,
        clearRunningSession: true,
        error: event.type == AgentEventType.error ? text : null,
        messagesBySession: {...state.messagesBySession, sessionId: nextBucket},
      );
    }
  }

  Future<void> _disconnect() async {
    await _client?.disconnect();
    _client = null;
  }
}
