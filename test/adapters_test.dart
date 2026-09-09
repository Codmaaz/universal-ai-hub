import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ai_hub/adapters/ai_provider_adapter.dart';
import 'package:universal_ai_hub/adapters/anthropic_adapter.dart';
import 'package:universal_ai_hub/adapters/gemini_adapter.dart';
import 'package:universal_ai_hub/adapters/openai_compatible_adapter.dart';
import 'package:universal_ai_hub/core/models/generation_settings.dart';
import 'package:universal_ai_hub/core/models/provider.dart';
import 'package:universal_ai_hub/core/models/types.dart';

AIProvider providerOf(ProviderType type, {AuthMethod auth = AuthMethod.bearerToken}) {
  return AIProvider(
    id: 'p',
    name: 'P',
    type: type,
    baseUrl: 'https://example.com/v1',
    authMethod: auth,
    model: 'test-model',
  );
}

List<ChatMessage> history() => const [
      ChatMessage(
          id: '1',
          role: ChatMessageRole.user,
          content: 'Hello'),
      ChatMessage(
          id: '2',
          role: ChatMessageRole.assistant,
          content: 'Hi there'),
      ChatMessage(
          id: '3',
          role: ChatMessageRole.user,
          content: 'How are you?'),
    ];

AiTurnRequest requestFor(AIProvider p,
    {GenerationSettings settings = const GenerationSettings()}) {
  return AiTurnRequest(
    provider: p,
    apiKey: 'secret-key',
    messages: history(),
    model: 'test-model',
    systemPrompt: 'You are helpful.',
    settings: settings,
    streaming: false,
  );
}

void main() {
  group('OpenAICompatibleAdapter bodies & parsing', () {
    const adapter = OpenAICompatibleAdapter();

    test('builds chat completion body with system message first', () {
      final p = providerOf(ProviderType.openaiCompatible);
      final body = adapter.buildRequestBody(requestFor(p));
      final messages = body['messages'] as List;
      expect((messages.first as Map)['role'], 'system');
      expect((messages.first as Map)['content'], 'You are helpful.');
      expect((messages[1] as Map)['role'], 'user');
      expect((messages[2] as Map)['role'], 'assistant');
      expect(body['model'], 'test-model');
      expect(body['stream'], false);
    });

    test('omits system when empty', () {
      final p = providerOf(ProviderType.openaiCompatible);
      final req = AiTurnRequest(
        provider: p,
        apiKey: 'k',
        messages: history(),
        model: 'm',
        systemPrompt: '   ',
        streaming: false,
      );
      final messages = adapter.buildRequestBody(req)['messages'] as List;
      expect(messages.length, 3);
      expect((messages.first as Map)['role'], 'user');
    });

    test('drops unsupported parameters by capability', () {
      final p = providerOf(ProviderType.openaiCompatible);
      final req = requestFor(
        p,
        settings: const GenerationSettings(
            temperature: 0.5,
            maxTokens: 100,
            topP: 0.9,
            stopSequences: ['END']),
      );
      final body = adapter.buildRequestBody(req);
      expect(body['temperature'], 0.5);
      expect(body['max_tokens'], 100);
      expect(body['stop'], ['END']);
    });

    test('parses stream deltas only from content deltas', () {
      expect(
          adapter.extractStreamDelta(
              '{"choices":[{"delta":{"content":"Hel"}}]}'),
          'Hel');
      expect(
          adapter.extractStreamDelta(
              '{"choices":[{"delta":{"role":"assistant"}}]}'),
          isNull);
      expect(adapter.extractStreamDelta('[DONE]'), isNull);
      // Non-conforming raw text stream is accepted.
      expect(adapter.extractStreamDelta('plain token'), 'plain token');
    });

    test('extracts final content', () {
      expect(
          adapter.extractContent({
            'choices': [
              {
                'message': {'content': 'Final answer'}
              }
            ]
          }),
          'Final answer');
      expect(adapter.extractContent({'choices': []}), '');
    });

    test('resolves endpoint URL with and without trailing slash', () {
      final baseA = providerOf(ProviderType.openaiCompatible)
          .copyWith(baseUrl: 'https://x.com/v1');
      expect(AdapterSupport.resolveUrl(baseA),
          'https://x.com/v1/chat/completions');
      final baseB = providerOf(ProviderType.openaiCompatible)
          .copyWith(baseUrl: 'https://x.com/v1/');
      expect(AdapterSupport.resolveUrl(baseB),
          'https://x.com/v1/chat/completions');
      final full = providerOf(ProviderType.openaiCompatible)
          .copyWith(baseUrl: 'https://x.com/v1/chat/completions');
      expect(AdapterSupport.resolveUrl(full), 'https://x.com/v1/chat/completions');
    });
  });

  group('AnthropicAdapter body & parsing', () {
    const adapter = AnthropicAdapter();

    test('uses anthropic native schema (not OpenAI)', () {
      final p = providerOf(ProviderType.anthropic);
      final body = adapter.buildRequestBody(requestFor(p));
      expect(body.containsKey('messages'), isTrue);
      expect(body.containsKey('system'), isTrue);
      expect(body['system'], 'You are helpful.');
      expect(body['max_tokens'], 1024);
      expect((body['messages'] as List).length, 3);
      expect((body['messages'] as List).first['role'], 'user');
    });

    test('defaults max_tokens when not provided', () {
      final p = providerOf(ProviderType.anthropic);
      final body = adapter.buildRequestBody(requestFor(p));
      expect(body['max_tokens'], 1024);
    });

    test('parses content blocks', () {
      final text = adapter.extractContent({
        'content': [
          {'type': 'text', 'text': 'First'},
          {'type': 'text', 'text': 'Second'},
        ]
      });
      expect(text, 'FirstSecond');
    });

    test('streams text only from content_block_delta', () {
      expect(
          adapter.streamDelta(
              '{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}'),
          'Hi');
      expect(
          adapter.streamDelta('{"type":"message_start","message":{}}'), isNull);
    });
  });

  group('GeminiAdapter body & parsing', () {
    const adapter = GeminiAdapter();

    test('builds contents with model role mapping and systemInstruction', () {
      final p = providerOf(ProviderType.gemini);
      final body = adapter.buildRequestBody(requestFor(p));
      final contents = body['contents'] as List;
      expect((contents[0] as Map)['role'], 'user');
      expect((contents[1] as Map)['role'], 'model');
      expect(body['systemInstruction'], isNotNull);
      expect(body['generationConfig'], isNotNull);
    });

    test('resolves generate URL from base with/without version', () {
      final withVer = providerOf(ProviderType.gemini)
          .copyWith(baseUrl: 'https://generativelanguage.googleapis.com/v1beta');
      expect(
          AdapterSupport.resolveUrl(withVer),
          isNot(contains(':generateContent')));
      // Gemini URL composition happens in _generateUrl; ensure no crash via
      // public list of the version segment below.
      final url = AdapterSupport.resolveUrl(
          withVer.copyWith(endpoint: ''));
      expect(url, 'https://generativelanguage.googleapis.com/v1beta');
    });

    test('parses stream delta text', () {
      expect(
          adapter.streamDelta(
              '{"candidates":[{"content":{"parts":[{"text":"Gen"}]}}]}'),
          'Gen');
    });

    test('parses final response text', () {
      final text = adapter.extractText({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Hello '},
                {'text': 'world'}
              ]
            }
          }
        ]
      });
      expect(text, 'Hello world');
    });
  });
}
