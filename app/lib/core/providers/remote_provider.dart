import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../remote/remote_client.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';

class RemoteState {
  const RemoteState({
    this.connecting = false,
    this.connected = false,
    this.videoReady = false,
    this.stagedCount = 0,
    this.error,
  });

  final bool connecting;
  final bool connected;
  final bool videoReady;
  final int stagedCount;
  final String? error;

  RemoteState copyWith({
    bool? connecting,
    bool? connected,
    bool? videoReady,
    int? stagedCount,
    String? error,
    bool clearError = false,
  }) {
    return RemoteState(
      connecting: connecting ?? this.connecting,
      connected: connected ?? this.connected,
      videoReady: videoReady ?? this.videoReady,
      stagedCount: stagedCount ?? this.stagedCount,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final remoteProvider =
    NotifierProvider<RemoteNotifier, RemoteState>(RemoteNotifier.new);

final remoteClientProvider = Provider<RemoteClient?>((ref) {
  ref.watch(remoteProvider);
  return ref.read(remoteProvider.notifier).client;
});

class RemoteNotifier extends Notifier<RemoteState> {
  RemoteClient? _client;

  RemoteClient? get client => _client;

  @override
  RemoteState build() {
    ref.onDispose(() {
      unawaited(disconnect());
    });
    return const RemoteState();
  }

  WsSessionHeaders _headers() {
    final session = ref.read(sessionProvider).valueOrNull;
    final config = ref.read(appConfigProvider);
    return (
      apiKey: session?.apiKey.isNotEmpty == true
          ? session!.apiKey
          : config.apiKey,
      deviceHash: session?.deviceHash,
      workspaceId: session?.activeWorkspaceId,
    );
  }

  void _onClientState({
    bool? connected,
    bool? videoReady,
    String? error,
    bool clearError = false,
  }) {
    state = state.copyWith(
      connected: connected ?? state.connected,
      videoReady: videoReady ?? state.videoReady,
      error: clearError ? null : (error ?? state.error),
      stagedCount: _client?.stagedCount ?? state.stagedCount,
    );
  }

  Future<void> connect() async {
    if (_client != null && state.connected && state.videoReady) {
      return;
    }

    final session = ref.read(sessionProvider).valueOrNull;
    if (session?.isAuthenticated != true) {
      state = state.copyWith(error: 'Authenticate before connecting remote.');
      return;
    }

    state = state.copyWith(connecting: true, clearError: true);
    try {
      await _client?.disconnect();
      _client = RemoteClient(
        config: ref.read(appConfigProvider),
        readHeaders: _headers,
        onStateChanged: _onClientState,
      );
      await _client!.connect();
      state = state.copyWith(
        connecting: false,
        connected: _client!.isConnected,
        videoReady: _client!.videoReady,
      );
    } catch (error) {
      state = state.copyWith(
        connecting: false,
        connected: false,
        error: error.toString(),
      );
    }
  }

  Future<void> disconnect() async {
    await _client?.disconnect();
    _client = null;
    state = const RemoteState();
  }

  void pointerMove(double x, double y) {
    _client?.pointerMove(x: x, y: y);
  }

  void click({String button = 'left'}) {
    _client?.click(button: button);
  }

  void sendKey(String value, {Set<String> modifiers = const {}}) {
    final client = _client;
    if (client == null) {
      return;
    }
    if (modifiers.isEmpty) {
      client.sendKeyInput(value);
      return;
    }
    client.sendKeyInput(value, modifiers: modifiers);
  }

  void dispatchStaging() {
    _client?.dispatch();
    _onClientState();
  }

  void clearStaging() {
    _client?.clearStaging();
    _onClientState();
  }
}
