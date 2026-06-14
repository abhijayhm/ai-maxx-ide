import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import '../config/app_config.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';
import 'global_loader_provider.dart';

class GrepMatch {
  const GrepMatch({
    required this.path,
    required this.asset,
    required this.line,
    required this.startIndex,
    required this.endIndex,
    required this.text,
  });

  final String path;
  final String asset;
  final int line;
  final int startIndex;
  final int endIndex;
  final String text;

  factory GrepMatch.fromFrame(Map<String, dynamic> frame) {
    int readInt(dynamic value) {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    final matches = frame['matches'] as List<dynamic>? ?? [];
    final first =
        matches.isNotEmpty ? matches.first as Map<String, dynamic> : {};
    return GrepMatch(
      path: frame['path'] as String? ?? '',
      asset: frame['asset'] as String? ?? '',
      line: readInt(frame['line'] ?? first['line']),
      startIndex: readInt(frame['start_index'] ?? first['start_index']),
      endIndex: readInt(frame['end_index'] ?? first['end_index']),
      text: frame['text'] as String? ?? first['text'] as String? ?? '',
    );
  }
}

class IdeSearchState {
  const IdeSearchState({
    this.results = const [],
    this.searching = false,
    this.error,
    this.keyword = '',
  });

  final List<GrepMatch> results;
  final bool searching;
  final String? error;
  final String keyword;

  IdeSearchState copyWith({
    List<GrepMatch>? results,
    bool? searching,
    String? error,
    String? keyword,
    bool clearError = false,
  }) {
    return IdeSearchState(
      results: results ?? this.results,
      searching: searching ?? this.searching,
      error: clearError ? null : (error ?? this.error),
      keyword: keyword ?? this.keyword,
    );
  }
}

final ideSearchProvider =
    NotifierProvider<IdeSearchNotifier, IdeSearchState>(IdeSearchNotifier.new);

class IdeSearchNotifier extends Notifier<IdeSearchState> {
  WsClient? _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;
  final List<GrepMatch> _pending = [];
  Timer? _flushTimer;
  int _searchGeneration = 0;
  LoaderHandle? _loader;

  @override
  IdeSearchState build() {
    ref.onDispose(_disconnect);
    return const IdeSearchState();
  }

  void _releaseLoader() {
    _loader?.release();
    _loader = null;
  }

  Future<void> search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      _searchGeneration++;
      _pending.clear();
      _flushTimer?.cancel();
      _flushTimer = null;
      if (_ws != null && _ws!.isConnected) {
        _ws!.send({'type': 'cancel'});
      }
      _releaseLoader();
      state = const IdeSearchState();
      return;
    }

    try {
      final session = await ref.read(sessionProvider.future);
      final workspaceId = int.tryParse(session.activeWorkspaceId ?? '');
      if (workspaceId == null) {
        _releaseLoader();
        state = state.copyWith(
          searching: false,
          error: 'Open a workspace first.',
        );
        return;
      }

      await _ensureConnected(session);

      final generation = ++_searchGeneration;
      if (state.searching) {
        _ws!.send({'type': 'cancel'});
      }

      _pending.clear();
      _flushTimer?.cancel();
      _flushTimer = null;
      _releaseLoader();
      state = IdeSearchState(
        searching: true,
        keyword: trimmed,
        results: const [],
      );
      _loader = ref
          .read(globalLoaderProvider.notifier)
          .acquire('Searching for "$trimmed"…');

      _ws!.send({
        'type': 'search',
        'workspace_id': workspaceId,
        'keyword': trimmed,
        'match_case': false,
        'match_exact': false,
        'files_to_include': <String>[],
        'files_to_exclude': <String>[],
      });

      if (generation != _searchGeneration) {
        _releaseLoader();
      }
    } catch (error) {
      _releaseLoader();
      state = IdeSearchState(
        searching: false,
        keyword: trimmed,
        error: error.toString(),
      );
    }
  }

  Future<void> _ensureConnected(SessionSnapshot session) async {
    if (_ws != null && _ws!.isConnected) {
      return;
    }

    await _sub?.cancel();
    _sub = null;

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
    _sub = _ws!.messages.listen(_onFrame);
    await _ws!.connect('ide_search/');
  }

  void _onFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String? ?? '';
    if (type == 'result') {
      _pending.add(GrepMatch.fromFrame(frame));
      _scheduleFlush();
      return;
    }

    if (type == 'search_complete') {
      _flushPending();
      _releaseLoader();
      state = state.copyWith(searching: false);
      return;
    }

    if (type == 'cancelled') {
      if (state.searching) {
        _releaseLoader();
        state = state.copyWith(searching: false);
      }
      return;
    }

    if (type == 'error' || type == 'connection_error') {
      _flushPending();
      _releaseLoader();
      state = state.copyWith(
        searching: false,
        error: frame['message'] as String? ?? 'Search failed',
      );
      return;
    }

    if (type == 'connection_closed') {
      _releaseLoader();
      if (state.searching) {
        state = state.copyWith(searching: false);
      }
    }
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 32), _flushPending);
  }

  void _flushPending() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) {
      return;
    }
    state = state.copyWith(
      results: [...state.results, ..._pending],
      searching: true,
    );
    _pending.clear();
  }

  Future<void> _disconnect() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    _releaseLoader();
    await _sub?.cancel();
    _sub = null;
    await _ws?.disconnect();
    _ws = null;
  }
}
