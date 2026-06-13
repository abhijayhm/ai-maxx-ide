import 'package:dio/dio.dart';

import '../config/app_config.dart';

typedef SessionHeaders = ({
  String? apiKey,
  String? deviceHash,
  String? workspaceId,
});

class ApiClient {
  ApiClient({
    required this._config,
    required this._readHeaders,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 30)
      ..receiveTimeout = const Duration(seconds: 60)
      ..headers = {'Content-Type': 'application/json'};
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final session = _readHeaders();
          final apiKey = session.apiKey ?? _config.apiKey;
          final deviceHash = session.deviceHash;
          final workspaceId = session.workspaceId;

          options.baseUrl = _config.apiBaseUrl;
          options.headers['X-API-Key'] = apiKey;
          if (deviceHash != null && deviceHash.isNotEmpty) {
            options.headers['X-Device-Identifier'] = deviceHash;
          }
          if (workspaceId != null && workspaceId.isNotEmpty) {
            options.headers['X-Workspace-Id'] = workspaceId;
          }
          handler.next(options);
        },
      ),
    );
  }

  final AppConfig _config;
  final SessionHeaders Function() _readHeaders;
  final Dio _dio;

  Dio get dio => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.get<T>(path, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Options? options,
  }) {
    return _dio.patch<T>(path, data: data, options: options);
  }

  Future<Response<T>> delete<T>(
    String path, {
    Options? options,
  }) {
    return _dio.delete<T>(path, options: options);
  }
}
