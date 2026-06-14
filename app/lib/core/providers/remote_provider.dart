import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../remote/remote_client.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';
import 'global_loader_provider.dart';

class RemoteState {
  const RemoteState({
    this.connecting = false,
    this.connected = false,
    this.videoReady = false,
    this.stagedCount = 0,
    this.error,
    this.pointerX = 0.5,
    this.pointerY = 0.5,
    this.trackpadSensitivity = 1.5,
  });

  final bool connecting;
  final bool connected;
  final bool videoReady;
  final int stagedCount;
  final String? error;
  /// Last server-reported cursor (normalized). Cursor is drawn into the RTC stream.
  final double pointerX;
  final double pointerY;
  final double trackpadSensitivity;

  bool get isLoading => connecting || (connected && !videoReady);

  RemoteState copyWith({
    bool? connecting,
    bool? connected,
    bool? videoReady,
    int? stagedCount,
    String? error,
    double? pointerX,
    double? pointerY,
    double? trackpadSensitivity,
    bool clearError = false,
  }) {
    return RemoteState(
      connecting: connecting ?? this.connecting,
      connected: connected ?? this.connected,
      videoReady: videoReady ?? this.videoReady,
      stagedCount: stagedCount ?? this.stagedCount,
      error: clearError ? null : (error ?? this.error),
      pointerX: pointerX ?? this.pointerX,
      pointerY: pointerY ?? this.pointerY,
      trackpadSensitivity: trackpadSensitivity ?? this.trackpadSensitivity,
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
  LoaderHandle? _loader;

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

  void _releaseLoader() {
    _loader?.release();
    _loader = null;
  }

  void _onClientState({
    bool? connected,
    bool? videoReady,
    String? error,
    bool clearError = false,
    double? pointerX,
    double? pointerY,
  }) {
    state = state.copyWith(
      connected: connected ?? state.connected,
      videoReady: videoReady ?? state.videoReady,
      error: clearError ? null : (error ?? state.error),
      stagedCount: _client?.stagedCount ?? state.stagedCount,
      pointerX: pointerX ?? state.pointerX,
      pointerY: pointerY ?? state.pointerY,
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

    _releaseLoader();
    state = state.copyWith(connecting: true, clearError: true);
    _loader = ref
        .read(globalLoaderProvider.notifier)
        .acquire('Connecting remote desktop…');
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
    } finally {
      _releaseLoader();
    }
  }

  Future<void> disconnect() async {
    _releaseLoader();
    await _client?.disconnect();
    _client = null;
    state = const RemoteState();
  }

  void setTrackpadSensitivity(double value) {
    state = state.copyWith(trackpadSensitivity: value.clamp(0.25, 4.0));
  }

  void pointerMove(double x, double y) {
    _client?.pointerMove(
      x: x.clamp(0.0, 1.0),
      y: y.clamp(0.0, 1.0),
    );
  }

  void pointerDelta(double dx, double dy) {
    _client?.pointerDelta(dx: dx, dy: dy);
  }

  void click({String button = 'left'}) {
    _client?.click(button: button);
  }

  void commitKeys(List<String> stagedKeys, Set<String> modifiers) {
    final client = _client;
    if (client == null) {
      return;
    }

    if (stagedKeys.isEmpty && modifiers.isEmpty) {
      return;
    }

    if (modifiers.isEmpty) {
      for (final key in stagedKeys) {
        client.sendKeyInput(key, dispatch: true);
      }
      return;
    }

    if (stagedKeys.isEmpty) {
      client.sendKeyInput('', modifiers: modifiers, dispatch: true);
      return;
    }

    for (var i = 0; i < stagedKeys.length - 1; i++) {
      client.sendKeyInput(stagedKeys[i], modifiers: modifiers, dispatch: true);
    }
    client.sendKeyInput(
      stagedKeys.last,
      modifiers: modifiers,
      dispatch: true,
    );
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
