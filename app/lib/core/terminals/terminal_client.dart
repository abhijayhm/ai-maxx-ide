import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../ws/ws_client.dart';
import 'terminal_models.dart';
import 'terminal_output_sanitizer.dart';

typedef TerminalOutputCallback = void Function(String chunk);
typedef TerminalOutputFullCallback = void Function(String text);
typedef TerminalReadyCallback = void Function(TerminalAttachInfo info);
typedef TerminalExitCallback = void Function(int code);
typedef TerminalErrorCallback = void Function(String code, String message);
typedef TerminalBatchCallback = void Function();
typedef TerminalBatchCompleteCallback = void Function({
  int exitCode,
  bool timedOut,
  String batchOutput,
  String batchText,
});

/// WebSocket client for `/api/ws/terminals/{id}/` — one open connection, batch execute per message.
class TerminalClient {
  TerminalClient({
    required AppConfig config,
    required WsSessionHeaders Function() readHeaders,
    this.onOutput,
    this.onOutputFull,
    this.onReady,
    this.onBatchStarted,
    this.onBatchComplete,
    this.onExit,
    this.onError,
  }) : _ws = WsClient(config: config, readHeaders: readHeaders);

  final TerminalOutputCallback? onOutput;
  final TerminalOutputFullCallback? onOutputFull;
  final TerminalReadyCallback? onReady;
  final TerminalBatchCallback? onBatchStarted;
  final TerminalBatchCompleteCallback? onBatchComplete;
  final TerminalExitCallback? onExit;
  final TerminalErrorCallback? onError;

  final WsClient _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _ready = false;

  bool get isConnected => _ws.isConnected;
  bool get isReady => _ready;

  Future<void> connect(int sessionId) async {
    await disconnect();
    await _ws.connect('terminals/$sessionId/');
    _sub = _ws.messages.listen(_onFrame);
  }

  void _onFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String? ?? '';
    if (type == 'batch_started' ||
        type == 'batch_complete' ||
        type == 'error' ||
        type == 'ready' ||
        type == 'attached' ||
        type == 'exit' ||
        type == 'output') {
      final size = type == 'output'
          ? (frame['data'] as String? ?? '').length
          : null;
      debugPrint(
        '[TerminalClient] frame type=$type${size != null ? ' b64_len=$size' : ''}',
      );
    }
    switch (type) {
      case 'ready':
      case 'attached':
        _ready = true;
        onReady?.call(TerminalAttachInfo.fromJson(frame));
        break;
      case 'batch_started':
        onBatchStarted?.call();
        break;
      case 'batch_complete':
        final batchOutput = _decodeBatchOutput(frame['data'] as String?);
        onBatchComplete?.call(
          exitCode: frame['exit_code'] as int? ?? 0,
          timedOut: frame['timed_out'] == true,
          batchOutput: batchOutput,
          batchText: frame['text'] as String? ?? '',
        );
        break;
      case 'output':
        final raw = frame['data'] as String? ?? '';
        if (raw.isNotEmpty) {
          final bytes = base64Decode(raw);
          onOutput?.call(decodeTerminalBytes(bytes));
        }
        break;
      case 'output_full':
        final raw = frame['data'] as String? ?? '';
        if (raw.isNotEmpty) {
          final bytes = base64Decode(raw);
          onOutputFull?.call(decodeTerminalBytes(bytes));
        }
        break;
      case 'exit':
        _ready = false;
        onExit?.call(frame['code'] as int? ?? 0);
        break;
      case 'error':
        final code = frame['code'] as String? ?? 'error';
        onError?.call(
          code,
          frame['message'] as String? ?? 'Terminal error',
        );
        if (_isFatalError(code)) {
          _ready = false;
        }
        break;
      case 'connection_closed':
        _ready = false;
        break;
    }
  }

  static const _fatalErrorCodes = {
    'invalid_api_key',
    'device_not_registered',
    'workspace_required',
    'not_found',
    'terminal_closed',
    'invalid_json',
  };

  static bool _isFatalError(String code) => _fatalErrorCodes.contains(code);

  static bool isFatalError(String code) => _isFatalError(code);

  static String _decodeBatchOutput(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '';
    }
    try {
      return decodeTerminalBytes(base64Decode(raw));
    } catch (_) {
      return '';
    }
  }

  void execute(String text) {
    if (!_ready) {
      return;
    }
    final lineEnd = !kIsWeb && Platform.isWindows ? '\r\n' : '\n';
    final payload = text.endsWith('\n') || text.endsWith('\r\n')
        ? text
        : '$text$lineEnd';
    _ws.send({
      'type': 'execute',
      'data': base64Encode(utf8.encode(payload)),
    });
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _ws.disconnect();
    _ready = false;
  }
}
