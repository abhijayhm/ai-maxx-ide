import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';

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
    final matches = frame['matches'] as List<dynamic>? ?? [];
    final first = matches.isNotEmpty ? matches.first as Map<String, dynamic> : {};
    return GrepMatch(
      path: frame['path'] as String? ?? '',
      asset: frame['asset'] as String? ?? '',
      line: first['line'] as int? ?? 0,
      startIndex: first['start_index'] as int? ?? 0,
      endIndex: first['end_index'] as int? ?? 0,
      text: first['text'] as String? ?? '',
    );
  }
}

class IdeSearchState {
  const IdeSearchState({
    this.results = const [],
    this.searching = false,
    this.error,
  });

  final List<GrepMatch> results;
  final bool searching;
  final String? error;

  IdeSearchState copyWith({
    List<GrepMatch>? results,
    bool? searching,
    String? error,
    bool clearError = false,
  }) {
    return IdeSearchState(
      results: results ?? this.results,
      searching: searching ?? this.searching,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final ideSearchProvider =
    NotifierProvider<IdeSearchNotifier, IdeSearchState>(IdeSearchNotifier.new);

class IdeSearchNotifier extends Notifier<IdeSearchState> {
  WsClient? _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  IdeSearchState build() {
    ref.onDispose(_disconnect);
    return const IdeSearchState();
  }

  Future<void> search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      state = const IdeSearchState();
      return;
    }

    final session = await ref.read(sessionProvider.future);
    final workspaceId = int.tryParse(session.activeWorkspaceId ?? '');
    if (workspaceId == null) {
      state = state.copyWith(error: 'Open a workspace first.');
      return;
    }

    await _ensureConnected(session);
    state = state.copyWith(searching: true, results: const [], clearError: true);

    _ws!.send({
      'type': 'search',
      'workspace_id': workspaceId,
      'keyword': trimmed,
      'match_case': false,
      'match_exact': false,
      'files_to_include': <String>[],
      'files_to_exclude': <String>[],
    });
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
    await _ws!.connect('ide_search/');
  }

  void _onFrame(Map<String, dynamic> frame) {
    final type = frame['type'] as String? ?? '';
    if (type == 'result') {
      final hit = GrepMatch.fromFrame(frame);
      state = state.copyWith(
        results: [...state.results, hit],
        searching: true,
      );
    } else if (type == 'search_complete' || type == 'cancelled') {
      state = state.copyWith(searching: false);
    } else if (type == 'error') {
      state = state.copyWith(
        searching: false,
        error: frame['message'] as String? ?? 'Search failed',
      );
    }
  }

  Future<void> _disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _ws?.disconnect();
    _ws = null;
  }
}
