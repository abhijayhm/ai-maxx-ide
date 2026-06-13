import '../api/api_client.dart';
import '../api/api_manifest.dart';

class SearchRepository {
  SearchRepository(this._api);

  final ApiClient _api;

  Future<List<ServerFileHit>> searchFiles(String query, {int limit = 50}) async {
    if (query.trim().isEmpty) {
      return [];
    }
    final response = await _api.get<List<dynamic>>(
      ApiManifest.searchFiles,
      queryParameters: {'q': query, 'limit': limit},
    );
    return (response.data ?? [])
        .map((item) => ServerFileHit.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<GrepHit>> grep(
    String pattern, {
    String glob = '*',
    bool caseSensitive = false,
  }) async {
    if (pattern.trim().isEmpty) {
      return [];
    }
    final response = await _api.post<List<dynamic>>(
      ApiManifest.searchGrep,
      data: {
        'pattern': pattern,
        'glob': glob,
        'case_sensitive': caseSensitive,
      },
    );
    return (response.data ?? [])
        .map((item) => GrepHit.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

class ServerFileHit {
  const ServerFileHit({required this.name, required this.path});

  final String name;
  final String path;

  factory ServerFileHit.fromJson(Map<String, dynamic> json) {
    return ServerFileHit(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }
}

class GrepHit {
  const GrepHit({
    required this.path,
    required this.lineStart,
    required this.lineEnd,
    required this.matches,
  });

  final String path;
  final int lineStart;
  final int lineEnd;
  final List<GrepMatchLine> matches;

  factory GrepHit.fromJson(Map<String, dynamic> json) {
    final rawMatches = json['matches'] as List<dynamic>? ?? [];
    return GrepHit(
      path: json['path'] as String? ?? '',
      lineStart: json['line_start'] as int? ?? 0,
      lineEnd: json['line_end'] as int? ?? 0,
      matches: rawMatches
          .map((item) => GrepMatchLine.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class GrepMatchLine {
  const GrepMatchLine({required this.line, required this.text});

  final int line;
  final String text;

  factory GrepMatchLine.fromJson(Map<String, dynamic> json) {
    return GrepMatchLine(
      line: json['line'] as int? ?? 0,
      text: json['text'] as String? ?? '',
    );
  }
}
