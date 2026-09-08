/// A fully sanitized record of a single API request/response pair shown in
/// the developer request inspector. Secrets are removed before this is built.
class ApiRequestRecord {
  const ApiRequestRecord({
    required this.method,
    required this.url,
    required this.headers,
    this.requestBody,
    this.responseStatus,
    this.responseHeaders,
    this.responseBody,
    this.durationMs,
  });

  final String method;
  final String url;

  /// Maps of header name -> header value, always masked.
  final Map<String, String> headers;

  /// Masked request body (or null when there was none).
  final String? requestBody;

  final int? responseStatus;
  final Map<String, String>? responseHeaders;

  /// Truncated + masked response body.
  final String? responseBody;
  final int? durationMs;

  /// Compiles a human readable inspector dump. Safe to copy/export: every
  /// value has already been masked upstream.
  String toText() {
    final b = StringBuffer();
    b.writeln('$method $url');
    b.writeln();
    b.writeln('-- Request headers --');
    headers.forEach((k, v) => b.writeln('$k: $v'));
    if (requestBody != null && requestBody!.isNotEmpty) {
      b.writeln();
      b.writeln('-- Request body --');
      b.writeln(requestBody);
    }
    b.writeln();
    b.writeln('-- Response --');
    b.writeln('Status: ${responseStatus ?? '—'} '
        '${durationMs != null ? '(${durationMs}ms)' : ''}');
    responseHeaders?.forEach((k, v) => b.writeln('$k: $v'));
    if (responseBody != null && responseBody!.isNotEmpty) {
      b.writeln();
      b.writeln(responseBody);
    }
    return b.toString();
  }
}
