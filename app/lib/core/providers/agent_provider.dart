import 'package:flutter_riverpod/flutter_riverpod.dart';

class AgentEvent {
  const AgentEvent({required this.type, this.text});

  final AgentEventType type;
  final String? text;
}

enum AgentEventType { message, error }

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

/// UI-only stub until agent WebSocket is reintroduced.
class AgentNotifier extends Notifier<AgentState> {
  @override
  AgentState build() => const AgentState();

  Future<void> stop() async {
    state = state.copyWith(running: false);
  }
}
