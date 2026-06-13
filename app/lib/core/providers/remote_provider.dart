import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../remote/remote_client.dart';
import 'app_providers.dart';

class RemoteState {
  const RemoteState({
    this.connected = false,
    this.videoReady = false,
    this.stagedCount = 0,
    this.status = 'Disconnected',
    this.error,
    this.renderer,
  });

  final bool connected;
  final bool videoReady;
  final int stagedCount;
  final String status;
  final String? error;
  final RTCVideoRenderer? renderer;

  RemoteState copyWith({
    bool? connected,
    bool? videoReady,
    int? stagedCount,
    String? status,
    String? error,
    RTCVideoRenderer? renderer,
  }) {
    return RemoteState(
      connected: connected ?? this.connected,
      videoReady: videoReady ?? this.videoReady,
      stagedCount: stagedCount ?? this.stagedCount,
      status: status ?? this.status,
      error: error,
      renderer: renderer ?? this.renderer,
    );
  }
}

final remoteProvider =
    NotifierProvider<RemoteNotifier, RemoteState>(RemoteNotifier.new);

class RemoteNotifier extends Notifier<RemoteState> {
  RemoteClient? _client;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  RemoteState build() {
    ref.onDispose(_disconnect);
    return const RemoteState();
  }

  Future<void> connect() async {
    if (_client != null && state.connected && state.videoReady) {
      return;
    }

    state = state.copyWith(status: 'Connecting…', error: null);

    final config = ref.read(appConfigProvider);
    final session = ref.read(sessionProvider).valueOrNull;
    _client = RemoteClient(
      config: config,
      readHeaders: () => (
        apiKey: session?.apiKey ?? config.apiKey,
        deviceHash: session?.deviceHash,
        workspaceId: session?.activeWorkspaceId,
      ),
      onStateChanged: () {
        final client = _client;
        if (client == null) {
          return;
        }
        state = state.copyWith(
          connected: client.isConnected,
          videoReady: client.videoReady,
          stagedCount: client.stagedCount,
          status: client.videoReady ? 'Live' : state.status,
          renderer: client.webrtc.renderer,
        );
      },
    );

    try {
      await _client!.connect();
      _sub = _client!.messages.listen((frame) async {
        await _client!.handleFrame(frame);
        final type = frame['type'] as String? ?? '';
        state = state.copyWith(
          connected: _client!.isConnected,
          videoReady: _client!.videoReady,
          stagedCount: _client!.stagedCount,
          status: _statusLabel(type, _client!),
          renderer: _client!.webrtc.renderer,
          error: type == 'error'
              ? frame['message'] as String? ?? 'Remote error'
              : null,
        );
      });
      state = state.copyWith(
        status: 'Negotiating video…',
        renderer: _client!.webrtc.renderer,
      );
    } catch (error) {
      state = state.copyWith(
        status: 'Connection failed',
        error: error.toString(),
      );
    }
  }

  String _statusLabel(String type, RemoteClient client) {
    if (client.videoReady) {
      return 'Live';
    }
    if (client.isConnected) {
      return 'Connected — waiting for video';
    }
    switch (type) {
      case 'answer':
        return 'Video answer received';
      case 'connected':
        return 'Signaling complete';
      default:
        return type.isEmpty ? 'Connecting…' : type;
    }
  }

  void leftClick() => _client?.click(button: 'left');
  void rightClick() => _client?.click(button: 'right');
  void pointerMove(double x, double y) => _client?.pointerMove(x: x, y: y);
  void stageKey(String key) => _client?.stageKey(key);
  void dispatch() => _client?.dispatch();
  void clear() => _client?.clearStaging();

  Future<void> _disconnect() async {
    await _sub?.cancel();
    await _client?.disconnect();
    _client = null;
    _sub = null;
  }
}
