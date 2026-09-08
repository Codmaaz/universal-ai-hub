
/// Helpers for building safe, well-formed request URLs from user supplied
/// base URLs, and for validating them.
///
/// Guarantees:
///  * never produces `//` between path segments,
///  * keeps whatever meaning the user gave (scheme, host, port and any
///    `/v1`, `/v2`, ... version path the user typed),
///  * strips any accidental trailing slash from a base URL before joining.
abstract final class UrlBuilder {
  static final RegExp _httpScheme = RegExp(r'^https?://', caseSensitive: false);

  /// Adds the http scheme when the user forgot it (dev convenience), then
  /// validates the result. Never rewrites an existing scheme.
  static String normalizeInput(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;
    if (!_httpScheme.hasMatch(value)) {
      value = 'https://$value';
    }
    return value;
  }

  /// Structural validation (no network call). Returns null when valid,
  /// otherwise a user readable explanation.
  static String? validate(String raw) {
    final trimmed = raw.trim();
    // A scheme the user typed explicitly must be http(s), never ftp://…
    if (RegExp(r'^[a-z][a-z0-9+.\-]*://', caseSensitive: false)
            .hasMatch(trimmed) &&
        !_httpScheme.hasMatch(trimmed)) {
      return 'Only http:// and https:// URLs are supported.';
    }
    final value = normalizeInput(raw);
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return 'This does not look like a valid URL.';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Only http:// and https:// URLs are supported.';
    }
    if (uri.host.isEmpty) {
      return 'The URL is missing a host name.';
    }
    if (uri.host.contains(' ') || uri.host.contains('%')) {
      return 'The URL host looks invalid.';
    }
    return null;
  }

  /// Joins a base URL and a path while removing duplicated slashes.
  ///
  /// ```
  /// join('https://x.com/v1', '/chat/completions')  // https://x.com/v1/chat/completions
  /// join('https://x.com/v1/', '/chat/completions') // https://x.com/v1/chat/completions
  /// join('https://x.com', 'v1/chat/completions')   // https://x.com/v1/chat/completions
  /// ```
  static String join(String baseUrl, String path) {
    final base = _stripTrailingSlash(baseUrl.trim());
    final p = path.trim();
    if (p.isEmpty) return base;
    var normalizedPath = p;
    while (normalizedPath.startsWith('/')) {
      normalizedPath = normalizedPath.substring(1);
    }
    return '$base/$normalizedPath';
  }

  static String _stripTrailingSlash(String value) {
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Preserves the user's existing trailing slash when their path ends in one
  /// (some endpoints genuinely end with a slash).
  static String _keepSingleTrailingSlash(String value) {
    if (value.isEmpty || value == '/') return value;
    final hasTrailing = value.endsWith('/');
    value = _stripTrailingSlash(value);
    if (hasTrailing) value = '$value/';
    return value;
  }

  /// True when a supplied base URL already contains a version-like path
  /// segment such as `/v1` or `/api/v2`. Used by the custom adapter.
  static bool containsVersionSegment(String baseUrl) {
    return RegExp(r'/(v\d+|api/|api$)', caseSensitive: false)
        .hasMatch(baseUrl);
  }

  /// Builds the final endpoint URI from components supplied by the UI.
  static String buildEndpoint({
    required String baseUrl,
    String? path,
    bool ensureTrailingSlash = false,
  }) {
    var base = _stripTrailingSlash(normalizeInput(baseUrl));
    final p = (path ?? '').trim();
    var result = base;
    if (p.isNotEmpty) {
      result = join(base, p);
    }
    if (ensureTrailingSlash && !result.endsWith('/')) {
      result = '$result/';
    }
    return result;
  }
}
