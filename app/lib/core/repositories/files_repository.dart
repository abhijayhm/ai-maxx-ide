import '../api/api_client.dart';
import '../api/api_manifest.dart';

class FilesRepository {
  FilesRepository(this._api);

  final ApiClient _api;

  Future<String> mkdir(String parentPath, String name) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiManifest.filesMkdir,
      data: {'path': parentPath, 'name': name},
    );
    return response.data?['path'] as String? ?? '';
  }

  Future<String> touch(String parentPath, String name) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiManifest.filesTouch,
      data: {'path': parentPath, 'name': name},
    );
    return response.data?['path'] as String? ?? '';
  }
}
