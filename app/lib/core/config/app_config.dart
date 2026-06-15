/// Baked-in defaults for the mobile client.
class AppConfig {
  static const String defaultServerUrl =
      'https://aimaxx.example.com';
  static const String defaultApiKey = '';

  AppConfig({
    String? serverUrl,
    String? apiKey,
  })  : serverUrl = normalizeServerUrl(serverUrl ?? defaultServerUrl),
        apiKey = apiKey ?? defaultApiKey;

  String serverUrl;
  String apiKey;

  String get apiBaseUrl => '${_trimTrailingSlash(serverUrl)}/api/';

  /// e.g. `wss://aimaxx.example.com/api/ws/`
  String get webSocketBaseUrl => webSocketUri('').toString();

  /// Build a WebSocket [Uri] without string concat (avoids `:0` port bugs).
  ///
  /// [relativePath] is under `/api/ws/`, e.g. `sync/1/` → `/api/ws/sync/1/`.
  Uri webSocketUri(
    String relativePath, {
    Map<String, String> queryParameters = const {},
  }) {
    final base = Uri.parse(_trimTrailingSlash(serverUrl));
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    // Always set an explicit port — omitting it yields port 0 on some runtimes
    // (Android), which breaks WebSocketChannel.connect.
    final port = _explicitPort(base) ?? (scheme == 'wss' ? 443 : 80);

    final trimmed = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    final path = trimmed.isEmpty
        ? '/api/ws/'
        : '/api/ws/${_ensureTrailingSlash(trimmed)}';

    return Uri(
      scheme: scheme,
      host: base.host,
      port: port,
      path: path,
      queryParameters: queryParameters,
    );
  }

  /// Workspace sync: `wss://{host}/api/ws/sync/{id}/?api_key=…&device_hash=…`
  Uri webSocketSyncUri(
    int workspaceId, {
    Map<String, String> queryParameters = const {},
  }) {
    return webSocketUri(
      'sync/$workspaceId/',
      queryParameters: queryParameters,
    );
  }

  static String _ensureTrailingSlash(String value) {
    return value.endsWith('/') ? value : '$value/';
  }

  /// Strips invalid ports (e.g. `:0`) from persisted or user-entered URLs.
  static String normalizeServerUrl(String raw) {
    var trimmed = raw.trim();
    // Legacy bad values saved with explicit :0
    trimmed = trimmed.replaceAll(RegExp(r':0(?=/|$)'), '');

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return defaultServerUrl;
    }

    final scheme =
        uri.scheme == 'http' || uri.scheme == 'https' ? uri.scheme : 'https';
    final port = _explicitPort(uri);

    if (port != null) {
      return Uri(scheme: scheme, host: uri.host, port: port).toString();
    }
    return Uri(scheme: scheme, host: uri.host).toString();
  }

  /// Only keep non-default, valid ports (never 0/80/443).
  static int? _explicitPort(Uri uri) {
    if (!uri.hasPort) {
      return null;
    }
    final port = uri.port;
    if (port == 0 || port == 80 || port == 443) {
      return null;
    }
    return port;
  }

  static String _trimTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
