import 'dart:convert';

import '../api/api_client.dart';
import '../api/api_manifest.dart';

class TerminalRepository {
  TerminalRepository(this._api);

  final ApiClient _api;

  Future<List<TerminalSession>> list() async {
    final response = await _api.get<List<dynamic>>(ApiManifest.terminals);
    return (response.data ?? [])
        .map((item) => TerminalSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TerminalSession> create({String? name, String? cwd}) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiManifest.terminals,
      data: {
        if (name != null) 'name': name,
        if (cwd != null) 'cwd': cwd,
      },
    );
    return TerminalSession.fromJson(response.data!);
  }

  Future<void> delete(int id) async {
    await _api.delete(ApiManifest.terminalDetail(id));
  }

  Future<TerminalExecResult> exec(int id, String command) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiManifest.terminalExec(id),
      data: {'command': command},
    );
    return TerminalExecResult.fromJson(response.data!);
  }
}

class TerminalSession {
  const TerminalSession({
    required this.id,
    required this.name,
    required this.shell,
    required this.cwd,
    required this.status,
  });

  final int id;
  final String name;
  final String shell;
  final String cwd;
  final String status;

  factory TerminalSession.fromJson(Map<String, dynamic> json) {
    return TerminalSession(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'terminal',
      shell: json['shell'] as String? ?? 'powershell',
      cwd: json['cwd'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
    );
  }
}

class TerminalExecResult {
  const TerminalExecResult({required this.stdout, required this.stderr});

  final String stdout;
  final String stderr;

  factory TerminalExecResult.fromJson(Map<String, dynamic> json) {
    return TerminalExecResult(
      stdout: json['stdout'] as String? ?? '',
      stderr: json['stderr'] as String? ?? '',
    );
  }
}

/// Encode keystrokes for terminal WebSocket input frame.
String encodeTerminalInput(String text) {
  return base64Encode(utf8.encode(text));
}

/// Decode PTY output frame from terminal WebSocket.
String? decodeTerminalOutput(Map<String, dynamic> message) {
  if (message['type'] != 'output') {
    return null;
  }
  final encoded = message['data'] as String? ?? '';
  if (encoded.isEmpty) {
    return null;
  }
  return utf8.decode(base64Decode(encoded));
}
