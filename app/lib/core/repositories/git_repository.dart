import '../api/api_client.dart';
import '../api/api_manifest.dart';

class GitRepository {
  GitRepository(this._api);

  final ApiClient _api;

  Future<List<GitChangedFile>> status() async {
    final response = await _api.get<Map<String, dynamic>>(ApiManifest.gitStatus);
    final files = response.data?['files'] as List<dynamic>? ?? [];
    return files
        .map((item) => GitChangedFile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<GitBranches> branches() async {
    final response =
        await _api.get<Map<String, dynamic>>(ApiManifest.gitBranches);
    return GitBranches.fromJson(response.data!);
  }

  Future<List<GitCommit>> log({int limit = 20}) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiManifest.gitLog,
      queryParameters: {'limit': limit},
    );
    final commits = response.data?['commits'] as List<dynamic>? ?? [];
    return commits
        .map((item) => GitCommit.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> stage(List<String> paths) async {
    await _api.post(ApiManifest.gitStage, data: {'paths': paths});
  }

  Future<void> discard(List<String> paths) async {
    await _api.post(ApiManifest.gitDiscard, data: {'paths': paths});
  }

  Future<void> stash({String message = 'WIP'}) async {
    await _api.post(ApiManifest.gitStash, data: {'message': message});
  }

  Future<void> commit(String message) async {
    await _api.post(ApiManifest.gitCommit, data: {'message': message});
  }

  Future<void> sync() async {
    await _api.post(ApiManifest.gitSync);
  }

  Future<void> checkout(String branch) async {
    await _api.post(ApiManifest.gitCheckout, data: {'branch': branch});
  }

  Future<GitExecResult> exec(String command) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiManifest.gitExec,
      data: {'command': command},
    );
    return GitExecResult.fromJson(response.data!);
  }
}

class GitChangedFile {
  const GitChangedFile({required this.status, required this.path});

  final String status;
  final String path;

  factory GitChangedFile.fromJson(Map<String, dynamic> json) {
    return GitChangedFile(
      status: json['status'] as String? ?? '?',
      path: json['path'] as String? ?? '',
    );
  }
}

class GitBranches {
  const GitBranches({required this.branches, this.current});

  final List<String> branches;
  final String? current;

  factory GitBranches.fromJson(Map<String, dynamic> json) {
    return GitBranches(
      branches: (json['branches'] as List<dynamic>? ?? [])
          .map((item) => item as String)
          .toList(),
      current: json['current'] as String?,
    );
  }
}

class GitCommit {
  const GitCommit({
    required this.hash,
    required this.subject,
    required this.author,
    required this.date,
  });

  final String hash;
  final String subject;
  final String author;
  final String date;

  factory GitCommit.fromJson(Map<String, dynamic> json) {
    return GitCommit(
      hash: json['hash'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      author: json['author'] as String? ?? '',
      date: json['date'] as String? ?? '',
    );
  }
}

class GitExecResult {
  const GitExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  factory GitExecResult.fromJson(Map<String, dynamic> json) {
    return GitExecResult(
      exitCode: json['exit_code'] as int? ?? 0,
      stdout: json['stdout'] as String? ?? '',
      stderr: json['stderr'] as String? ?? '',
    );
  }
}
