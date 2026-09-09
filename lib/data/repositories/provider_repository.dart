import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/models/provider.dart';
import '../../core/storage/app_database.dart';
import '../../core/utils/ids.dart';

/// CRUD + queries for provider profiles (configurations only; API keys are
/// stored separately in secure storage by the caller's service).
///
/// Provider rows keep a JSON configuration blob (indexed columns are only the
/// ones needed for listing/ordering) so adding future configuration fields
/// never requires a database migration.
class ProviderRepository {
  const ProviderRepository();

  Future<List<AIProvider>> listAll() async {
    final db = await AppDatabase.instance;
    final rows =
        await db.query('providers', orderBy: 'sort_order ASC, name ASC');
    return rows.map((r) => AIProvider.fromJson(
        jsonDecode(r['data'] as String) as Map<String, dynamic>)).toList();
  }

  Future<List<AIProvider>> listEnabled() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('providers',
        where: 'is_enabled = 1', orderBy: 'sort_order ASC, name ASC');
    return rows.map((r) => AIProvider.fromJson(
        jsonDecode(r['data'] as String) as Map<String, dynamic>)).toList();
  }

  Future<AIProvider?> findById(String id) async {
    final db = await AppDatabase.instance;
    final rows = await db
        .query('providers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return AIProvider.fromJson(
        jsonDecode(rows.first['data'] as String) as Map<String, dynamic>);
  }

  Future<void> upsert(AIProvider provider) async {
    final db = await AppDatabase.instance;
    final existing = await db.query('providers',
        where: 'id = ?', whereArgs: [provider.id], limit: 1);
    final sortOrder = existing.isEmpty
        ? Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM providers')) ?? 0
        : existing.first['sort_order'] as int? ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'providers',
      {
        'id': provider.id,
        'name': provider.name,
        'type': provider.type.name,
        'is_enabled': provider.isEnabled ? 1 : 0,
        'created_at': provider.createdAt?.millisecondsSinceEpoch ?? now,
        'updated_at': provider.updatedAt?.millisecondsSinceEpoch ?? now,
        'sort_order': sortOrder,
        'data': jsonEncode(provider.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Duplicates a provider with a new id/name, returning the copy.
  Future<AIProvider> duplicate(AIProvider source, {String? newName}) async {
    final copy = AIProvider(
      id: Ids.newId('prov'),
      name: newName ?? '${source.name} (copy)',
      type: source.type,
      baseUrl: source.baseUrl,
      authMethod: source.authMethod,
      customAuthHeaderName: source.customAuthHeaderName,
      customAuthHeaderValue: source.customAuthHeaderValue,
      customHeaders: source.customHeaders,
      enabledCapabilities: source.enabledCapabilities,
      capabilityEndpoints: source.capabilityEndpoints,
      capabilityMethods: source.capabilityMethods,
      capabilityRequestTemplates: source.capabilityRequestTemplates,
      capabilityResponsePaths: source.capabilityResponsePaths,
      model: source.model,
      endpoint: source.endpoint,
      isEnabled: source.isEnabled,
      streamingEnabled: source.streamingEnabled,
      httpMethod: source.httpMethod,
      requestBodyTemplate: source.requestBodyTemplate,
      responsePath: source.responsePath,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await upsert(copy);
    return copy;
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.instance;
    await db.delete('providers', where: 'id = ?', whereArgs: [id]);
    // Orphan chats stay viewable but lose their provider link.
    await db.delete('saved_models', where: 'provider_id = ?', whereArgs: [id]);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final db = await AppDatabase.instance;
    await db.update(
      'providers',
      {'is_enabled': enabled ? 1 : 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> rememberModel(String providerId, String model,
      {bool favorite = false}) async {
    if (model.isEmpty) return;
    final db = await AppDatabase.instance;
    final rows = await db.query('saved_models',
        where: 'provider_id = ? AND model = ?', whereArgs: [providerId, model]);
    if (rows.isNotEmpty) {
      await db.update(
        'saved_models',
        {
          'is_favorite': favorite
              ? 1
              : (rows.first['is_favorite'] as int? ?? 0),
          'last_used_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'provider_id = ? AND model = ?',
        whereArgs: [providerId, model],
      );
    } else {
      await db.insert('saved_models', {
        'provider_id': providerId,
        'model': model,
        'is_favorite': favorite ? 1 : 0,
        'last_used_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> setModelFavorite(
      String providerId, String model, bool favorite) async {
    final db = await AppDatabase.instance;
    await db.update('saved_models', {'is_favorite': favorite ? 1 : 0},
        where: 'provider_id = ? AND model = ?',
        whereArgs: [providerId, model]);
  }

  Future<List<String>> recentModels(String providerId) async {
    final db = await AppDatabase.instance;
    final rows = await db.query('saved_models',
        where: 'provider_id = ?',
        whereArgs: [providerId],
        orderBy: 'last_used_at DESC',
        limit: 20);
    return rows.map((e) => e['model'] as String).toList();
  }

  Future<List<String>> favoriteModels(String providerId) async {
    final db = await AppDatabase.instance;
    final rows = await db.query('saved_models',
        where: 'provider_id = ? AND is_favorite = 1',
        whereArgs: [providerId],
        orderBy: 'last_used_at DESC');
    return rows.map((e) => e['model'] as String).toList();
  }
}
