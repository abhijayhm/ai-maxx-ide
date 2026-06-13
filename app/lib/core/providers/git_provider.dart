import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/git_repository.dart';
import 'app_providers.dart';

final gitRepositoryProvider = FutureProvider<GitRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return GitRepository(api);
});

class GitState {
  const GitState({
    this.loading = false,
    this.files = const [],
    this.branches = const [],
    this.currentBranch,
    this.commits = const [],
    this.error,
    this.lastOutput,
  });

  final bool loading;
  final List<GitChangedFile> files;
  final List<String> branches;
  final String? currentBranch;
  final List<GitCommit> commits;
  final String? error;
  final String? lastOutput;

  GitState copyWith({
    bool? loading,
    List<GitChangedFile>? files,
    List<String>? branches,
    String? currentBranch,
    List<GitCommit>? commits,
    String? error,
    String? lastOutput,
  }) {
    return GitState(
      loading: loading ?? this.loading,
      files: files ?? this.files,
      branches: branches ?? this.branches,
      currentBranch: currentBranch ?? this.currentBranch,
      commits: commits ?? this.commits,
      error: error,
      lastOutput: lastOutput ?? this.lastOutput,
    );
  }
}

final gitProvider = NotifierProvider<GitNotifier, GitState>(GitNotifier.new);

class GitNotifier extends Notifier<GitState> {
  @override
  GitState build() => const GitState();

  Future<GitRepository> _repo() => ref.read(gitRepositoryProvider.future);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final repo = await _repo();
      final files = await repo.status();
      final branchInfo = await repo.branches();
      final commits = await repo.log();
      state = GitState(
        files: files,
        branches: branchInfo.branches,
        currentBranch: branchInfo.current,
        commits: commits,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  Future<void> stage(String path) async {
    final repo = await _repo();
    await repo.stage([path]);
    await refresh();
  }

  Future<void> discard(String path) async {
    final repo = await _repo();
    await repo.discard([path]);
    await refresh();
  }

  Future<void> commit(String message) async {
    final repo = await _repo();
    await repo.commit(message);
    await refresh();
  }

  Future<void> stash() async {
    final repo = await _repo();
    await repo.stash();
    await refresh();
  }

  Future<void> sync() async {
    final repo = await _repo();
    await repo.sync();
    await refresh();
  }

  Future<void> checkout(String branch) async {
    final repo = await _repo();
    await repo.checkout(branch);
    await refresh();
  }

  Future<void> exec(String command) async {
    final repo = await _repo();
    final result = await repo.exec(command);
    state = state.copyWith(
      lastOutput: '${result.stdout}${result.stderr}'.trim(),
    );
    await refresh();
  }
}
