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

  /// Workspace-scoped list; server creates a default session when none exist.
  Future<List<AgentSessionInfo>> fetchWorkspaceSessions(int workspaceId) async {
    final response = await _api.get<List<dynamic>>(
      'workspaces/$workspaceId/agent/sessions/',
    );
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

  Future<List<StoredAgentMessage>> fetchMessages(
    int sessionId, {
    int limit = 500,
    int offset = 0,
  }) async {
    final response = await _api.get<List<dynamic>>(
      'agent/messages/',
      queryParameters: {
        'session_id': sessionId,
        'limit': limit,
        'offset': offset,
      },
    );
    final data = response.data ?? [];
    return data
        .map((item) => StoredAgentMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

class StoredAgentMessage {
  const StoredAgentMessage({
    required this.sender,
    required this.payload,
  });

  final String sender;
  final Map<String, dynamic> payload;

  factory StoredAgentMessage.fromJson(Map<String, dynamic> json) {
    return StoredAgentMessage(
      sender: json['sender'] as String? ?? '',
      payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
    );
  }
}
