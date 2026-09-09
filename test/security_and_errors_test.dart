import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ai_hub/core/models/provider.dart';
import 'package:universal_ai_hub/core/models/types.dart';
import 'package:universal_ai_hub/core/network/api_exception.dart';
import 'package:universal_ai_hub/core/utils/export_formatters.dart';
import 'package:universal_ai_hub/core/models/conversation.dart';

AIProvider sampleProvider() => const AIProvider(
      id: 'prov1',
      name: 'Test provider',
      type: ProviderType.openaiCompatible,
      baseUrl: 'https://api.example.com/v1',
      authMethod: AuthMethod.bearerToken,
      model: 'test-model',
    );

void main() {
  group('Provider JSON never carries secrets', () {
    test('toJson has no api key members', () {
      final json = sampleProvider().toJson();
      expect(json.containsKey('apiKey'), isFalse);
      expect(json.containsKey('api_key'), isFalse);
      expect(json.containsKey('secret'), isFalse);
      expect(json['baseUrl'], 'https://api.example.com/v1');
    });
  });

  group('Conversation exports are plain text only', () {
    test('json export shape', () {
      final conv = ChatConversation(
          id: 'c1', title: 'Test chat', providerId: 'p', model: 'm');
      final messages = const [
        ChatMessage(
            id: 'm1',
            role: ChatMessageRole.user,
            content: 'hi'),
        ChatMessage(
            id: 'm2',
            role: ChatMessageRole.assistant,
            content: 'hello'),
      ];
      final json = ExportFormatters.conversationToJson(conv, messages);
      expect(json.contains('"role":"user"'), isTrue);
      expect(json.contains('"role":"assistant"'), isTrue);
      expect(json.contains('apiKey'), isFalse);
      expect(json.contains('secret'), isFalse);
    });

    test('markdown/text exports contain no key material', () {
      final conv = ChatConversation(
          id: 'c1', title: 'Test chat', providerId: 'p', model: 'm');
      const messages = [
        ChatMessage(
            id: 'm1', role: ChatMessageRole.user, content: 'hi'),
      ];
      for (final out in [
        ExportFormatters.conversationToMarkdown(conv, messages),
        ExportFormatters.conversationToText(conv, messages),
      ]) {
        expect(out, isNot(contains('apiKey')));
        expect(out, isNot(contains('Bearer ')));
      }
    });
  });

  group('ApiException classification + sanitization', () {
    DioException dioError(int status, Map<String, dynamic> body) {
      final opts = RequestOptions(path: 'https://api.example.com/v1/chat/completions');
      return DioException(
        requestOptions: opts,
        response: Response(
          requestOptions: opts,
          statusCode: status,
          data: body,
        ),
        type: DioExceptionType.badResponse,
      );
    }

    test('401 becomes invalidApiKey with friendly tip', () {
      final e = ApiException.fromDio(
          dioError(401, {'error': {'message': 'Invalid API key'}}),
          providerName: 'X');
      expect(e.kind, ApiErrorKind.invalidApiKey);
      expect(e.httpStatus, 401);
      expect(e.tip, isNotNull);
    });

    test('429 is rate limiting, 500 is server error', () {
      expect(ApiException.fromDio(dioError(429, {})).kind,
          ApiErrorKind.rateLimited);
      expect(ApiException.fromDio(dioError(500, {})).kind,
          ApiErrorKind.serverError);
    });

    test('sanitizes keys found in response body details', () {
      const sk = 'sk-abcdefghijklmnopqrstuvwx';
      final e = ApiException.fromDio(dioError(400, {'error': {'message': sk}}));
      expect(e.sanitizedBody, isNotNull);
      expect(e.sanitizedBody!.contains(sk), isFalse);
      expect(e.message, contains('provider'));
    });
  });
}
