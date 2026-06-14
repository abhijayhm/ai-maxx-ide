import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../config/app_config.dart';
import '../db/app_database.dart';
import '../device_identifier.dart';

class AuthRepository {
  AuthRepository({
    required this._apiClient,
    required this._database,
    required this._deviceIdentifier,
    required this._config,
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final ApiClient _apiClient;
  final AppDatabase _database;
  final DeviceIdentifierService _deviceIdentifier;
  final AppConfig _config;
  final FlutterSecureStorage _secureStorage;

  static const _apiKeySetting = 'api_key';
  static const _serverUrlSetting = 'server_url';
  static const _workspaceIdSetting = 'active_workspace_id';
  static const _registeredSetting = 'device_registered';

  Future<SessionSnapshot> loadSession() async {
    final secureKey = await _secureStorage.read(key: _apiKeySetting);
    final dbKey = await _database.getSetting(_apiKeySetting);
    final serverUrl = AppConfig.normalizeServerUrl(
      await _database.getSetting(_serverUrlSetting) ??
          AppConfig.defaultServerUrl,
    );
    final workspaceId = await _database.getSetting(_workspaceIdSetting);
    final registered =
        (await _database.getSetting(_registeredSetting)) == 'true';
    final apiKey = secureKey ?? dbKey ?? AppConfig.defaultApiKey;

    _config.serverUrl = serverUrl;
    _config.apiKey = apiKey;
    await _database.setSetting(_serverUrlSetting, serverUrl);

    final deviceHash = await _deviceIdentifier.computeHash();

    return SessionSnapshot(
      apiKey: apiKey,
      serverUrl: serverUrl,
      deviceHash: deviceHash,
      isRegistered: registered,
      activeWorkspaceId: workspaceId,
    );
  }

  Future<SessionSnapshot> registerDevice(String apiKey) async {
    final deviceData = await _deviceIdentifier.collectDeviceData();
    final deviceHash = computeDeviceHash(deviceData);

    _config.apiKey = apiKey;
    await _secureStorage.write(key: _apiKeySetting, value: apiKey);
    await _database.setSetting(_apiKeySetting, apiKey);

    final response = await _apiClient.post<Map<String, dynamic>>(
      'devices/register/',
      data: {
        'hash': deviceHash,
        'data': deviceData,
      },
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'Device registration failed',
      );
    }

    await _database.setSetting(_registeredSetting, 'true');

    return loadSession();
  }

  Future<void> setActiveWorkspace(int workspaceId) async {
    await _database.setSetting(_workspaceIdSetting, workspaceId.toString());
  }

  Future<void> clearActiveWorkspace() async {
    await _database.setSetting(_workspaceIdSetting, null);
  }

  Future<List<WorkspaceSummary>> listWorkspaces() async {
    return const [];
  }

  Future<WorkspaceSummary> openWorkspace(String folderPath) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      'workspaces/',
      data: {'path': folderPath},
    );
    final body = response.data!;
    final workspace = WorkspaceSummary(
      id: body['id'] as int,
      absolutePath: body['path'] as String? ?? folderPath,
      label: body['label'] as String? ?? folderPath,
    );
    await setActiveWorkspace(workspace.id);
    await _database.setSetting(
      AppDatabase.lastWorkspacePathKey,
      workspace.absolutePath,
    );
    return workspace;
  }
}

class SessionSnapshot {
  const SessionSnapshot({
    required this.apiKey,
    required this.serverUrl,
    required this.deviceHash,
    required this.isRegistered,
    this.activeWorkspaceId,
  });

  final String apiKey;
  final String serverUrl;
  final String deviceHash;
  final bool isRegistered;
  final String? activeWorkspaceId;

  bool get isAuthenticated => isRegistered && apiKey.isNotEmpty;

  bool get hasWorkspace =>
      activeWorkspaceId != null && activeWorkspaceId!.isNotEmpty;

  bool get isReady => isAuthenticated && hasWorkspace;
}

class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.absolutePath,
    required this.label,
  });

  final int id;
  final String absolutePath;
  final String label;

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) {
    return WorkspaceSummary(
      id: json['id'] as int,
      absolutePath: json['absolute_path'] as String,
      label: json['label'] as String? ?? '',
    );
  }
}
