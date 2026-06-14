import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef SignalingSend = void Function(Map<String, dynamic> frame);

/// WebRTC session: offer/answer/ICE over WebSocket, renders remote screen track.
class RemoteWebRtcSession {
  RemoteWebRtcSession({required this.onSignalingSend});

  final SignalingSend onSignalingSend;
  VoidCallback? onVideoTrack;
  VoidCallback? onConnectionFailed;

  final RTCVideoRenderer renderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  bool _initialized = false;
  bool _negotiating = false;

  bool get videoReady => renderer.srcObject != null;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await renderer.initialize();
    _initialized = true;
  }

  Future<void> startNegotiation() async {
    if (_negotiating) {
      return;
    }
    _negotiating = true;

    await initialize();
    await _disposePeerConnection();

    _peerConnection = await createPeerConnection({
      'sdpSemantics': 'unified-plan',
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
    });

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) {
        return;
      }
      onSignalingSend({
        'type': 'ice_candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
        onVideoTrack?.call();
      }
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('Remote WebRTC state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        onConnectionFailed?.call();
      }
    };

    await _peerConnection!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(
        direction: TransceiverDirection.RecvOnly,
      ),
    );

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    onSignalingSend({'type': 'offer', 'sdp': offer.sdp});
  }

  Future<void> handleSignalingFrame(Map<String, dynamic> frame) async {
    final type = frame['type'] as String? ?? '';
    if (type == 'answer') {
      final sdp = frame['sdp'] as String? ?? '';
      if (sdp.isEmpty || _peerConnection == null) {
        return;
      }
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, 'answer'),
      );
    } else if (type == 'ice_candidate') {
      final raw = frame['candidate'];
      if (raw is! Map || _peerConnection == null) {
        return;
      }
      final candidate = RTCIceCandidate(
        raw['candidate'] as String?,
        raw['sdpMid'] as String?,
        raw['sdpMLineIndex'] as int?,
      );
      await _peerConnection!.addCandidate(candidate);
    }
  }

  Future<void> dispose() async {
    await _disposePeerConnection();
    if (_initialized) {
      await renderer.dispose();
      _initialized = false;
    }
  }

  Future<void> _disposePeerConnection() async {
    final pc = _peerConnection;
    _peerConnection = null;
    _negotiating = false;
    if (pc != null) {
      await pc.close();
    }
    renderer.srcObject = null;
  }
}
