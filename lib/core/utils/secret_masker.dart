import 'dart:convert';

/// Defensive secret handling helpers.
///
/// Everything that could contain an API key passes through these functions
/// before it is allowed into logs, exports or error details.
abstract final class SecretMasker {
  /// Masks [value] keeping at most [keepTail] trailing characters visible.
  static String mask(String value, {int keepTail = 4, bool reveal = false}) {
    if (reveal) return value;
    if (value.isEmpty) return value;
    if (value.length <= keepTail + 1) return '********';
    return '${'*' * (value.length - keepTail)}${value.substring(value.length - keepTail)}';
  }

  /// Masks secret-looking values found in free-form text:
  ///   - `Authorization: Bearer sk-abc...`
  ///   - `"x-api-key": "secret..."`
  ///   - the API key when it appears verbatim in a body / query string.
  static String scrubSecrets(String input, {String? knownSecret}) {
    if (input.isEmpty) return input;
    var out = input;
    if (knownSecret != null && knownSecret.isNotEmpty) {
      // Protect against accidental inclusion of a plaintext key.
      out = out.replaceAll(knownSecret, mask(knownSecret));
    }
    out = out.replaceAllMapped(
      RegExp(
        r'''(authorization\s*:\s*(?:bearer\s+)?|x-api-key\s*:\s*|api[_-]?key\s*[:=\s]*)\s*([A-Za-z0-9_.-]{8,})''',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}${mask(m.group(2) ?? '')}',
    );
    // Query string secrets, e.g. ?key=sk-abc or &api_key=xyz
    out = out.replaceAllMapped(
      RegExp(
        r'''((?:\?|&)(?:key|api_key|apikey|token|access_token)=)([^&\s]+)''',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}${mask(m.group(2) ?? '')}',
    );
    // Common prefixes in JSON bodies: "sk-...", "Bearer ..."
    out = out.replaceAllMapped(
      RegExp(r'sk-[A-Za-z0-9_\-]{6,}'),
      (m) => mask(m.group(0) ?? '', keepTail: 6),
    );
    return out;
  }

  /// Removes every secret that could exist in an [encodedJson] request body.
  static String scrubJsonBody(String encodedJson, {String? knownSecret}) {
    try {
      final decoded = jsonDecode(encodedJson);
      final encoded = jsonEncode(_redactMap(decoded, knownSecret: knownSecret));
      // Second pass: mask any sk-… style tokens that appear in values.
      return scrubSecrets(encoded, knownSecret: knownSecret);
    } catch (_) {
      return scrubSecrets(encodedJson, knownSecret: knownSecret);
    }
  }

  static Object? _redactMap(Object? node, {String? knownSecret}) {
    if (node is Map) {
      return node.map((key, value) {
        final k = key.toString().toLowerCase();
        if (k.contains('api') && k.contains('key') ||
            k == 'authorization' ||
            k.contains('token') ||
            k == 'x-api-key') {
          return MapEntry(key, mask(value.toString()));
        }
        return MapEntry(key, _redactMap(value, knownSecret: knownSecret));
      });
    }
    if (node is List) {
      return node.map((e) => _redactMap(e, knownSecret: knownSecret)).toList();
    }
    if (node is String && knownSecret != null && node.contains(knownSecret)) {
      return scrubSecrets(node, knownSecret: knownSecret);
    }
    return node;
  }

  static const String maskedHeaderPlaceholder = '**************';
}
