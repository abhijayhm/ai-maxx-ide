import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../db/app_database.dart';
import 'sync_models.dart';

/// Sequential workspace sync: metadata JSON first, inline file bodies after.
class WorkspaceSyncService {
  WorkspaceSyncService({
    required ApiClient apiClient,
    required AppDatabase database,
    this.onProgress,
  })  : _apiClient = apiClient,
        _database = database;

  static const int inlineBatchSize = 4;

  final ApiClient _apiClient;
  final AppDatabase _database;
  final void Function(SyncProgress progress)? onProgress;

  int? _activeWorkspaceId;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
  }

  Future<void> syncWorkspace(int workspaceId) async {
    _cancelled = false;
    _activeWorkspaceId = workspaceId;

    _emit(
      SyncProgress(
        phase: SyncPhase.metadata,
        workspaceId: workspaceId,
      ),
    );

    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        'workspaces/$workspaceId/sync/',
      );
      if (_cancelled || _activeWorkspaceId != workspaceId) {
        return;
      }

      final root = SyncTreeNode.fromJson(response.data!);
      final nodes = _flattenTree(root);
      final now = DateTime.now().toUtc().toIso8601String();

      await _database.replaceWorkspaceIndex(
        workspaceId: workspaceId,
        rows: nodes
            .map(
              (node) => IndexedFileRow(
                path: node.path,
                name: node.name,
                type: node.type,
                size: node.size,
                syncPolicy: node.syncPolicy,
                modifiedAt: node.modifiedAt,
                syncedAt: now,
              ),
            )
            .toList(),
      );

      if (_cancelled || _activeWorkspaceId != workspaceId) {
        return;
      }

      final inlineFiles =
          nodes.where((node) => node.isFile && node.isInline).toList();

      _emit(
        SyncProgress(
          phase: SyncPhase.files,
          workspaceId: workspaceId,
          metadataTotal: nodes.length,
          metadataDone: nodes.length,
          filesTotal: inlineFiles.length,
          filesDone: 0,
        ),
      );

      var filesDone = 0;
      for (var i = 0; i < inlineFiles.length; i += inlineBatchSize) {
        if (_cancelled || _activeWorkspaceId != workspaceId) {
          return;
        }

        final chunk = inlineFiles.skip(i).take(inlineBatchSize).toList();
        await _storeInlineBatch(workspaceId, chunk);

        filesDone += chunk.length;
        _emit(
          SyncProgress(
            phase: SyncPhase.files,
            workspaceId: workspaceId,
            metadataTotal: nodes.length,
            metadataDone: nodes.length,
            filesTotal: inlineFiles.length,
            filesDone: filesDone,
          ),
        );
      }

      if (_cancelled || _activeWorkspaceId != workspaceId) {
        return;
      }

      _emit(
        SyncProgress(
          phase: SyncPhase.complete,
          workspaceId: workspaceId,
          metadataTotal: nodes.length,
          metadataDone: nodes.length,
          filesTotal: inlineFiles.length,
          filesDone: inlineFiles.length,
        ),
      );
    } on DioException catch (error) {
      _emit(
        SyncProgress(
          phase: SyncPhase.error,
          workspaceId: workspaceId,
          errorMessage: error.message ?? 'Workspace sync failed',
        ),
      );
    } catch (error) {
      _emit(
        SyncProgress(
          phase: SyncPhase.error,
          workspaceId: workspaceId,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> bindCursorInBackground(int workspaceId) async {
    try {
      await _apiClient.post('workspaces/$workspaceId/bind-cursor/');
    } on DioException {
      // Cursor binding is optional for shell unlock.
    }
  }

  Future<void> _storeInlineBatch(
    int workspaceId,
    List<SyncTreeNode> nodes,
  ) async {
    if (nodes.isEmpty) {
      return;
    }

    final response = await _apiClient.post<Map<String, dynamic>>(
      'workspaces/$workspaceId/sync/files/',
      data: {
        'paths': nodes.map((node) => node.path).toList(),
      },
    );

    final files = response.data?['files'] as List<dynamic>? ?? [];
    for (final raw in files) {
      final item = raw as Map<String, dynamic>;
      final path = item['path'] as String? ?? '';
      final encoded = item['content_base64'] as String?;
      if (path.isEmpty || encoded == null || encoded.isEmpty) {
        continue;
      }

      final bytes = base64Decode(encoded);
      final content = _decodeText(bytes);
      if (content == null) {
        continue;
      }

      await _database.updateFileContent(
        workspaceId: workspaceId,
        path: path,
        content: content,
        contentHash: sha256.convert(utf8.encode(content)).toString(),
      );
    }
  }

  String? _decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  List<SyncTreeNode> _flattenTree(SyncTreeNode root) {
    final nodes = <SyncTreeNode>[];
    void walk(SyncTreeNode node) {
      nodes.add(node);
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(root);
    return nodes;
  }

  void _emit(SyncProgress progress) {
    onProgress?.call(progress);
  }
}
