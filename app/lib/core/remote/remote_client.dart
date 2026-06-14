import 'dart:async';

import '../config/app_config.dart';
import '../ws/ws_client.dart';
import 'remote_webrtc.dart';

typedef RemoteStateCallback = void Function({
  bool? connected,
  bool? videoReady,
  String? error,
  bool clearError,
});

/// Remote desktop WebSocket + WebRTC client (`/api/ws/remote/`).
class RemoteClient {
  RemoteClient({
    required AppConfig config,
    required WsSessionHeaders Function() readHeaders,
    this.onStateChanged,
  }) : _ws = WsClient(config: config, readHeaders: readHeaders) {
    _webrtc = RemoteWebRtcSession(onSignalingSend: _ws.send);
    _webrtc.onVideoTrack = () {
      _videoReady = true;
      _notify(clearError: true);
    };
    _webrtc.onConnectionFailed = () {
      _notify(
        error:
            'WebRTC peer connection failed. If using a tunnel, video may need '
            'a direct LAN route or TURN server.',
      );
    };
  }

  final RemoteStateCallback? onStateChanged;

  final WsClient _ws;
  late final RemoteWebRtcSession _webrtc;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _connected = false;
  bool _videoReady = false;
  int _stagedCount = 0;

  RemoteWebRtcSession get webrtc => _webrtc;
  bool get isConnected => _connected;
  bool get videoReady => _videoReady;
  int get stagedCount => _stagedCount;
  Stream<Map<String, dynamic>> get messages => _ws.messages;

  void _notify({String? error, bool clearError = false}) {
    onStateChanged?.call(
      connected: _connected,
      videoReady: _videoReady,
      error: error,
      clearError: clearError,
    );
  }

  Future<void> connect() async {
    await _webrtc.initialize();
    await _ws.connect('remote/');
    _sub ??= _ws.messages.listen(_onFrame);
    await _webrtc.startNegotiation();
    _notify(clearError: true);
  }

  void _onFrame(Map<String, dynamic> frame) {
    handleFrame(frame);
  }

  Future<void> handleFrame(Map<String, dynamic> frame) async {
    final type = frame['type'] as String? ?? '';
    if (type == 'auth_ok' || type == 'connected') {
      _connected = true;
      _notify(clearError: true);
    } else if (type == 'input_staged') {
      _stagedCount = frame['count'] as int? ?? _stagedCount;
      _notify();
    } else if (type == 'staging_cleared') {
      _stagedCount = 0;
      _notify();
    } else if (type == 'answer' || type == 'ice_candidate') {
      await _webrtc.handleSignalingFrame(frame);
      if (_webrtc.videoReady) {
        _videoReady = true;
      }
      _notify(clearError: true);
    } else if (type == 'error') {
      _connected = false;
      _videoReady = false;
      final code = frame['code'] as String? ?? 'error';
      final message = frame['message'] as String? ?? 'Remote error';
      _notify(error: '$code: $message');
    } else if (type == 'connection_closed') {
      _connected = false;
      _videoReady = false;
      _notify(error: 'Remote WebSocket closed');
    }
  }

  void stageEvents(List<Map<String, dynamic>> events) {
    _ws.send({'type': 'input_batch', 'events': events, 'dispatch': false});
  }

  void dispatch() {
    _ws.send({'type': 'input_batch', 'events': [], 'dispatch': true});
  }

  void clearStaging() {
    _ws.send({'type': 'clear'});
    _stagedCount = 0;
  }

  void click({required String button}) {
    _ws.send({
      'type': 'input_batch',
      'events': [
        {'op': 'click', 'button': button},
      ],
      'dispatch': true,
    });
  }

  void pointerMove({
    required double x,
    required double y,
    bool normalized = true,
  }) {
    _ws.send({
      'type': 'input_batch',
      'events': [
        {
          'op': 'pointer_move',
          'x': x,
          'y': y,
          'normalized': normalized,
        },
      ],
      'dispatch': true,
    });
  }

  void stageKey(String key) {
    _ws.send({
      'type': 'input_batch',
      'events': [
        {'op': 'key_combo', 'keys': [key]},
      ],
      'dispatch': false,
    });
  }

  void sendKeyInput(
    String value, {
    Set<String> modifiers = const {},
    bool dispatch = true,
  }) {
    final keys = [
      ...modifiers.map((m) => m.toLowerCase()),
      value,
    ];
    _ws.send({
      'type': 'input_batch',
      'events': [
        {'op': 'key_combo', 'keys': keys},
      ],
      'dispatch': dispatch,
    });
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _ws.disconnect();
    await _webrtc.dispose();
    _connected = false;
    _videoReady = false;
    _stagedCount = 0;
  }
}
