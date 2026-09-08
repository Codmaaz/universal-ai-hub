import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';

/// Opens the application SQLite database and creates the schema.
///
/// Only *configurations* live here. API keys and other secrets are never
/// written to SQLite — they live in [SecureTokenStore].
abstract final class AppDatabase {
  static Database? _db;

  static Future<Database> get instance async => _db ??= await _open();

  static Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'uai_hub.db');
    return openDatabase(
      path,
      version: AppConstants.schemaVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 1) await _createSchema(db);
      },
    );
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE providers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER,
        updated_at INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        data TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        provider_id TEXT NOT NULL,
        model TEXT NOT NULL DEFAULT '',
        system_prompt TEXT NOT NULL DEFAULT '',
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        seq INTEGER NOT NULL,
        content TEXT NOT NULL,
        is_error INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_messages_conv ON messages(conversation_id, seq)');
    await db.execute('''
      CREATE TABLE prompts (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_built_in INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE saved_models (
        provider_id TEXT NOT NULL,
        model TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        last_used_at INTEGER,
        PRIMARY KEY (provider_id, model)
      )
    ''');
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Destroys every row (used by Clear all data).
  static Future<void> wipe() async {
    final db = await instance;
    for (final table in [
      'messages',
      'conversations',
      'providers',
      'prompts',
      'saved_models',
    ]) {
      await db.delete(table);
    }
  }
}
