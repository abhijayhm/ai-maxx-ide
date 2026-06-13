import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../sync/sync_models.dart';

class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static AppDatabase? _instance;

  static Future<AppDatabase> open() async {
    if (_instance != null) {
      return _instance!;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'ai_maxx_ide.db');
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (database, version) async {
        await _createSettingsTable(database);
        await _createFilesTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createFilesTable(database);
        }
      },
    );
    _instance = AppDatabase._(db);
    return _instance!;
  }

  static Future<void> _createSettingsTable(Database database) async {
    await database.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  static Future<void> _createFilesTable(Database database) async {
    await database.execute('''
      CREATE TABLE files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id INTEGER NOT NULL,
        path TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        sync_policy TEXT NOT NULL DEFAULT 'metadata_only',
        modified_at TEXT,
        content TEXT,
        content_hash TEXT,
        synced_at TEXT NOT NULL,
        UNIQUE(workspace_id, path)
      )
    ''');
    await database.execute(
      'CREATE INDEX idx_files_workspace_name ON files(workspace_id, name)',
    );
    await database.execute(
      'CREATE INDEX idx_files_workspace_path ON files(workspace_id, path)',
    );
  }

  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> allSettings() async {
    final rows = await _db.query('settings');
    return {
      for (final row in rows)
        row['key']! as String: row['value']! as String,
    };
  }

  Future<void> replaceWorkspaceIndex({
    required int workspaceId,
    required List<IndexedFileRow> rows,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'files',
        where: 'workspace_id = ?',
        whereArgs: [workspaceId],
      );
      for (final row in rows) {
        await txn.insert(
          'files',
          {
            'workspace_id': workspaceId,
            'path': row.path,
            'name': row.name,
            'type': row.type,
            'size': row.size,
            'sync_policy': row.syncPolicy,
            'modified_at': row.modifiedAt,
            'content': row.content,
            'content_hash': row.contentHash,
            'synced_at': row.syncedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> updateFileContent({
    required int workspaceId,
    required String path,
    required String content,
    String? contentHash,
  }) async {
    await _db.update(
      'files',
      {
        'content': content,
        'content_hash': contentHash,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'workspace_id = ? AND path = ?',
      whereArgs: [workspaceId, path],
    );
  }

  Future<List<IndexedFileRow>> searchFiles({
    required int workspaceId,
    required String query,
    int limit = 50,
  }) async {
    final pattern = '%$query%';
    final rows = await _db.query(
      'files',
      where:
          'workspace_id = ? AND type = ? AND (name LIKE ? OR path LIKE ?)',
      whereArgs: [workspaceId, 'file', pattern, pattern],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map(_rowToIndexedFile).toList();
  }

  Future<int> countIndexedFiles(int workspaceId) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM files WHERE workspace_id = ? AND type = ?',
      [workspaceId, 'file'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countSyncedContents(int workspaceId) async {
    final result = await _db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM files
      WHERE workspace_id = ? AND type = ? AND content IS NOT NULL AND content != ''
      ''',
      [workspaceId, 'file'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  IndexedFileRow _rowToIndexedFile(Map<String, Object?> row) {
    return IndexedFileRow(
      path: row['path']! as String,
      name: row['name']! as String,
      type: row['type']! as String,
      size: row['size']! as int,
      syncPolicy: row['sync_policy']! as String,
      modifiedAt: row['modified_at'] as String?,
      content: row['content'] as String?,
      contentHash: row['content_hash'] as String?,
      syncedAt: row['synced_at']! as String,
    );
  }
}
