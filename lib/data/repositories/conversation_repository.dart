import 'package:sqflite/sqflite.dart';

import '../../core/models/conversation.dart';
import '../../core/models/types.dart';
import '../../core/storage/app_database.dart';
import '../../core/utils/ids.dart';

/// Persists conversations and their messages. Store-backed slices only —
/// never secrets.
class ConversationRepository {
  const ConversationRepository();

  // ---- Conversations -----------------------------------------------------

  Future<ChatConversation> create({
    required String providerId,
    String title = 'New chat',
    String model = '',
    String systemPrompt = '',
  }) async {
    final now = DateTime.now();
    final conv = ChatConversation(
      id: Ids.newId('chat'),
      title: title,
      providerId: providerId,
      model: model,
      systemPrompt: systemPrompt,
      createdAt: now,
      updatedAt: now,
    );
    final db = await AppDatabase.instance;
    await db.insert('conversations', {
      'id': conv.id,
      'title': conv.title,
      'provider_id': conv.providerId,
      'model': conv.model,
      'system_prompt': conv.systemPrompt,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return conv;
  }

  Future<ChatConversation?> findById(String id) async {
    final db = await AppDatabase.instance;
    final rows = await db
        .query('conversations', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ChatConversation(
      id: r['id'] as String,
      title: r['title'] as String,
      providerId: r['provider_id'] as String,
      model: (r['model'] ?? '') as String,
      systemPrompt: (r['system_prompt'] ?? '') as String,
      createdAt: r['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int)
          : null,
      updatedAt: r['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int)
          : null,
    );
  }

  /// Persists metadata changes (provider/model/system prompt) for an existing
  /// conversation; creates the row when it does not exist yet.
  Future<void> upsertConversation(ChatConversation conversation) async {
    final db = await AppDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'conversations',
      {
        'id': conversation.id,
        'title': conversation.title,
        'provider_id': conversation.providerId,
        'model': conversation.model,
        'system_prompt': conversation.systemPrompt,
        'created_at': conversation.createdAt?.millisecondsSinceEpoch ?? now,
        'updated_at': conversation.updatedAt?.millisecondsSinceEpoch ?? now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> rename(String id, String title) async {
    final db = await AppDatabase.instance;
    await db.update(
      'conversations',
      {
        'title': title,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> touch(String id) async {
    final db = await AppDatabase.instance;
    await db.update(
      'conversations',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.instance;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'conversation_id = ?', whereArgs: [id]);
      await txn.delete('conversations', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<ConversationSummary>> summaries({
    String? search,
    int limit = 200,
  }) async {
    final db = await AppDatabase.instance;
    final where = <String>[];
    final args = <Object?>[];
    if (search != null && search.trim().isNotEmpty) {
      where.add('(c.title LIKE ? OR EXISTS '
          '(SELECT 1 FROM messages m2 WHERE m2.conversation_id = c.id '
          'AND m2.content LIKE ?))');
      final like = '%${search.trim()}%';
      args.addAll([like, like]);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT c.id, c.title, c.model, c.updated_at,
             COALESCE(p.name, '') AS provider_name,
             (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id) AS message_count
      FROM conversations c
      LEFT JOIN providers p ON p.id = c.provider_id
      $whereSql
      ORDER BY c.updated_at DESC
      LIMIT ?
    ''', [...args, limit]);
    return rows.map((r) => ConversationSummary(
          id: r['id'] as String,
          title: r['title'] as String,
          providerName: (r['provider_name'] ?? '') as String,
          model: (r['model'] ?? '') as String,
          updatedAt: r['updated_at'] != null
              ? DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int)
              : null,
          messageCount: (r['message_count'] as int? ?? 0),
        )).toList();
  }

  Future<void> clearAll() async {
    final db = await AppDatabase.instance;
    await db.transaction((txn) async {
      await txn.delete('messages');
      await txn.delete('conversations');
    });
  }

  // ---- Messages ----------------------------------------------------------

  Future<void> insertMessage(String conversationId, ChatMessage message) async {
    final db = await AppDatabase.instance;
    final maxRow = await db.rawQuery(
        'SELECT COALESCE(MAX(seq), 0) AS mx FROM messages WHERE conversation_id = ?',
        [conversationId]);
    final seq = ((maxRow.first['mx'] as int? ?? 0)) + 1;
    await db.insert('messages', {
      'id': message.id,
      'conversation_id': conversationId,
      'role': message.role.wireName,
      'seq': seq,
      'content': message.content,
      'is_error': message.error ? 1 : 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<ChatMessage>> messagesOf(String conversationId,
      {int offset = 0, int limit = 100000}) async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'seq ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => ChatMessage(
          id: r['id'] as String,
          role: ChatMessageRoleX.fromWire(r['role'] as String?),
          content: (r['content'] ?? '') as String,
          error: (r['is_error'] as int? ?? 0) == 1,
        )).toList();
  }

  Future<void> updateMessageContent(String conversationId, String messageId,
      String content) async {
    final db = await AppDatabase.instance;
    await db.update('messages', {'content': content},
        where: 'id = ?', whereArgs: [messageId]);
    await touch(conversationId);
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    final db = await AppDatabase.instance;
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
    // Re-sequence for display ordering.
    await _resequence(db, conversationId);
    await touch(conversationId);
  }

  Future<void> _resequence(Database db, String conversationId) async {
    final rows = await db.query('messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'seq ASC');
    await db.transaction((txn) async {
      for (var i = 0; i < rows.length; i++) {
        await txn.update('messages', {'seq': i + 1},
            where: 'id = ?', whereArgs: [rows[i]['id']]);
      }
    });
  }

  Future<void> replaceMessages(String conversationId,
      List<ChatMessage> messages) async {
    final db = await AppDatabase.instance;
    await db.delete('messages',
        where: 'conversation_id = ?', whereArgs: [conversationId]);
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      await db.insert('messages', {
        'id': m.id,
        'conversation_id': conversationId,
        'role': m.role.wireName,
        'seq': i + 1,
        'content': m.content,
        'is_error': m.error ? 1 : 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
    await touch(conversationId);
  }
}
