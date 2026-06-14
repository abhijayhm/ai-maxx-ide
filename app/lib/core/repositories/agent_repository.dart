import '../api/api_client.dart';
import '../models/agent_session.dart';
import '../models/agent_model.dart';

class AgentRepository {
  AgentRepository(this._api);

  final ApiClient _api;

  Future<List<AgentSessionInfo>> fetchSessions() async {
    final response = await _api.get<List<dynamic>>('agent/sessions/');
    final data = response.data ?? [];
    return data
        .map((item) => AgentSessionInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AgentSessionInfo> createSession() async {
    final response = await _api.post<Map<String, dynamic>>('agent/sessions/');
    return AgentSessionInfo.fromJson(response.data!);
  }

  Future<List<AgentModelInfo>> fetchModels() async {
    final response = await _api.get<List<dynamic>>('agent/models/');
    final data = response.data ?? [];
    return data
        .map((item) => AgentModelInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
