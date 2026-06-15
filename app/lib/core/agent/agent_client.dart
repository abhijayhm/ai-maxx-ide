import 'dart:async';

import '../config/app_config.dart';
import '../ws/ws_client.dart';

/// Cursor agent WebSocket client (`/api/ws/agent/`).
class AgentClient {
  AgentClient({
    required AppConfig config,
    required WsSessionHeaders Function() readHeaders,
  }) : _ws = WsClient(config: config, readHeaders: readHeaders);

  final WsClient _ws;
  final _messages = <AgentEvent>[];
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _running = false;

  List<AgentEvent> get messages => List.unmodifiable(_messages);
  bool get isRunning => _running;
  bool get isConnected => _ws.isConnected;

  Future<void> connect() async {
    await _ws.connect('agent/');
  }

  Future<void> sendMessage(
    String text, {
    required int sessionId,
    String? model,
    String? agentMode,
  }) async {
    _running = true;
    _ws.send({
      'type': 'message',
      'text': text,
      'session_id': sessionId,
      if (model != null) 'model': model,
      if (agentMode != null) 'agent_mode': agentMode,
    });
  }

  void stop({int? sessionId}) {
    _ws.send({
      'type': 'stop',
      if (sessionId != null) 'session_id': sessionId,
    });
    _running = false;
  }

  void listen(void Function(AgentEvent event) onEvent) {
    _sub?.cancel();
    _sub = _ws.messages.listen((frame) {
      final event = AgentEvent.fromFrame(frame);
      if (event != null) {
        _messages.add(event);
        if (event.type == AgentEventType.stopped ||
            event.type == AgentEventType.error ||
            event.type == AgentEventType.runFinished) {
          _running = false;
        }
        onEvent(event);
      }
    });
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    await _ws.disconnect();
    _running = false;
  }
}

enum AgentEventType { stream, runStarted, runFinished, stopped, error, other }

class AgentEvent {
  const AgentEvent({
    required this.type,
    required this.raw,
    this.text,
  });

  final AgentEventType type;
  final Map<String, dynamic> raw;
  final String? text;

  static AgentEvent? fromFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String? ?? '';
    switch (type) {
      case 'stream':
        final message = frame['message'] as Map<String, dynamic>? ?? {};
        final text = frame['text'] as String? ??
            _extractAssistantText(message) ??
            message['text'] as String? ??
            message['content'] as String?;
        return AgentEvent(type: AgentEventType.stream, raw: frame, text: text);
      case 'run_started':
        return AgentEvent(type: AgentEventType.runStarted, raw: frame);
      case 'run_finished':
        return AgentEvent(
          type: AgentEventType.runFinished,
          raw: frame,
          text: frame['status'] as String? ?? 'completed',
        );
      case 'stopped':
        return AgentEvent(type: AgentEventType.stopped, raw: frame);
      case 'error':
        return AgentEvent(
          type: AgentEventType.error,
          raw: frame,
          text: frame['message'] as String?,
        );
      case 'connection_error':
      case 'connection_closed':
        return AgentEvent(
          type: AgentEventType.error,
          raw: frame,
          text: frame['message'] as String? ??
              (type == 'connection_closed'
                  ? 'Agent connection closed'
                  : 'Agent connection failed'),
        );
      default:
        return null;
    }
  }

  static AgentEvent? fromStoredMessage(
    String sender,
    Map<String, dynamic> payload,
  ) {
    if (sender == 'user') {
      final text = payload['text'] as String? ?? '';
      if (text.isEmpty) {
        return null;
      }
      return AgentEvent(type: AgentEventType.stream, raw: const {}, text: text);
    }
    final text = payload['text'] as String? ?? _extractAssistantText(payload);
    if (text != null && text.isNotEmpty) {
      return AgentEvent(
        type: AgentEventType.stream,
        raw: {'message': payload},
        text: text,
      );
    }
    return fromFrame({'type': 'stream', 'message': payload});
  }

  static String? _extractAssistantText(Map<String, dynamic> message) {
    final content = message['content'];
    if (content is! List) {
      final nested = message['message'];
      if (nested is Map<String, dynamic>) {
        return _extractAssistantText(nested);
      }
      return null;
    }
    final parts = <String>[];
    for (final block in content) {
      if (block is Map<String, dynamic> && block['type'] == 'text') {
        final text = block['text'] as String?;
        if (text != null && text.isNotEmpty) {
          parts.add(text);
        }
      }
    }
    return parts.isEmpty ? null : parts.join();
  }
}
