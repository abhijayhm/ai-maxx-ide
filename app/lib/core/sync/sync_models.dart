/// Parsed node from `POST /workspaces/{id}/sync/`.
class SyncTreeNode {
  const SyncTreeNode({
    required this.path,
    required this.name,
    required this.type,
    required this.size,
    required this.syncPolicy,
    this.modifiedAt,
    this.contentBase64,
    this.children = const [],
  });

  final String path;
  final String name;
  final String type;
  final int size;
  final String syncPolicy;
  final String? modifiedAt;
  final String? contentBase64;
  final List<SyncTreeNode> children;

  bool get isFile => type == 'file';
  bool get isDirectory => type == 'directory';
  bool get isInline => syncPolicy == 'inline';

  factory SyncTreeNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'] as List<dynamic>? ?? [];
    return SyncTreeNode(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'file',
      size: json['size'] as int? ?? 0,
      syncPolicy: json['sync_policy'] as String? ?? 'metadata_only',
      modifiedAt: json['modified_at'] as String?,
      contentBase64: json['content_base64'] as String?,
      children: rawChildren
          .map((item) => SyncTreeNode.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class IndexedFileRow {
  const IndexedFileRow({
    required this.path,
    required this.name,
    required this.type,
    required this.size,
    required this.syncPolicy,
    this.modifiedAt,
    this.content,
    this.contentHash,
    required this.syncedAt,
  });

  final String path;
  final String name;
  final String type;
  final int size;
  final String syncPolicy;
  final String? modifiedAt;
  final String? content;
  final String? contentHash;
  final String syncedAt;

  bool get hasContent => content != null && content!.isNotEmpty;
}

enum SyncPhase {
  idle,
  metadata,
  files,
  complete,
  error,
}

class SyncProgress {
  const SyncProgress({
    required this.phase,
    this.workspaceId,
    this.metadataTotal = 0,
    this.metadataDone = 0,
    this.filesTotal = 0,
    this.filesDone = 0,
    this.errorMessage,
  });

  final SyncPhase phase;
  final int? workspaceId;
  final int metadataTotal;
  final int metadataDone;
  final int filesTotal;
  final int filesDone;
  final String? errorMessage;

  bool get isActive =>
      phase == SyncPhase.metadata || phase == SyncPhase.files;

  String get statusLabel {
    switch (phase) {
      case SyncPhase.idle:
        return '';
      case SyncPhase.metadata:
        return 'Indexing workspace…';
      case SyncPhase.files:
        if (filesTotal == 0) {
          return 'Indexing workspace…';
        }
        return 'Syncing files $filesDone/$filesTotal';
      case SyncPhase.complete:
        return 'Synced';
      case SyncPhase.error:
        return errorMessage ?? 'Sync failed';
    }
  }

  SyncProgress copyWith({
    SyncPhase? phase,
    int? workspaceId,
    int? metadataTotal,
    int? metadataDone,
    int? filesTotal,
    int? filesDone,
    String? errorMessage,
  }) {
    return SyncProgress(
      phase: phase ?? this.phase,
      workspaceId: workspaceId ?? this.workspaceId,
      metadataTotal: metadataTotal ?? this.metadataTotal,
      metadataDone: metadataDone ?? this.metadataDone,
      filesTotal: filesTotal ?? this.filesTotal,
      filesDone: filesDone ?? this.filesDone,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
