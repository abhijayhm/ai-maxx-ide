import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../config/app_config.dart';
import '../db/app_database.dart';
import '../ws/ws_client.dart';
import 'sync_models.dart';

/// Workspace sync over a single WebSocket session.
///
/// Server pushes metadata, inline file batches, and bind-cursor in parallel.
class WorkspaceSyncService {
  WorkspaceSyncService({
    required AppConfig config,
    required WsSessionHeaders Function() readHeaders,
    required AppDatabase database,
    this.onProgress,
  })  : _ws = WsClient(config: config, readHeaders: readHeaders),
        _database = database;

  static const _messageTimeout = Duration(minutes: 10);

  final WsClient _ws;
  final AppDatabase _database;
  final void Function(SyncProgress progress)? onProgress;

  int? _activeWorkspaceId;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _ws.send({'type': 'cancel'});
    unawaited(_ws.disconnect());
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
      await _ws.connectSync(workspaceId);

      final ready = await _waitForType('ready');
      if (ready == null || _cancelled || _activeWorkspaceId != workspaceId) {
        return;
      }

      _ws.send({'type': 'start'});

      var metadataTotal = 0;
      var inlineTotal = 0;
      var filesDone = 0;

      while (!_cancelled && _activeWorkspaceId == workspaceId) {
        final message = await _nextMessage();
        if (message == null) {
          _emit(
            SyncProgress(
              phase: SyncPhase.error,
              workspaceId: workspaceId,
              errorMessage: 'Sync timed out waiting for server',
            ),
          );
          return;
        }

        final type = message['type'] as String? ?? '';

        if (type == 'sync_started' || type == 'bind_cursor') {
          continue;
        }

        if (type == 'metadata') {
          final root = SyncTreeNode.fromJson(
            message['tree'] as Map<String, dynamic>,
          );
          inlineTotal = message['files_total'] as int? ?? 0;
          final nodes = _flattenTree(root);
          metadataTotal = nodes.length;

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
                    syncedAt: DateTime.now().toUtc().toIso8601String(),
                  ),
                )
                .toList(),
          );

          _emit(
            SyncProgress(
              phase: SyncPhase.files,
              workspaceId: workspaceId,
              metadataTotal: metadataTotal,
              metadataDone: metadataTotal,
              filesTotal: inlineTotal,
              filesDone: 0,
            ),
          );
          continue;
        }

        if (type == 'files') {
          final files = message['files'] as List<dynamic>? ?? [];
          filesDone = message['files_done'] as int? ?? filesDone;
          inlineTotal = message['files_total'] as int? ?? inlineTotal;

          for (final raw in files) {
            await _storeFile(workspaceId, raw as Map<String, dynamic>);
          }

          _emit(
            SyncProgress(
              phase: SyncPhase.files,
              workspaceId: workspaceId,
              metadataTotal: metadataTotal,
              metadataDone: metadataTotal,
              filesTotal: inlineTotal,
              filesDone: filesDone,
            ),
          );
          continue;
        }

        if (type == 'complete') {
          _emit(
            SyncProgress(
              phase: SyncPhase.complete,
              workspaceId: workspaceId,
              metadataTotal: metadataTotal,
              metadataDone: metadataTotal,
              filesTotal: inlineTotal,
              filesDone: filesDone,
            ),
          );
          return;
        }

        if (type == 'error' ||
            type == 'connection_closed' ||
            type == 'connection_error') {
          _emit(
            SyncProgress(
              phase: SyncPhase.error,
              workspaceId: workspaceId,
              errorMessage: message['message'] as String? ??
                  'Workspace sync failed',
            ),
          );
          return;
        }
      }
    } catch (error) {
      if (!_cancelled) {
        _emit(
          SyncProgress(
            phase: SyncPhase.error,
            workspaceId: workspaceId,
            errorMessage: error.toString(),
          ),
        );
      }
    } finally {
      await _ws.disconnect();
    }
  }

  Future<Map<String, dynamic>?> _waitForType(String type) async {
    final deadline = DateTime.now().add(_messageTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final message = await _nextMessage();
      if (message == null) {
        return null;
      }
      if (message['type'] == type) {
        return message;
      }
      if (message['type'] == 'error') {
        return message;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _nextMessage() async {
    try {
      return await _ws.receive().timeout(_messageTimeout);
    } on TimeoutException {
      return null;
    } on StateError {
      return null;
    }
  }

  Future<void> _storeFile(int workspaceId, Map<String, dynamic> item) async {
    final path = item['path'] as String? ?? '';
    final encoded = item['content_base64'] as String?;
    if (path.isEmpty || encoded == null || encoded.isEmpty) {
      return;
    }

    final bytes = base64Decode(encoded);
    final content = _decodeText(bytes);
    if (content == null) {
      return;
    }

    await _database.updateFileContent(
      workspaceId: workspaceId,
      path: path,
      content: content,
      contentHash: sha256.convert(utf8.encode(content)).toString(),
    );
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
