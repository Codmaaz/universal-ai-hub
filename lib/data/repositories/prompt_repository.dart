import 'package:sqflite/sqflite.dart';

import '../../core/models/system_prompt.dart';
import '../../core/storage/app_database.dart';
import '../../core/utils/ids.dart';

/// Persists system prompts (user created + built-ins seeded once).
class PromptRepository {
  const PromptRepository();

  Future<void> seedBuiltins() async {
    final db = await AppDatabase.instance;
    final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM prompts WHERE is_built_in = 1'));
    if ((count ?? 0) > 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in BuiltinPrompts.all()) {
      await db.insert('prompts', {
        'id': p.id,
        'title': p.title,
        'content': p.content,
        'is_favorite': p.isFavorite ? 1 : 0,
        'is_built_in': p.isBuiltIn ? 1 : 0,
        'updated_at': now,
      });
    }
  }

  Future<List<SystemPrompt>> listAll({String? search}) async {
    final db = await AppDatabase.instance;
    final rows = search == null || search.trim().isEmpty
        ? await db.query('prompts', orderBy: 'is_favorite DESC, title ASC')
        : await db.query('prompts',
            where: 'title LIKE ? OR content LIKE ?',
            whereArgs: ['%${search.trim()}%', '%${search.trim()}%'],
            orderBy: 'is_favorite DESC, title ASC');
    return rows.map((r) => SystemPrompt(
          id: r['id'] as String,
          title: r['title'] as String,
          content: (r['content'] ?? '') as String,
          isFavorite: (r['is_favorite'] as int? ?? 0) == 1,
          isBuiltIn: (r['is_built_in'] as int? ?? 0) == 1,
        )).toList();
  }

  Future<SystemPrompt?> findById(String id) async {
    final db = await AppDatabase.instance;
    final rows =
        await db.query('prompts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SystemPrompt(
      id: r['id'] as String,
      title: r['title'] as String,
      content: (r['content'] ?? '') as String,
      isFavorite: (r['is_favorite'] as int? ?? 0) == 1,
      isBuiltIn: (r['is_built_in'] as int? ?? 0) == 1,
    );
  }

  Future<SystemPrompt> create(
      {required String title, required String content}) async {
    final p = SystemPrompt(
        id: Ids.newId('prompt'), title: title, content: content);
    await _upsert(p);
    return p;
  }

  Future<void> update(SystemPrompt prompt) => _upsert(prompt);

  Future<void> _upsert(SystemPrompt p) async {
    final db = await AppDatabase.instance;
    await db.insert('prompts', {
      'id': p.id,
      'title': p.title,
      'content': p.content,
      'is_favorite': p.isFavorite ? 1 : 0,
      'is_built_in': p.isBuiltIn ? 1 : 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<SystemPrompt> duplicate(SystemPrompt source,
      {String? newTitle}) async {
    final copy = SystemPrompt(
      id: Ids.newId('prompt'),
      title: newTitle ?? '${source.title} (copy)',
      content: source.content,
      isFavorite: source.isFavorite,
      isBuiltIn: false,
    );
    await _upsert(copy);
    return copy;
  }

  Future<void> toggleFavorite(String id) async {
    final p = await findById(id);
    if (p == null) return;
    await _upsert(p.copyWith(isFavorite: !p.isFavorite));
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.instance;
    await db.delete('prompts', where: 'id = ?', whereArgs: [id]);
  }
}
