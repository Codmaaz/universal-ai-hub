import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ai_hub/core/models/provider.dart';
import 'package:universal_ai_hub/core/models/types.dart';
import 'package:universal_ai_hub/core/network/auth_headers.dart';

AIProvider providerFor(AuthMethod method,
    {String name = '', String value = '', List<HttpHeader> extra = const []}) {
  return AIProvider(
    id: 'p1',
    name: 'Test',
    type: ProviderType.openaiCompatible,
    baseUrl: 'https://example.com/v1',
    authMethod: method,
    customAuthHeaderName: name,
    customAuthHeaderValue: value,
    customHeaders: extra,
  );
}

void main() {
  group('AuthHeaderBuilder', () {
    test('bearer token auth sets Authorization header', () {
      final deco = AuthHeaderBuilder.build(
          provider: providerFor(AuthMethod.bearerToken), apiKey: 'KEY123');
      expect(deco.headers['Authorization'], 'Bearer KEY123');
      expect(deco.queryParameters, isEmpty);
    });

    test('api key header auth sets x-api-key', () {
      final deco = AuthHeaderBuilder.build(
          provider: providerFor(AuthMethod.apiKeyHeader), apiKey: 'KEY123');
      expect(deco.headers['x-api-key'], 'KEY123');
    });

    test('custom header uses user header name and template', () {
      final deco = AuthHeaderBuilder.build(
          provider: providerFor(AuthMethod.customHeader,
              name: 'X-Goog-Api-Key', value: 'Bearer {{API_KEY}}'),
          apiKey: 'SECRET');
      expect(deco.headers, {'X-Goog-Api-Key': 'Bearer SECRET'});
    });

    test('query param auth never puts the key in headers', () {
      final deco = AuthHeaderBuilder.build(
          provider: providerFor(AuthMethod.queryParam, name: 'key'),
          apiKey: 'SECRET');
      expect(deco.headers, isEmpty);
      expect(deco.queryParameters, {'key': 'SECRET'});
    });

    test('query param auth defaults name to api_key', () {
      final deco = AuthHeaderBuilder.build(
          provider: providerFor(AuthMethod.queryParam), apiKey: 'SECRET');
      expect(deco.queryParameters, {'api_key': 'SECRET'});
    });

    test('resolves {{API_KEY}} placeholder inside custom headers', () {
      final deco = AuthHeaderBuilder.build(
        provider: providerFor(AuthMethod.bearerToken,
            extra: const [
              HttpHeader(name: 'X-Tenant', value: 'acme'),
              HttpHeader(name: 'X-Custom-Key', value: '{{API_KEY}}'),
            ]),
        apiKey: 'MYKEY',
      );
      expect(deco.headers['X-Tenant'], 'acme');
      expect(deco.headers['X-Custom-Key'], 'MYKEY');
      expect(deco.headers['Authorization'], 'Bearer MYKEY');
    });
  });
}
