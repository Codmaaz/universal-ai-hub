/// A reusable system prompt that can be attached to a chat.
class SystemPrompt {
  const SystemPrompt({
    required this.id,
    required this.title,
    required this.content,
    this.isFavorite = false,
    this.isBuiltIn = false,
  });

  final String id;
  final String title;
  final String content;
  final bool isFavorite;
  final bool isBuiltIn;

  SystemPrompt copyWith({
    String? title,
    String? content,
    bool? isFavorite,
  }) =>
      SystemPrompt(
        id: id,
        title: title ?? this.title,
        content: content ?? this.content,
        isFavorite: isFavorite ?? this.isFavorite,
        isBuiltIn: isBuiltIn,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'isFavorite': isFavorite,
        'isBuiltIn': isBuiltIn,
      };

  static SystemPrompt fromJson(Map<String, dynamic> json) => SystemPrompt(
        id: json['id'] as String,
        title: (json['title'] ?? '') as String,
        content: (json['content'] ?? '') as String,
        isFavorite: (json['isFavorite'] as bool?) ?? false,
        isBuiltIn: (json['isBuiltIn'] as bool?) ?? false,
      );
}

/// Built-in prompt library seeded on first launch.
abstract final class BuiltinPrompts {
  static List<SystemPrompt> all() {
    const defs = <(String, String)>[
      (
        'General Assistant',
        'You are a helpful, friendly and knowledgeable assistant. '
            'Answer clearly and concisely, and ask for clarification when needed.',
      ),
      (
        'Coding Assistant',
        'You are an expert software engineer. Write clean, well-documented, '
            'efficient code. Explain your approach briefly and point out edge '
            'cases. When you show code, use fenced code blocks with the '
            'language name.',
      ),
      (
        'Translator',
        'You are a professional translator. Translate the user\'s text '
            'accurately while preserving tone and meaning. If the target '
            'language is unclear, ask which language they want.',
      ),
      (
        'Creative Writer',
        'You are a creative writing partner. Help craft vivid, original '
            'stories, poems and scripts. Be imaginative and offer constructive '
            'revisions.',
      ),
      (
        'Teacher',
        'You are a patient teacher. Explain concepts step by step using '
            'simple analogies, and check understanding by asking short '
            'questions. Adapt to the learner\'s level.',
      ),
      (
        'Debugging Assistant',
        'You are a debugging expert. Analyze error messages carefully, '
            'propose the most likely root cause first, then provide a fix and '
            'a way to verify it. Ask for logs only when needed.',
      ),
    ];
    return [
      for (final (i, d) in defs.indexed)
        SystemPrompt(
          id: 'builtin_prompt_$i',
          title: d.$1,
          content: d.$2,
          isBuiltIn: true,
        ),
    ];
  }
}
