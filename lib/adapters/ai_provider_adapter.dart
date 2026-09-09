import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/models/api_request_record.dart';
import '../core/models/generation_settings.dart';
import '../core/models/provider.dart';
import '../core/models/types.dart';
import '../core/network/auth_headers.dart';
import '../core/utils/secret_masker.dart';

/// Immutable description of one AI turn request.
class AiTurnRequest {
  const AiTurnRequest({
    required this.provider,
    required this.apiKey,
    required this.messages,
    required this.model,
    this.systemPrompt = '',
    this.settings = const GenerationSettings(),
    this.streaming = true,
    this.cancelToken,
    this.onDelta,
    this.inspectorEnabled = false,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 120),
  });

  final AIProvider provider;
  final String apiKey;
  final List<ChatMessage> messages;
  final String model;
  final String systemPrompt;
  final GenerationSettings settings;
  final bool streaming;
  final CancelToken? cancelToken;
  final void Function(String partialText)? onDelta;
  final bool inspectorEnabled;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  /// Messages restricted to roles that adapters may send.
  List<ChatMessage> get wireMessages =>
      messages.where((m) => m.role != ChatMessageRole.system).toList();
}

/// Result of one AI turn (non-streamed reply or final assembled stream).
class AiTurnResult {
  const AiTurnResult({
    required this.content,
    this.requestRecord,
    this.responseModel,
    this.providerName,
  });

  final String content;

  /// Present only when the developer request inspector is enabled.
  final ApiRequestRecord? requestRecord;
  final String? responseModel;
  final String? providerName;
}

/// Outcome of a safe "Test Connection" call.
class ConnectionTestResult {
  const ConnectionTestResult({
    required this.ok,
    required this.summary,
    this.detail = '',
    this.durationMs,
    this.requestRecord,
  });

  final bool ok;
  final String summary;

  /// Human readable description of exactly what request was sent.
  final String detail;
  final int? durationMs;
  final ApiRequestRecord? requestRecord;
}

/// All provider adapters implement this contract. The chat UI only knows this
/// interface — every provider request/response conversion lives behind it.
abstract interface class AIProviderAdapter {
  ProviderType get type;

  String get label;

  /// Features the adapter really supports (used to gate the UI).
  ProviderCapabilities get capabilities;

  /// Whether this adapter can talk to the given [provider] config at all
  /// (e.g. minimum base URL sanity checks) — without network calls.
  String? validateConfiguration(AIProvider provider);

  /// Sends one turn and resolves with the assistant text. When
  /// [request.streaming] is true, partial text is delivered through
  /// [request.onDelta].
  Future<AiTurnResult> send(AiTurnRequest request);

  /// Safe connection probe. Returns [ConnectionTestResult].
  Future<ConnectionTestResult> testConnection(AiTurnRequest request);

  /// Lists available model names when supported, otherwise throws
  /// [UnsupportedError]. UI must check capabilities first.
  Future<List<String>> listModels({
    required AIProvider provider,
    required String apiKey,
  });
}

/// Shared helpers every adapter uses (URL resolution, header auth wiring,
/// inspector records). Kept free of provider-specific formats.
abstract class AdapterSupport {
  /// Resolves the final full request URL for a provider configuration,
  /// guarding against duplicate slashes and double suffixes.
  static String resolveUrl(AIProvider provider, {String? explicitPath}) {
    var base = provider.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final override = (explicitPath ?? provider.endpoint).trim();

    if (override.isNotEmpty) {
      if (override.startsWith('http://') || override.startsWith('https://')) {
        return override;
      }
      return _join(base, override);
    }

    final def = provider.defaultEndpoint;
    if (def.isEmpty) return base;
    // Do not double-append when the base URL already ends with the endpoint.
    if (base.endsWith(def)) return base;
    return _join(base, def);
  }

  static String _join(String base, String path) {
    var p = path;
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    return '$base/$p';
  }

  /// Builds the auth + custom headers and applies them to [options].
  static void applyAuth(RequestOptions options, AIProvider provider, String apiKey) {
    final decoration = AuthHeaderBuilder.build(
        provider: provider, apiKey: apiKey);
    decoration.headers.forEach((k, v) => options.headers[k] = v);
    if (decoration.queryParameters.isNotEmpty) {
      final query = Map<String, dynamic>.from(options.queryParameters);
      decoration.queryParameters.forEach((k, v) => query[k] = v);
      options.queryParameters = query;
    }
  }

  /// Creates an [ApiRequestRecord] for the inspector. All values are masked.
  static ApiRequestRecord buildRecord({
    required RequestOptions options,
    String? requestBody,
    int? status,
    Map<String, String>? responseHeaders,
    String? responseBody,
    int? durationMs,
  }) {
    final maskedHeaders = <String, String>{};
    options.headers.forEach((k, v) {
      final name = k.toString();
      final lower = name.toLowerCase();
      final value = v.toString();
      final secret = lower == 'authorization' ||
          lower == 'x-api-key' ||
          name.toLowerCase().contains('api') && name.toLowerCase().contains('key') ||
          value.startsWith('Bearer ');
      maskedHeaders[name] =
          secret ? SecretMasker.mask(value) : SecretMasker.scrubSecrets(value);
    });
    // Mask key query params appended by auth.
    final qp = Map<String, dynamic>.from(options.queryParameters);
    qp.forEach((k, v) {
      if (k.toLowerCase().contains('key') ||
          k.toLowerCase().contains('token') ||
          k.toLowerCase().contains('auth')) {
        qp[k] = SecretMasker.mask(v.toString());
      }
    });
    var url = options.uri.toString();
    if (qp.isNotEmpty) {
      final qs = qp.entries.map((e) => '${e.key}=${e.value}').join('&');
      final uri = Uri.parse(url);
      url = uri.replace(query: uri.hasQuery ? '${uri.query}&$qs' : qs).toString();
    }
    url = SecretMasker.scrubSecrets(url);

    final respHeaders = <String, String>{};
    (responseHeaders ?? {}).forEach((k, v) {
      respHeaders[k] = SecretMasker.scrubSecrets(v);
    });

    return ApiRequestRecord(
      method: options.method,
      url: url,
      headers: maskedHeaders,
      requestBody: requestBody == null
          ? null
          : _truncate(SecretMasker.scrubJsonBody(requestBody)),
      responseStatus: status,
      responseHeaders: respHeaders.isEmpty ? null : respHeaders,
      responseBody: responseBody == null || responseBody.isEmpty
          ? null
          : _truncate(SecretMasker.scrubJsonBody(responseBody)),
      durationMs: durationMs,
    );
  }

  /// Extracts an error body even from streaming (ResponseBody) responses.
  static Future<String?> readErrorBody(Object? data) async {
    if (data == null) return null;
    if (data is ResponseBody) {
      try {
        final bytes = <int>[];
        await for (final chunk in data.stream.take(65536)) {
          bytes.addAll(chunk);
        }
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
    return data.toString();
  }

  static String? _truncate(String v, {int max = 4000}) =>
      v.length <= max ? v : '${v.substring(0, max)}\n… (truncated)';
}

/// Decodes a JSON response body of any shape.
dynamic safeDecode(String? body) {
  if (body == null || body.isEmpty) return null;
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}
