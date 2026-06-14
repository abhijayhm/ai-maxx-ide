import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_client.dart';
import '../config/app_config.dart';
import 'app_providers.dart';

export '../agent/agent_client.dart' show AgentEvent, AgentEventType;

class AgentState {
  const AgentState({
    this.messages = const [],
    this.running = false,
    this.error,
  });

  final List<AgentEvent> messages;
  final bool running;
  final String? error;

  AgentState copyWith({
    List<AgentEvent>? messages,
    bool? running,
    String? error,
    bool clearError = false,
  }) {
    return AgentState(
      messages: messages ?? this.messages,
      running: running ?? this.running,
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

    await _ensureConnected();
    state = state.copyWith(
      running: true,
      clearError: true,
      messages: [
        ...state.messages,
        AgentEvent(type: AgentEventType.stream, raw: const {}, text: trimmed),
      ],
    );
    await _client!.sendMessage(trimmed);
  }

  Future<void> sendContextRef(String contextRef) => send(contextRef);

  Future<void> stop() async {
    _client?.stop();
    state = state.copyWith(running: false);
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
    final text = event.text;
    if (text != null && text.isNotEmpty) {
      state = state.copyWith(
        messages: [...state.messages, event],
        running: _client?.isRunning ?? state.running,
      );
      return;
    }

    if (event.type == AgentEventType.runStarted) {
      state = state.copyWith(running: true);
      return;
    }

    if (event.type == AgentEventType.runFinished ||
        event.type == AgentEventType.stopped ||
        event.type == AgentEventType.error) {
      state = state.copyWith(
        running: false,
        error: event.type == AgentEventType.error ? text : null,
        messages: text != null && text.isNotEmpty
            ? [...state.messages, event]
            : state.messages,
      );
    }
  }

  Future<void> _disconnect() async {
    await _client?.disconnect();
    _client = null;
  }
}
