/// A chat conversation stored locally. Never contains API keys.
class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.title,
    required this.providerId,
    this.model = '',
    this.systemPrompt = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String providerId;
  final String model;
  final String systemPrompt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ChatConversation copyWith({
    String? title,
    String? providerId,
    String? model,
    String? systemPrompt,
    DateTime? updatedAt,
  }) =>
      ChatConversation(
        id: id,
        title: title ?? this.title,
        providerId: providerId ?? this.providerId,
        model: model ?? this.model,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Lightweight row used to render conversation list items.
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.providerName,
    required this.model,
    required this.updatedAt,
    required this.messageCount,
  });

  final String id;
  final String title;
  final String providerName;
  final String model;
  final DateTime? updatedAt;
  final int messageCount;
}
