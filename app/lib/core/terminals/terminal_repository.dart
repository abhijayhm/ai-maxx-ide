import '../api/api_client.dart';
import 'terminal_models.dart';

class TerminalRepository {
  TerminalRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  Future<List<TerminalSession>> listActive() async {
    final resp = await _api.get<List<dynamic>>('terminals/');
    final data = resp.data ?? [];
    return data
        .map((e) => TerminalSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TerminalSession> create({
    String? name,
    String? shell,
    String? cwd,
    int cols = 80,
    int rows = 24,
  }) async {
    final resp = await _api.post<Map<String, dynamic>>(
      'terminals/',
      data: {
        if (name != null) 'name': name,
        if (shell != null) 'shell': shell,
        if (cwd != null) 'cwd': cwd,
        'cols': cols,
        'rows': rows,
      },
    );
    return TerminalSession.fromJson(resp.data!);
  }

  Future<void> close(int id) async {
    await _api.delete('terminals/$id/');
  }

  Future<List<TerminalIOLine>> fetchIo(int id, {int limit = 500}) async {
    final resp = await _api.get<List<dynamic>>(
      'terminals/$id/io/',
      queryParameters: {'limit': limit},
    );
    final data = resp.data ?? [];
    return data
        .map((e) => TerminalIOLine.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
