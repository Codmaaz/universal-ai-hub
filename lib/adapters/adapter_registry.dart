import '../core/models/types.dart';
import 'ai_provider_adapter.dart';
import 'anthropic_adapter.dart';
import 'custom_api_adapter.dart';
import 'gemini_adapter.dart';
import 'openai_compatible_adapter.dart';

/// Maps [ProviderType] to its adapter implementation. Adding a new provider
/// family = add an adapter class + register it here. The chat UI never needs
/// to change.
abstract final class AdapterRegistry {
  static final Map<ProviderType, AIProviderAdapter> _adapters = {
    ProviderType.openaiCompatible: const OpenAICompatibleAdapter(),
    ProviderType.anthropic: const AnthropicAdapter(),
    ProviderType.gemini: const GeminiAdapter(),
    ProviderType.custom: const CustomApiAdapter(),
  };

  static AIProviderAdapter forType(ProviderType type) => _adapters[type]!;

  static bool supports(ProviderType type) => _adapters.containsKey(type);

  /// Sensible starting defaults shown by the setup wizard for each type.
  static ({String baseUrl, AuthMethod authMethod, String model}) defaultsFor(
      ProviderType type) {
    switch (type) {
      case ProviderType.openaiCompatible:
        return (
          baseUrl: 'https://api.openai.com/v1',
          authMethod: AuthMethod.bearerToken,
          model: '',
        );
      case ProviderType.anthropic:
        return (
          baseUrl: 'https://api.anthropic.com',
          authMethod: AuthMethod.bearerToken,
          model: 'claude-3-5-sonnet-latest',
        );
      case ProviderType.gemini:
        return (
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          authMethod: AuthMethod.queryParam,
          model: 'gemini-2.5-flash',
        );
      case ProviderType.custom:
        return (
          baseUrl: 'https://example.com/v1',
          authMethod: AuthMethod.bearerToken,
          model: '',
        );
    }
  }

  /// Editable model-name hints shown in the model picker ("enter manually").
  static List<String> modelHints(ProviderType type) {
    switch (type) {
      case ProviderType.openaiCompatible:
        return const [
          'gpt-4o-mini',
          'gpt-4o',
          'gpt-4.1-mini',
          'gpt-4.1',
          'o3-mini',
          'gpt-3.5-turbo',
        ];
      case ProviderType.anthropic:
        return const [
          'claude-3-5-haiku-latest',
          'claude-3-5-sonnet-latest',
          'claude-3-opus-latest',
        ];
      case ProviderType.gemini:
        return const [
          'gemini-2.5-flash',
          'gemini-2.5-pro',
          'gemini-2.0-flash',
        ];
      case ProviderType.custom:
        return const [];
    }
  }

  /// Concise per-field guidance for the provider form.
  static String fieldHelp(ProviderType type, String field) {
    switch (field) {
      case 'name':
        return 'Any name you will recognise later, e.g. “My gateway”.';
      case 'baseUrl':
        switch (type) {
          case ProviderType.gemini:
            return 'Usually https://generativelanguage.googleapis.com/v1beta '
                '(with or without a trailing slash).';
          case ProviderType.anthropic:
            return 'Usually https://api.anthropic.com — the /v1/messages '
                'path is appended automatically.';
          case ProviderType.openaiCompatible:
            return 'The API root, e.g. https://api.openai.com/v1 or your '
                'gateway. Trailing slashes and /v1 paths are handled safely.';
          case ProviderType.custom:
            return 'The URL your API listens on. The endpoint/path from the '
                'Custom section is appended, or use the full URL here.';
        }
      case 'model':
        return 'Exact model identifier the provider accepts. Fetch the list '
            'later or type it manually.';
      case 'streaming':
        return 'Realtime token-by-token answers. Turn off if the endpoint '
            'does not support SSE.';
      default:
        return '';
    }
  }
}
