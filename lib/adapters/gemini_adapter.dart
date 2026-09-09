import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/models/api_request_record.dart';
import '../core/models/provider.dart';
import '../core/models/types.dart';
import '../core/network/api_exception.dart';
import '../core/network/app_dio.dart';
import '../core/network/auth_headers.dart';
import '../core/network/sse_parser.dart';
import 'ai_provider_adapter.dart';

/// Adapter for Google's Gemini generative language API.
///
/// Own request/response shapes — nothing OpenAI-like is assumed:
///   POST /v1beta/models/{model}:generateContent
///   body  { contents: [{role, parts: [{text}]}], systemInstruction, generationConfig }
class GeminiAdapter implements AIProviderAdapter {
  const GeminiAdapter();

  @override
  ProviderType get type => ProviderType.gemini;

  @override
  String get label => 'Google Gemini';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsChat: true,
        supportsStreaming: true,
        supportsModelListing: true,
        supportsSystemPrompt: true,
        supportsTemperature: true,
        supportsMaxTokens: true,
        supportsTopP: true,
        supportsFrequencyPenalty: false,
        supportsPresencePenalty: false,
        supportsStopSequences: false,
        supportsSeed: false,
      );

  @override
  String? validateConfiguration(AIProvider provider) {
    if (provider.baseUrl.trim().isEmpty) return 'Base URL is required.';
    return null;
  }

  /// Resolves the full `:generateContent` URL for [model], tolerating base
  /// URLs with or without the `/v1beta` version segment and full endpoints.
  String _generateUrl(AIProvider provider, String model) {
    var base = provider.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.contains(':generateContent')) return base;
    if (base.endsWith('/models/${Uri.encodeComponent(model)}:generateContent')) {
      return base;
    }
    final versioned = RegExp(r'/v\d+(beta)?$').hasMatch(base);
    if (versioned) return '$base/models/$model:generateContent';
    return '$base/v1beta/models/$model:generateContent';
  }

  String _baseWithoutEndpoint(AIProvider provider) {
    final url = _generateUrl(provider, 'x').replaceFirst(':generateContent', '');
    final idx = url.lastIndexOf('/models');
    return idx > 0 ? url.substring(0, idx) : provider.baseUrl;
  }

  Map<String, String> _headers(AIProvider provider, String apiKey) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (provider.authMethod == AuthMethod.apiKeyHeader ||
        provider.authMethod == AuthMethod.bearerToken) {
      // Gemini accepts x-goog-api-key; some proxies accept bearer.
      if (provider.authMethod == AuthMethod.bearerToken) {
        headers['Authorization'] = 'Bearer $apiKey';
      } else {
        headers['x-goog-api-key'] = apiKey;
      }
    } else if (provider.authMethod == AuthMethod.customHeader) {
      headers[provider.customAuthHeaderName.trim()] =
          AuthHeaderBuilder.resolveTemplate(
              provider.customAuthHeaderValue, apiKey);
    }
    for (final h in provider.customHeaders) {
      if (h.name.trim().isNotEmpty) {
        headers[h.name.trim()] =
            AuthHeaderBuilder.resolveTemplate(h.value, apiKey);
      }
    }
    return headers;
  }

  Map<String, String> _queryFor(AIProvider provider, String apiKey) {
    // Official Gemini docs use ?key=... (query param) as the primary method.
    if (provider.authMethod == AuthMethod.queryParam) {
      final name = provider.customAuthHeaderName.trim().isEmpty
          ? 'key'
          : provider.customAuthHeaderName.trim();
      return {name: apiKey};
    }
    return const {};
  }

  Map<String, dynamic> buildRequestBody(AiTurnRequest request) {
    final s = request.settings.filteredBy(request.provider);
    final parts = <Map<String, dynamic>>[
      for (final m in request.wireMessages)
        {
          'role': m.role == ChatMessageRole.assistant ? 'model' : 'user',
          'parts': [
            {'text': m.content}
          ],
        }
    ];
    return {
      'contents': parts,
      if (request.systemPrompt.trim().isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': request.systemPrompt}
          ]
        },
      'generationConfig': {
        if (s.temperature != null) 'temperature': s.temperature,
        if (s.maxTokens != null) 'maxOutputTokens': s.maxTokens,
        if (s.topP != null) 'topP': s.topP,
      },
    };
  }

  @override
  Future<AiTurnResult> send(AiTurnRequest request) {
    if (request.streaming && request.provider.streamingEnabled) {
      return _sendStreaming(request);
    }
    return _sendSingle(request);
  }

  Future<AiTurnResult> _sendSingle(AiTurnRequest request) async {
    final url = _generateUrl(request.provider, request.model);
    final body = buildRequestBody(request);
    final headers = _headers(request.provider, request.apiKey);
    final query = _queryFor(request.provider, request.apiKey);
    final dio = AppDio.create(
      connectTimeout: request.connectTimeout,
      receiveTimeout: request.receiveTimeout,
    );
    final started = DateTime.now();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        url,
        data: jsonEncode(body),
        queryParameters: query,
        cancelToken: request.cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
        ),
      );
      final text = extractText(response.data);
      final durationMs = DateTime.now().difference(started).inMilliseconds;
      return AiTurnResult(
        content: text,
        providerName: request.provider.name,
        requestRecord: request.inspectorEnabled
            ? _record(request, url, body, query, headers, response.data,
                response.statusCode ?? 200, durationMs)
            : null,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e, providerName: request.provider.name);
    }
  }

  Future<AiTurnResult> _sendStreaming(AiTurnRequest request) async {
    final url = _generateUrl(request.provider, request.model);
    final body = buildRequestBody(request);
    final headers = _headers(request.provider, request.apiKey);
    final query = _queryFor(request.provider, request.apiKey);
    final dio = AppDio.create(
      connectTimeout: request.connectTimeout,
      receiveTimeout: request.receiveTimeout,
    );
    final started = DateTime.now();
    final buffer = StringBuffer();
    try {
      final response = await dio.post<ResponseBody>(
        url,
        data: jsonEncode(body),
        queryParameters: query,
        cancelToken: request.cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
      );
      final decoder = SseDecoder();
      await for (final payload in decoder.decode(response.data!.stream)) {
        final delta = streamDelta(payload);
        if (delta != null && delta.isNotEmpty) {
          buffer.write(delta);
          request.onDelta?.call(delta);
        }
      }
      final content = buffer.toString();
      final durationMs = DateTime.now().difference(started).inMilliseconds;
      return AiTurnResult(
        content: content,
        providerName: request.provider.name,
        requestRecord: request.inspectorEnabled
            ? _record(request, url, body, query, headers, null,
                response.statusCode ?? 200, durationMs,
                assembledContent: content)
            : null,
      );
    } on DioException catch (e) {
      final apiError = ApiException.fromDio(e, providerName: request.provider.name);
      throw apiError.copyWith(partialContent: buffer.toString());
    } catch (e) {
      throw ApiException(
        kind: ApiErrorKind.streamingError,
        message: 'The streaming connection dropped while receiving the response.',
        tip: buffer.isNotEmpty
            ? 'The response received so far was preserved.'
            : 'Try again or disable streaming for this provider.',
        providerName: request.provider.name,
        partialContent: buffer.toString(),
        raw: e,
      );
    }
  }

  String? streamDelta(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) return null;
    final json = safeDecode(trimmed);
    if (json is! Map<String, dynamic>) return null;
    // Candidate content parts may carry text.
    return partsText(json);
  }

  String partsText(Map<String, dynamic> json) {
    final buf = StringBuffer();
    final candidates = json['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      for (final cand in candidates) {
        if (cand is Map<String, dynamic>) {
          buf.write(contentText(cand['content']));
        }
      }
    }
    return buf.toString();
  }

  String contentText(Object? content) {
    if (content is! Map<String, dynamic>) return '';
    final parts = content['parts'];
    if (parts is List) {
      final buf = StringBuffer();
      for (final p in parts) {
        if (p is Map<String, dynamic>) {
          buf.write(p['text'] ?? '');
        }
      }
      return buf.toString();
    }
    return '';
  }

  String extractText(Map<String, dynamic>? json) {
    if (json == null) return '';
    return partsText(json);
  }

  ApiRequestRecord _record(
      AiTurnRequest request,
      String url,
      Map<String, dynamic> body,
      Map<String, String> query,
      Map<String, String> headers,
      dynamic rawResponse,
      int status,
      int durationMs, {
      String? assembledContent,
      }) {
    final options = RequestOptions(
      path: url,
      method: 'POST',
      headers: headers,
      queryParameters: query,
    );
    return AdapterSupport.buildRecord(
      options: options,
      requestBody: jsonEncode(body),
      status: status,
      responseBody:
          assembledContent ?? (rawResponse == null ? null : jsonEncode(rawResponse)),
      durationMs: durationMs,
    );
  }

  @override
  Future<List<String>> listModels({
    required AIProvider provider,
    required String apiKey,
  }) async {
    final base = _baseWithoutEndpoint(provider);
    final url = '$base/models';
    final headers = _headers(provider, apiKey);
    final query = _queryFor(provider, apiKey);
    final dio = AppDio.create(receiveTimeout: const Duration(seconds: 30));
    try {
      final response = await dio.get<Map<String, dynamic>>(
        url,
        queryParameters: query,
        options: Options(headers: headers, responseType: ResponseType.json),
      );
      final list = response.data?['models'];
      if (list is List) {
        final names = <String>{};
        for (final m in list) {
          if (m is Map) {
            final name = (m['name'] ?? '').toString();
            // format: models/gemini-pro
            final short = name.startsWith('models/')
                ? name.substring('models/'.length)
                : name;
            if (short.isNotEmpty) names.add(short);
          }
        }
        return names.toList()..sort();
      }
      return const [];
    } on DioException catch (e) {
      throw ApiException.fromDio(e, providerName: provider.name);
    }
  }

  @override
  Future<ConnectionTestResult> testConnection(AiTurnRequest request) async {
    final url = _generateUrl(request.provider, request.model);
    final headers = _headers(request.provider, request.apiKey);
    final query = _queryFor(request.provider, request.apiKey);
    final body = <String, dynamic>{
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'Reply with the single word: ok'}
          ]
        }
      ],
      'generationConfig': {
        'maxOutputTokens': 1,
      },
    };
    final description = 'Sends one short message (maxOutputTokens=1) to $url '
        'using your configured model and authentication.';
    final dio = AppDio.create(receiveTimeout: const Duration(seconds: 45));
    final started = DateTime.now();
    try {
      final response = await dio.post<Map<String, dynamic>>(
        url,
        data: jsonEncode(body),
        queryParameters: query,
        options: Options(headers: headers, responseType: ResponseType.json),
      );
      final durationMs = DateTime.now().difference(started).inMilliseconds;
      return ConnectionTestResult(
        ok: true,
        summary: 'Connection successful — responded in ${durationMs} ms',
        detail: description,
        durationMs: durationMs,
        requestRecord: request.inspectorEnabled
            ? _record(request, url, body, query, headers, response.data,
                response.statusCode ?? 200, durationMs)
            : null,
      );
    } on DioException catch (e) {
      final wrapped =
          ApiException.fromDio(e, providerName: request.provider.name);
      return ConnectionTestResult(
        ok: false,
        summary: wrapped.message,
        detail: description,
        durationMs: DateTime.now().difference(started).inMilliseconds,
      );
    }
  }
}
