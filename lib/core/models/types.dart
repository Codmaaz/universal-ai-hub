/// Shared model types. Pure Dart (no Flutter imports) so they can be unit
/// tested and reused across feature boundaries.
library;

/// Kinds of adapters the application knows how to talk to.
enum ProviderType {
  openaiCompatible('OpenAI Compatible'),
  anthropic('Anthropic'),
  gemini('Gemini'),
  custom('Custom API'),
  universalHttp('Universal HTTP API');

  const ProviderType(this.label);
  final String label;

  static ProviderType fromStorage(String? value) {
    return ProviderType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => ProviderType.custom,
    );
  }
}


/// Operations a user can expose from any HTTP API. The universal connector
/// stores these flags in the provider JSON, so adding capabilities does not
/// require a database migration.
enum AiCapability {
  chat('Chat'),
  imageGeneration('Image generation'),
  videoGeneration('Video generation'),
  audioGeneration('Audio generation'),
  speechToText('Speech to text'),
  textToSpeech('Text to speech'),
  embeddings('Embeddings'),
  moderation('Moderation'),
  files('Files'),
  custom('Custom');

  const AiCapability(this.label);
  final String label;

  static AiCapability? fromStorage(String? value) {
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }
}

/// How the API secret is attached to a request.
enum AuthMethod {
  bearerToken('Bearer Token', 'Authorization: Bearer <api_key>'),
  apiKeyHeader('API Key Header', 'x-api-key: <api_key>'),
  customHeader('Custom Header', 'Arbitrary header name + value'),
  queryParam('Query Parameter', 'Adds ?key=<api_key> to the URL');

  const AuthMethod(this.label, this.description);
  final String label;
  final String description;

  static AuthMethod fromStorage(String? value) {
    return AuthMethod.values.firstWhere(
      (a) => a.name == value,
      orElse: () => AuthMethod.bearerToken,
    );
  }
}

/// Role of a message inside a chat conversation.
enum ChatMessageRole { system, user, assistant }

extension ChatMessageRoleX on ChatMessageRole {
  String get wireName {
    switch (this) {
      case ChatMessageRole.system:
        return 'system';
      case ChatMessageRole.user:
        return 'user';
      case ChatMessageRole.assistant:
        return 'assistant';
    }
  }

  static ChatMessageRole fromWire(String? value) {
    switch (value) {
      case 'system':
        return ChatMessageRole.system;
      case 'assistant':
        return ChatMessageRole.assistant;
      default:
        return ChatMessageRole.user;
    }
  }
}

/// Immutable record of a single chat message.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.error = false,
  });

  final String id;
  final ChatMessageRole role;
  final String content;

  /// True when [content] represents an error diagnostic rather than model text.
  final bool error;

  ChatMessage copyWith({String? content, bool? error}) => ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        error: error ?? this.error,
      );
}
