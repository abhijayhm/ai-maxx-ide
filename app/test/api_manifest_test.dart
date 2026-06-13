import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_maxx_ide/core/api/api_manifest.dart';
import 'package:ai_maxx_ide/core/config/app_config.dart';

void main() {
  late Map<String, dynamic> urlsConfig;

  setUpAll(() {
    final file = File('${Directory.current.path}/../common/urls.json');
    urlsConfig = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  test('ApiManifest matches common/urls.json base paths', () {
    expect(urlsConfig['api_base_path'], ApiManifest.apiBasePath);
    expect(urlsConfig['ws_base_path'], ApiManifest.wsBasePath);
  });

  test('rest paths in manifest match urls.json', () {
    final rest = urlsConfig['rest'] as Map<String, dynamic>;
    for (final entry in ApiManifest.restPaths.entries) {
      expect(rest[entry.key]['path'], entry.value);
    }
  });

  test('AppConfig builds sync WebSocket URI without :0 port', () {
    final config = AppConfig();
    final uri = config.webSocketSyncUri(
      1,
      queryParameters: {
        'api_key': 'test',
        'device_hash': 'abc',
        'workspace_id': '1',
      },
    );
    expect(uri.scheme, 'wss');
    expect(uri.host, 'aimaxx.organisationapp.online');
    expect(uri.port, 443);
    expect(uri.path, '/api/ws/sync/1/');
    expect(uri.toString(), isNot(contains(':0/')));
    expect(uri.toString(), isNot(contains('https://')));
  });

  test('websocket paths in urls.json match ApiManifest', () {
    final ws = urlsConfig['websocket'] as Map<String, dynamic>;
    expect(ws['agent']['path'], ApiManifest.wsAgent);
    expect(ws['sync']['path'], 'sync/{workspace_id}/');
    expect(ws['terminals']['path'], 'terminals/{session_id}/');
    expect(ws['remote']['path'], ApiManifest.wsRemote);
  });
}
