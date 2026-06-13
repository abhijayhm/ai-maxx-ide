import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../ws/ws_client.dart';
import 'remote_webrtc.dart';

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
      onStateChanged?.call();
    };
  }

  final VoidCallback? onStateChanged;

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

  Future<void> connect() async {
    await _webrtc.initialize();
    await _ws.connect('remote/');
    _sub ??= _ws.messages.listen(_onFrame);
    await _webrtc.startNegotiation();
  }

  void _onFrame(Map<String, dynamic> frame) {
    handleFrame(frame);
  }

  Future<void> handleFrame(Map<String, dynamic> frame) async {
    final type = frame['type'] as String? ?? '';
    if (type == 'auth_ok' || type == 'connected') {
      _connected = true;
    } else if (type == 'input_staged') {
      _stagedCount = frame['count'] as int? ?? _stagedCount;
    } else if (type == 'staging_cleared') {
      _stagedCount = 0;
    } else if (type == 'answer' || type == 'ice_candidate') {
      await _webrtc.handleSignalingFrame(frame);
      if (_webrtc.videoReady) {
        _videoReady = true;
      }
    } else if (type == 'error') {
      _connected = false;
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
