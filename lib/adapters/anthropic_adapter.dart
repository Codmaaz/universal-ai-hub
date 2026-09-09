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

/// Adapter for Anthropic's Messages API. Does NOT convert to the OpenAI
/// format — Anthropic's schema (system + content blocks + SSE events) is
/// produced natively here.
class AnthropicAdapter implements AIProviderAdapter {
  const AnthropicAdapter();

  static const String apiVersion = '2023-06-01';

  @override
  ProviderType get type => ProviderType.anthropic;

  @override
  String get label => 'Anthropic';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsChat: true,
        supportsStreaming: true,
        supportsModelListing: false,
        supportsSystemPrompt: true,
        supportsTemperature: true,
        supportsMaxTokens: true,
        supportsTopP: true,
        supportsStopSequences: true,
        supportsFrequencyPenalty: false,
        supportsPresencePenalty: false,
        supportsSeed: false,
      );

  @override
  String? validateConfiguration(AIProvider provider) {
    if (provider.baseUrl.trim().isEmpty) return 'Base URL is required.';
    return null;
  }

  String _messagesUrl(AIProvider provider) =>
      AdapterSupport.resolveUrl(provider); // defaults to /v1/messages

  Map<String, String> _headers(AIProvider provider, String apiKey,
      {bool json = true}) {
    final headers = <String, String>{
      if (json) 'content-type': 'application/json',
      'anthropic-version': apiVersion,
    };
    switch (provider.authMethod) {
      case AuthMethod.bearerToken:
        headers['authorization'] = 'Bearer $apiKey';
        break;
      case AuthMethod.apiKeyHeader:
      case AuthMethod.customHeader:
        final name = provider.authMethod == AuthMethod.apiKeyHeader
            ? 'x-api-key'
            : provider.customAuthHeaderName.trim();
        final value = provider.authMethod == AuthMethod.customHeader
            ? AuthHeaderBuilder.resolveTemplate(
                provider.customAuthHeaderValue, apiKey)
            : apiKey;
        if (name.isNotEmpty) headers[name] = value;
        break;
      case AuthMethod.queryParam:
        break;
    }
    // Let users override provider-specific headers.
    for (final h in provider.customHeaders) {
      if (h.name.trim().isNotEmpty) {
        headers[h.name.trim()] =
            AuthHeaderBuilder.resolveTemplate(h.value, apiKey);
      }
    }
    return headers;
  }

  Map<String, dynamic> buildRequestBody(AiTurnRequest request) {
    final s = request.settings.filteredBy(request.provider);
    return {
      'model': request.model,
      'max_tokens': s.maxTokens ?? 1024,
      if (request.systemPrompt.trim().isNotEmpty)
        'system': request.systemPrompt,
      'messages': [
        for (final m in request.wireMessages)
          {
            'role': m.role == ChatMessageRole.assistant ? 'assistant' : 'user',
            'content': m.content,
          }
      ],
      'stream': request.streaming,
      if (s.temperature != null) 'temperature': s.temperature,
      if (s.topP != null) 'top_p': s.topP,
      if (s.stopSequences.isNotEmpty) 'stop_sequences': s.stopSequences,
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
    final url = _messagesUrl(request.provider);
    final body = buildRequestBody(request);
    final headers = _headers(request.provider, request.apiKey);
    final query = request.provider.authMethod == AuthMethod.queryParam
        ? _queryParam(request)
        : const <String, String>{};
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
      final text = extractContent(response.data);
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
    final url = _messagesUrl(request.provider);
    final body = buildRequestBody(request);
    final headers = _headers(request.provider, request.apiKey);
    final query = request.provider.authMethod == AuthMethod.queryParam
        ? _queryParam(request)
        : const <String, String>{};
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
        if (delta != null) {
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
      throw ApiException.fromDio(e, providerName: request.provider.name);
    }
  }

  Map<String, String> _queryParam(AiTurnRequest request) {
    final name = request.provider.customAuthHeaderName.trim().isEmpty
        ? 'api_key'
        : request.provider.customAuthHeaderName.trim();
    return {name: request.apiKey};
  }

  /// SSE `content_block_delta` events carry `delta: {type: text_delta, text}`.
  String? streamDelta(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) return null;
    final json = safeDecode(trimmed);
    if (json is! Map<String, dynamic>) return null;
    final type = json['type'];
    if (type == 'content_block_delta') {
      final delta = json['delta'];
      if (delta is Map<String, dynamic>) {
        final text = delta['text'];
        if (text != null) return text.toString();
      }
    }
    return null;
  }

  String extractContent(Map<String, dynamic>? json) {
    if (json == null) return '';
    final content = json['content'];
    if (content is List) {
      final buf = StringBuffer();
      for (final block in content) {
        if (block is Map && block['type'] == 'text') {
          buf.write(block['text'] ?? '');
        }
      }
      return buf.toString();
    }
    return '';
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
    throw UnsupportedError(
        'Anthropic-style endpoints do not expose a model listing here. '
        'Enter the model name manually.');
  }

  @override
  Future<ConnectionTestResult> testConnection(AiTurnRequest request) async {
    final url = _messagesUrl(request.provider);
    final headers = _headers(request.provider, request.apiKey);
    final query = request.provider.authMethod == AuthMethod.queryParam
        ? _queryParam(request)
        : const <String, String>{};
    final body = <String, dynamic>{
      'model': request.model,
      'max_tokens': 1,
      'messages': [
        {'role': 'user', 'content': 'Reply with the single word: ok'}
      ],
    };
    final description =
        'Sends a single short message (max_tokens=1) to $url using your '
        'configured model and authentication.';
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
