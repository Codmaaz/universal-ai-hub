import '../models/provider.dart';
import '../models/types.dart';

/// Resolved auth decoration for one request.
class AuthDecoration {
  const AuthDecoration({required this.headers, this.queryParameters = const {}});

  final Map<String, String> headers;
  final Map<String, String> queryParameters;
}

/// Builds headers/query parameters for a provider configuration using the
/// secret fetched from secure storage. The [apiKey] is only held transiently
/// in memory by the caller.
abstract final class AuthHeaderBuilder {
  static const String keyPlaceholder = '{{API_KEY}}';

  /// Applies a single header template, resolving `{{API_KEY}}` when present.
  static String resolveTemplate(String value, String apiKey) =>
      value.replaceAll(keyPlaceholder, apiKey);

  static AuthDecoration build({
    required AIProvider provider,
    required String apiKey,
  }) {
    final headers = <String, String>{};

    // 1) Custom headers first (they may include the {{API_KEY}} placeholder).
    for (final h in provider.customHeaders) {
      if (h.name.trim().isNotEmpty) {
        headers[h.name.trim()] = resolveTemplate(h.value, apiKey);
      }
    }

    // 2) The active auth method.
    switch (provider.authMethod) {
      case AuthMethod.bearerToken:
        headers['Authorization'] = 'Bearer $apiKey';
        return AuthDecoration(headers: headers);
      case AuthMethod.apiKeyHeader:
        headers['x-api-key'] = apiKey;
        return AuthDecoration(headers: headers);
      case AuthMethod.customHeader:
        final name = provider.customAuthHeaderName.trim();
        if (name.isEmpty) {
          throw ArgumentError(
              'Custom authentication header needs a header name.');
        }
        headers[name] =
            resolveTemplate(provider.customAuthHeaderValue, apiKey);
        return AuthDecoration(headers: headers);
      case AuthMethod.queryParam:
        // Explicitly configured query-parameter auth. The key travels in the
        // URL query string because the user asked for that behaviour.
        final name = provider.customAuthHeaderName.trim().isEmpty
            ? 'api_key'
            : provider.customAuthHeaderName.trim();
        return AuthDecoration(
          headers: headers,
          queryParameters: {name: apiKey},
        );
    }
  }
}
