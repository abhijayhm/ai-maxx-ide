import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/git_models.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';

class GitState {
  const GitState({
    this.loading = false,
    this.files = const [],
    this.branches = const [],
    this.currentBranch,
    this.commits = const [],
    this.graphLines = const [],
    this.error,
    this.lastOutput,
  });

  final bool loading;
  final List<GitChangedFile> files;
  final List<String> branches;
  final String? currentBranch;
  final List<GitCommit> commits;
  final List<String> graphLines;
  final String? error;
  final String? lastOutput;

  GitState copyWith({
    bool? loading,
    List<GitChangedFile>? files,
    List<String>? branches,
    String? currentBranch,
    List<GitCommit>? commits,
    List<String>? graphLines,
    String? error,
    String? lastOutput,
  }) {
    return GitState(
      loading: loading ?? this.loading,
      files: files ?? this.files,
      branches: branches ?? this.branches,
      currentBranch: currentBranch ?? this.currentBranch,
      commits: commits ?? this.commits,
      graphLines: graphLines ?? this.graphLines,
      error: error,
      lastOutput: lastOutput ?? this.lastOutput,
    );
  }
}

final gitProvider = NotifierProvider<GitNotifier, GitState>(GitNotifier.new);

class GitNotifier extends Notifier<GitState> {
  WsClient? _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Completer<Map<String, dynamic>>? _waiter;

  @override
  GitState build() {
    ref.onDispose(_disconnect);
    return const GitState();
  }

  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _send({'type': 'status'});
      final statusMsg = await _nextResponse(['status']);
      final files = (statusMsg['files'] as List<dynamic>? ?? [])
          .map((f) => GitChangedFile.fromJson(f as Map<String, dynamic>))
          .toList();

      await _send({'type': 'branches'});
      final branchMsg = await _nextResponse(['branches']);
      final branches =
          (branchMsg['branches'] as List<dynamic>? ?? []).cast<String>();

      await _send({'type': 'log', 'limit': 20});
      final logMsg = await _nextResponse(['log']);
      final commits = (logMsg['commits'] as List<dynamic>? ?? [])
          .map((c) => GitCommit.fromJson(c as Map<String, dynamic>))
          .toList();

      await _send({'type': 'log_graph'});
      final graphMsg = await _nextResponse(['log_graph']);
      final lines =
          (graphMsg['lines'] as List<dynamic>? ?? []).cast<String>();

      state = GitState(
        files: files,
        branches: branches,
        currentBranch: branchMsg['current'] as String?,
        commits: commits,
        graphLines: lines,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  Future<void> stage(String path) async {
    await _send({'type': 'add', 'paths': [path]});
    await _nextResponse(['add']);
    await refresh();
  }

  Future<void> stageAll() async {
    await _send({'type': 'add', 'all': true});
    await _nextResponse(['add']);
    await refresh();
  }

  Future<void> discard(String path) async {
    await _send({'type': 'discard', 'paths': [path]});
    await _nextResponse(['discard']);
    await refresh();
  }

  Future<void> commit(String message) async {
    await _send({'type': 'commit', 'message': message});
    await _nextResponse(['commit']);
    await refresh();
  }

  Future<void> stash() async {
    await _send({'type': 'stash', 'message': 'WIP'});
    await _nextResponse(['stash']);
    await refresh();
  }

  Future<void> checkout(String branch) async {
    await _send({'type': 'checkout', 'branch': branch});
    await _nextResponse(['checkout']);
    await refresh();
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    final session = await ref.read(sessionProvider.future);
    final workspaceId = int.tryParse(session.activeWorkspaceId ?? '');
    if (workspaceId == null) {
      throw StateError('No active workspace');
    }
    await _ensureConnected(session);
    _ws!.send({...payload, 'workspace_id': workspaceId});
  }

  Future<Map<String, dynamic>> _nextResponse(List<String> types) async {
    final completer = Completer<Map<String, dynamic>>();
    _waiter = completer;
    final msg = await completer.future.timeout(const Duration(seconds: 30));
    if (msg['type'] == 'error') {
      throw StateError(msg['message'] as String? ?? 'Git command failed');
    }
    if (!types.contains(msg['type'])) {
      throw StateError('Unexpected git response: ${msg['type']}');
    }
    return msg;
  }

  void _onFrame(Map<String, dynamic> frame) {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      _waiter = null;
      waiter.complete(frame);
    }
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
    await _ws!.connect('git/');
  }

  Future<void> _disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _ws?.disconnect();
    _ws = null;
  }
}
