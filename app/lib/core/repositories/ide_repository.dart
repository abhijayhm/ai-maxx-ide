import '../api/api_client.dart';
import '../models/route_node.dart';

class IdeRepository {
  IdeRepository(this._api);

  final ApiClient _api;

  Future<List<RouteNode>> fetchExposedRoutesTree() async {
    final response = await _api.get<List<dynamic>>('exposed_routes_tree/');
    final data = response.data ?? [];
    return data
        .map((item) => RouteNode.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<RouteNode>> fetchExposedChildren(String folderPath) async {
    final response = await _api.get<List<dynamic>>(
      'exposed_routes_tree/',
      queryParameters: {'path': folderPath},
    );
    final data = response.data ?? [];
    return data
        .map((item) => RouteNode.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<({int id, String path})> openWorkspace(String folderPath) async {
    final response = await _api.post<Map<String, dynamic>>(
      'workspaces/',
      data: {'path': folderPath},
    );
    final body = response.data!;
    return (id: body['id'] as int, path: body['path'] as String? ?? folderPath);
  }

  Future<RouteNode> fetchWorkspaceTree(int workspaceId) async {
    final response = await _api.get<Map<String, dynamic>>(
      'workspaces/$workspaceId/tree/',
    );
    return RouteNode.fromJson(response.data!);
  }
}
