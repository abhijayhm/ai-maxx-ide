import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show WebSocket;

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';

typedef WsSessionHeaders = ({
  String apiKey,
  String? deviceHash,
  String? workspaceId,
});

/// JSON WebSocket client — paths are under `/api/ws/` via [AppConfig.webSocketUri].
class WsClient {
  WsClient({
    required AppConfig config,
    required WsSessionHeaders Function() readHeaders,
  })  : _config = config,
        _readHeaders = readHeaders;

  final AppConfig _config;
  final WsSessionHeaders Function() _readHeaders;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final Queue<Map<String, dynamic>> _inbox = Queue();
  Completer<Map<String, dynamic>>? _waiter;
  final StreamController<Map<String, dynamic>> _broadcast =
      StreamController<Map<String, dynamic>>.broadcast();

  bool get isConnected => _channel != null;

  /// All frames — for terminals, agent, remote listeners.
  Stream<Map<String, dynamic>> get messages => _broadcast.stream;

  Future<void> connect(String relativePath) async {
    await disconnect();
    await _openChannel(_buildUri(relativePath, _readHeaders()));
  }

  Future<void> connectSync(int workspaceId) async {
    await disconnect();
    await _openChannel(_buildSyncUri(workspaceId, _readHeaders()));
  }

  /// Next JSON frame from the server (queued — safe across await gaps).
  Future<Map<String, dynamic>> receive() async {
    if (_inbox.isNotEmpty) {
      return _inbox.removeFirst();
    }

    final completer = Completer<Map<String, dynamic>>();
    _waiter = completer;
    return completer.future;
  }

  Future<void> _openChannel(Uri uri) async {
    assert(uri.scheme == 'ws' || uri.scheme == 'wss');
    assert(uri.port != 0, 'WebSocket URI must not use port 0: $uri');

    try {
      final socket = await WebSocket.connect(uri.toString());
      socket.pingInterval = const Duration(seconds: 25);
      _channel = IOWebSocketChannel(socket);
    } catch (error) {
      _channel = null;
      throw StateError('WebSocket connection failed: $error');
    }

    _subscription = _channel!.stream.listen(
      (event) {
        if (event is! String) {
          return;
        }
        try {
          final decoded = jsonDecode(event) as Map<String, dynamic>;
          _deliver(decoded);
        } on FormatException {
          _deliver({
            'type': 'error',
            'code': 'invalid_json',
            'message': 'Invalid JSON from server',
          });
        }
      },
      onError: (Object error) {
        _deliver({
          'type': 'error',
          'code': 'connection_error',
          'message': error.toString(),
        });
      },
      onDone: () {
        _deliver({
          'type': 'connection_closed',
        });
      },
    );
  }

  void _deliver(Map<String, dynamic> message) {
    if (!_broadcast.isClosed) {
      _broadcast.add(message);
    }
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      waiter.complete(message);
      return;
    }
    _inbox.add(message);
  }

  void send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    channel.sink.add(jsonEncode(payload));
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _inbox.clear();
    _waiter?.completeError(StateError('WebSocket disconnected'));
    _waiter = null;
  }

  Future<void> dispose() async {
    await disconnect();
  }

  Map<String, String> _authQuery(WsSessionHeaders session) {
    return {
      'api_key': session.apiKey,
      if (session.deviceHash != null && session.deviceHash!.isNotEmpty)
        'device_hash': session.deviceHash!,
      if (session.workspaceId != null && session.workspaceId!.isNotEmpty)
        'workspace_id': session.workspaceId!,
    };
  }

  Uri _buildUri(String relativePath, WsSessionHeaders session) {
    final normalizedPath =
        relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;

    return _config.webSocketUri(
      normalizedPath,
      queryParameters: _authQuery(session),
    );
  }

  Uri _buildSyncUri(int workspaceId, WsSessionHeaders session) {
    return _config.webSocketSyncUri(
      workspaceId,
      queryParameters: _authQuery(session),
    );
  }
}
