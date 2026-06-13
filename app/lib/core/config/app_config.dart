/// Baked-in defaults for the mobile client.
class AppConfig {
  static const String defaultServerUrl = 'https://aimaxx.organisationapp.online';
  static const String defaultApiKey = 'change-me-to-a-long-random-secret';

  AppConfig({
    String? serverUrl,
    String? apiKey,
  })  : serverUrl = serverUrl ?? defaultServerUrl,
        apiKey = apiKey ?? defaultApiKey;

  String serverUrl;
  String apiKey;

  String get apiBaseUrl => '${_trimTrailingSlash(serverUrl)}/api/';

  String get webSocketBaseUrl {
    final uri = Uri.parse(serverUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final host = uri.hasPort && uri.port != 80 && uri.port != 443
        ? '${uri.host}:${uri.port}'
        : uri.host;
    return '$scheme://$host/ws/';
  }

  static String _trimTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
