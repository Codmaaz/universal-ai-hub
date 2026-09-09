import 'dart:convert';

import '../models/conversation.dart';
import '../models/types.dart';

/// Pure formatters for conversation exports (TXT / Markdown / JSON).
/// Safe by construction: messages contain text only — never keys.
abstract final class ExportFormatters {
  static String conversationToText(ChatConversation conv,
      List<ChatMessage> messages) {
    final b = StringBuffer()
      ..writeln(conv.title)
      ..writeln('=' * conv.title.length)
      ..writeln('Exported ${DateTime.now().toIso8601String()}');
    if (conv.systemPrompt.isNotEmpty) {
      b.writeln('System prompt: ${conv.systemPrompt}');
    }
    b.writeln('Model: ${conv.model}');
    b.writeln();
    for (final m in messages) {
      if (m.content.isEmpty) continue;
      final who = m.role == ChatMessageRole.user
          ? 'You'
          : m.role == ChatMessageRole.assistant
              ? 'Assistant'
              : 'System';
      b.writeln('[$who]');
      b.writeln(m.content);
      b.writeln();
    }
    return b.toString().trimRight();
  }

  static String conversationToMarkdown(ChatConversation conv,
      List<ChatMessage> messages) {
    final b = StringBuffer()..writeln('# ${conv.title}');
    if (conv.model.isNotEmpty) {
      b.writeln();
      b.writeln('_Model: ${conv.model}_');
    }
    b.writeln();
    for (final m in messages) {
      if (m.content.isEmpty) continue;
      final who = m.role == ChatMessageRole.user
          ? 'You'
          : m.role == ChatMessageRole.assistant
              ? 'Assistant'
              : 'System';
      b.writeln('### $who');
      b.writeln();
      b.writeln(m.content);
      b.writeln();
    }
    return b.toString().trimRight();
  }

  static String conversationToJson(ChatConversation conv,
      List<ChatMessage> messages) {
    final export = <String, dynamic>{
      'format': 'universal_ai_hub_chat',
      'version': 1,
      'conversation': {
        'id': conv.id,
        'title': conv.title,
        'model': conv.model,
        'createdAt': conv.createdAt?.toIso8601String(),
        'updatedAt': conv.updatedAt?.toIso8601String(),
      },
      'messages': [
        for (final m in messages)
          if (m.content.isNotEmpty)
            {
              'role': m.role.wireName,
              'content': m.content,
            }
      ],
    };
    return jsonEncode(export);
  }
}
