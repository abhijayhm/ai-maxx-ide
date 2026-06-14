import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';
import 'global_loader_provider.dart';

class OpenFileState {
  const OpenFileState({
    this.path,
    this.asset,
    this.loading = false,
    this.error,
    this.isText = true,
    this.mimeType,
    this.textContent,
    this.bytes,
  });

  final String? path;
  final String? asset;
  final bool loading;
  final String? error;
  final bool isText;
  final String? mimeType;
  final String? textContent;
  final Uint8List? bytes;

  bool get isOpen => path != null;

  OpenFileState copyWith({
    String? path,
    String? asset,
    bool? loading,
    String? error,
    bool? isText,
    String? mimeType,
    String? textContent,
    Uint8List? bytes,
    bool clear = false,
    bool clearError = false,
  }) {
    if (clear) {
      return const OpenFileState();
    }
    return OpenFileState(
      path: path ?? this.path,
      asset: asset ?? this.asset,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      isText: isText ?? this.isText,
      mimeType: mimeType ?? this.mimeType,
      textContent: textContent ?? this.textContent,
      bytes: bytes ?? this.bytes,
    );
  }
}

final ideFileProvider =
    NotifierProvider<IdeFileNotifier, OpenFileState>(IdeFileNotifier.new);

class IdeFileNotifier extends Notifier<OpenFileState> {
  WsClient? _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;
  final StringBuffer _textBuffer = StringBuffer();
  final List<int> _byteBuffer = [];
  LoaderHandle? _loader;

  @override
  OpenFileState build() {
    ref.onDispose(_disconnect);
    return const OpenFileState();
  }

  void _releaseLoader() {
    _loader?.release();
    _loader = null;
  }

  Future<void> open(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return;
    }

    _releaseLoader();
    _ws?.send({'type': 'cancel'});

    try {
      final session = await ref.read(sessionProvider.future);
      final workspaceId = int.tryParse(session.activeWorkspaceId ?? '');
      if (workspaceId == null) {
        state = state.copyWith(error: 'Open a workspace first.');
        return;
      }

      await _ensureConnected(session);
      _textBuffer.clear();
      _byteBuffer.clear();
      state = OpenFileState(
        path: trimmed,
        loading: true,
      );
      _loader = ref.read(globalLoaderProvider.notifier).acquire('Loading file…');

      _ws!.send({
        'type': 'get',
        'workspace_id': workspaceId,
        'path': trimmed,
      });
    } catch (error) {
      _releaseLoader();
      state = OpenFileState(
        path: trimmed,
        loading: false,
        error: error.toString(),
      );
    }
  }

  void close() {
    _ws?.send({'type': 'cancel'});
    _releaseLoader();
    state = const OpenFileState();
    _textBuffer.clear();
    _byteBuffer.clear();
  }

  Future<void> _ensureConnected(session) async {
    if (_ws != null && _ws!.isConnected) {
      return;
    }
    final config = ref.read(appConfigProvider);
    config.serverUrl = AppConfig.normalizeServerUrl(session.serverUrl);
    config.apiKey = session.apiKey;

    _ws = WsClient(
      config: config,
      readHeaders: () => (
        apiKey: session.apiKey,
        deviceHash: session.deviceHash,
        workspaceId: session.activeWorkspaceId,
      ),
    );
    _sub ??= _ws!.messages.listen(_onFrame);
    await _ws!.connect('getbypath/');
  }

  void _onFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String? ?? '';
    if (type == 'file_started') {
      state = state.copyWith(
        path: frame['path'] as String? ?? state.path,
        asset: frame['asset'] as String? ?? state.asset,
        loading: true,
        isText: frame['is_text'] as bool? ?? true,
        mimeType: frame['mime_type'] as String?,
        clearError: true,
      );
      return;
    }

    if (type == 'chunk') {
      final encoding = frame['encoding'] as String? ?? 'utf-8';
      final content = frame['content'] as String? ?? '';
      if (encoding == 'base64') {
        _byteBuffer.addAll(base64.decode(content));
      } else {
        _textBuffer.write(content);
      }
      return;
    }

    if (type == 'file_complete') {
      _releaseLoader();
      if (state.isText) {
        state = state.copyWith(
          loading: false,
          textContent: _textBuffer.toString(),
        );
      } else {
        state = state.copyWith(
          loading: false,
          bytes: Uint8List.fromList(_byteBuffer),
        );
      }
      return;
    }

    if (isWsTerminalFrame(type)) {
      _releaseLoader();
      if (type == 'error' || type == 'connection_error') {
        state = state.copyWith(
          loading: false,
          error: frame['message'] as String? ?? 'Failed to load file',
        );
      } else {
        state = state.copyWith(loading: false);
      }
    }
  }

  Future<void> _disconnect() async {
    _releaseLoader();
    await _sub?.cancel();
    _sub = null;
    await _ws?.disconnect();
    _ws = null;
  }
}
