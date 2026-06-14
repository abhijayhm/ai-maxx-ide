import 'dart:async';
import 'dart:convert';

import '../config/app_config.dart';
import '../ws/ws_client.dart';
import 'terminal_models.dart';

typedef TerminalOutputCallback = void Function(String chunk);
typedef TerminalHistoryCallback = void Function(List<TerminalIOLine> lines);
typedef TerminalExitCallback = void Function(int code);
typedef TerminalErrorCallback = void Function(String code, String message);

/// WebSocket client for `/api/ws/terminals/{id}/`.
class TerminalClient {
  TerminalClient({
    required AppConfig config,
    required WsSessionHeaders Function() readHeaders,
    this.onOutput,
    this.onHistory,
    this.onExit,
    this.onError,
    this.onAttached,
  }) : _ws = WsClient(config: config, readHeaders: readHeaders);

  final TerminalOutputCallback? onOutput;
  final TerminalHistoryCallback? onHistory;
  final TerminalExitCallback? onExit;
  final TerminalErrorCallback? onError;
  final void Function(TerminalAttachInfo info)? onAttached;

  final WsClient _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _attached = false;

  bool get isConnected => _ws.isConnected;
  bool get isAttached => _attached;

  Future<void> connect(int sessionId) async {
    await disconnect();
    await _ws.connect('terminals/$sessionId/');
    _sub = _ws.messages.listen(_onFrame);
  }

  void _onFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String? ?? '';
    switch (type) {
      case 'attached':
        _attached = true;
        onAttached?.call(TerminalAttachInfo.fromJson(frame));
      case 'history':
        final raw = frame['lines'];
        if (raw is List) {
          final lines = raw
              .whereType<Map<String, dynamic>>()
              .map(TerminalIOLine.fromJson)
              .toList();
          onHistory?.call(lines);
        }
      case 'output':
        final raw = frame['data'] as String? ?? '';
        if (raw.isNotEmpty) {
          final bytes = base64Decode(raw);
          onOutput?.call(utf8.decode(bytes, allowMalformed: true));
        }
      case 'exit':
        _attached = false;
        onExit?.call(frame['code'] as int? ?? 0);
      case 'error':
        _attached = false;
        onError?.call(
          frame['code'] as String? ?? 'error',
          frame['message'] as String? ?? 'Terminal error',
        );
      case 'connection_closed':
        _attached = false;
    }
  }

  void sendInput(String text) {
    sendBytes(utf8.encode(text));
  }

  void sendBytes(List<int> bytes) {
    if (!_attached) {
      return;
    }
    _ws.send({
      'type': 'input',
      'data': base64Encode(bytes),
    });
  }

  void resize({required int cols, required int rows}) {
    if (!_attached) {
      return;
    }
    _ws.send({
      'type': 'resize',
      'cols': cols,
      'rows': rows,
    });
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _ws.disconnect();
    _attached = false;
  }
}
