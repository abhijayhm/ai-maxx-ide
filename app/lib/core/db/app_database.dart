import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/route_node.dart';

class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static AppDatabase? _instance;

  static const cacheKeyExposed = 'exposed';
  static String workspaceCacheKey(int workspaceId) => 'workspace_$workspaceId';

  static const lastWorkspacePathKey = 'last_workspace_path';

  static Future<AppDatabase> open() async {
    if (_instance != null) {
      return _instance!;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'ai_maxx_ide.db');
    final db = await openDatabase(
      path,
      version: 4,
      onCreate: (database, version) async {
        await _createSettingsTable(database);
        await _createRouteCacheTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await database.execute('DROP TABLE IF EXISTS files');
        }
        if (oldVersion < 4) {
          await _createRouteCacheTable(database);
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

  static Future<void> _createRouteCacheTable(Database database) async {
    await database.execute('''
      CREATE TABLE route_cache (
        cache_key TEXT PRIMARY KEY,
        tree_json TEXT NOT NULL,
        flat_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
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

  Future<void> saveRouteCache({
    required String cacheKey,
    required List<RouteNode> tree,
    required List<RouteNode> flat,
  }) async {
    await _db.insert(
      'route_cache',
      {
        'cache_key': cacheKey,
        'tree_json': jsonEncode(tree.map((node) => node.toJson()).toList()),
        'flat_json': jsonEncode(flat.map((node) => node.toJsonFlat()).toList()),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<({List<RouteNode> tree, List<RouteNode> flat})?> loadRouteCache(
    String cacheKey,
  ) async {
    final rows = await _db.query(
      'route_cache',
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    final treeRaw = jsonDecode(row['tree_json']! as String) as List<dynamic>;
    final flatRaw = jsonDecode(row['flat_json']! as String) as List<dynamic>;
    return (
      tree: treeRaw
          .map((item) => RouteNode.fromJson(item as Map<String, dynamic>))
          .toList(),
      flat: flatRaw
          .map((item) => RouteNode.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
