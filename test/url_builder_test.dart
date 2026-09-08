import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ai_hub/core/utils/url_builder.dart';

void main() {
  group('UrlBuilder.join', () {
    test('appends path to plain base', () {
      expect(UrlBuilder.join('https://example.com', '/chat/completions'),
          'https://example.com/chat/completions');
    });

    test('strips trailing slash from base', () {
      expect(UrlBuilder.join('https://example.com/', '/chat/completions'),
          'https://example.com/chat/completions');
      expect(UrlBuilder.join('https://example.com/v1/', '/chat/completions'),
          'https://example.com/v1/chat/completions');
    });

    test('never creates duplicate slashes between base and path', () {
      expect(UrlBuilder.join('https://example.com/v1//', '///chat'),
          'https://example.com/v1/chat');
      expect(UrlBuilder.join('https://example.com/v1/', '/chat/completions'),
          'https://example.com/v1/chat/completions');
      // Scheme's own '//' is untouched.
      final withHost = UrlBuilder.join('https://example.com/', '/a');
      expect(withHost.startsWith('https://example.com/a'), isTrue);
    });

    test('keeps version segments intact', () {
      expect(UrlBuilder.join('https://example.com/v1', '/chat/completions'),
          'https://example.com/v1/chat/completions');
    });

    test('path without leading slash also works', () {
      expect(UrlBuilder.join('https://x.com/v1', 'chat/completions'),
          'https://x.com/v1/chat/completions');
    });

    test('empty path returns base', () {
      expect(UrlBuilder.join('https://x.com/v1/', ''), 'https://x.com/v1');
    });
  });

  group('UrlBuilder.validate / normalize', () {
    test('accepts valid https/http hosts', () {
      expect(UrlBuilder.validate('https://api.openai.com/v1'), isNull);
      expect(UrlBuilder.validate('http://10.0.0.2:8080/v1'), isNull);
    });

    test('rejects garbage and non-http schemes', () {
      expect(UrlBuilder.validate('not a url'), isNotNull);
      expect(UrlBuilder.validate('ftp://example.com'), isNotNull);
      expect(UrlBuilder.validate('javascript:alert(1)'), isNotNull);
    });

    test('adds https when scheme missing', () {
      expect(UrlBuilder.normalizeInput('api.example.com/v1'),
          'https://api.example.com/v1');
    });
  });

  group('buildEndpoint', () {
    test('adds trailing slash only when explicitly requested', () {
      expect(UrlBuilder.buildEndpoint(baseUrl: 'https://x.com/v1', path: 'p'),
          'https://x.com/v1/p');
      expect(
          UrlBuilder.buildEndpoint(
              baseUrl: 'https://x.com/v1/', path: 'p', ensureTrailingSlash: true),
          'https://x.com/v1/p/');
    });
  });
}
