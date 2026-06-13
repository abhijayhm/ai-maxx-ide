import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agent/agent_client.dart';
import '../config/app_config.dart';
import 'app_providers.dart';

class AgentState {
  const AgentState({
    this.messages = const [],
    this.connected = false,
    this.running = false,
    this.error,
  });

  final List<AgentEvent> messages;
  final bool connected;
  final bool running;
  final String? error;

  AgentState copyWith({
    List<AgentEvent>? messages,
    bool? connected,
    bool? running,
    String? error,
    bool clearError = false,
  }) {
    return AgentState(
      messages: messages ?? this.messages,
      connected: connected ?? this.connected,
      running: running ?? this.running,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Short user-facing message from verbose WebSocket / Dio errors.
String friendlyConnectionError(String raw) {
  if (raw.contains('was not upgraded to websocket') ||
      raw.contains('502') ||
      raw.contains('Bad Gateway')) {
    return 'Agent WebSocket failed — wait for workspace sync to finish, then retry.';
  }
  if (raw.contains('Connection refused') || raw.contains('Failed host lookup')) {
    return 'Cannot reach server — check tunnel and SERVER_DOMAIN.';
  }
  if (raw.length > 120) {
    return '${raw.substring(0, 117)}…';
  }
  return raw;
}

final agentProvider = NotifierProvider<AgentNotifier, AgentState>(
  AgentNotifier.new,
);

class AgentNotifier extends Notifier<AgentState> {
  AgentClient? _client;

  @override
  AgentState build() {
    ref.onDispose(() {
      _client?.disconnect();
    });
    return const AgentState();
  }

  Future<void> connect() async {
    if (_client != null && state.connected) {
      return;
    }

    final session = await ref.read(sessionProvider.future);
    if (!session.isReady) {
      return;
    }

    final config = ref.read(appConfigProvider);
    config.serverUrl = AppConfig.normalizeServerUrl(session.serverUrl);
    config.apiKey = session.apiKey;

    _client?.disconnect();
    _client = AgentClient(
      config: config,
      readHeaders: () => (
        apiKey: session.apiKey,
        deviceHash: session.deviceHash,
        workspaceId: session.activeWorkspaceId,
      ),
    );

    _client!.listen((event) {
      final isError = event.type == AgentEventType.error;
      state = state.copyWith(
        messages: [..._client!.messages],
        running: _client!.isRunning,
        connected: _client!.isConnected && !isError,
        error: isError ? friendlyConnectionError(event.text ?? 'Agent error') : null,
        clearError: !isError,
      );
    });

    try {
      await _client!.connect();
      if (!_client!.isConnected) {
        state = state.copyWith(
          connected: false,
          error: 'Agent WebSocket could not connect.',
        );
        return;
      }
      state = state.copyWith(connected: true, clearError: true);
    } catch (error) {
      state = state.copyWith(
        connected: false,
        error: friendlyConnectionError(error.toString()),
      );
    }
  }

  Future<void> send(String text) async {
    if (_client == null || !state.connected) {
      await connect();
    }
    if (!state.connected) {
      return;
    }
    state = state.copyWith(running: true, clearError: true);
    _client!.sendMessage(text);
  }

  Future<void> stop() async {
    _client?.stop();
    state = state.copyWith(running: false);
  }
}
