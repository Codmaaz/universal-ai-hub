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

/// Adapter for any API that speaks the OpenAI Chat Completions dialect
/// (OpenAI itself, commercial OpenAI-compatible gateways, and local servers
/// like LM Studio or Ollama's OpenAI endpoint).
class OpenAICompatibleAdapter implements AIProviderAdapter {
  const OpenAICompatibleAdapter();

  @override
  ProviderType get type => ProviderType.openaiCompatible;

  @override
  String get label => 'OpenAI Compatible';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsChat: true,
        supportsStreaming: true,
        supportsModelListing: true,
        supportsSystemPrompt: true,
        supportsImages: true,
        supportsTemperature: true,
        supportsMaxTokens: true,
        supportsTopP: true,
        supportsFrequencyPenalty: true,
        supportsPresencePenalty: true,
        supportsStopSequences: true,
        supportsSeed: true,
      );

  @override
  String? validateConfiguration(AIProvider provider) {
    if (provider.baseUrl.trim().isEmpty) return 'Base URL is required.';
    return null;
  }

  String _chatUrl(AIProvider provider) => AdapterSupport.resolveUrl(provider);

  Map<String, String> _authHeaders(AIProvider provider, String apiKey) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    switch (provider.authMethod) {
      case AuthMethod.bearerToken:
        headers['Authorization'] = 'Bearer $apiKey';
        break;
      case AuthMethod.apiKeyHeader:
        headers['x-api-key'] = apiKey;
        break;
      case AuthMethod.customHeader:
        headers[provider.customAuthHeaderName.trim()] =
            AuthHeaderBuilder.resolveTemplate(
                provider.customAuthHeaderValue, apiKey);
        break;
      case AuthMethod.queryParam:
        break; // applied through AdapterSupport
    }
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
      'messages': [
        if (request.systemPrompt.trim().isNotEmpty)
          {'role': 'system', 'content': request.systemPrompt},
        for (final m in request.wireMessages)
          {'role': m.role.wireName, 'content': m.content},
      ],
      'stream': request.streaming,
      if (s.temperature != null) 'temperature': s.temperature,
      if (s.maxTokens != null) 'max_tokens': s.maxTokens,
      if (s.topP != null) 'top_p': s.topP,
      if (s.frequencyPenalty != null)
        'frequency_penalty': s.frequencyPenalty,
      if (s.presencePenalty != null) 'presence_penalty': s.presencePenalty,
      if (s.stopSequences.isNotEmpty) 'stop': s.stopSequences,
      if (s.seed != null) 'seed': s.seed,
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
    final url = _chatUrl(request.provider);
    final body = buildRequestBody(request);
    final headers = _authHeaders(request.provider, request.apiKey);
    final query = _queryFor(request);
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
      final content = extractContent(response.data);
      final durationMs = DateTime.now().difference(started).inMilliseconds;
      return AiTurnResult(
        content: content,
        providerName: request.provider.name,
        requestRecord: request.inspectorEnabled
            ? _makeRecord(request, url, body, query, headers,
                response.data, response.statusCode ?? 200, durationMs)
            : null,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e, providerName: request.provider.name);
    }
  }

  Future<AiTurnResult> _sendStreaming(AiTurnRequest request) async {
    final url = _chatUrl(request.provider);
    final body = buildRequestBody(request);
    final headers = _authHeaders(request.provider, request.apiKey);
    final query = _queryFor(request);
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
        final delta = extractStreamDelta(payload);
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
            ? _makeRecord(request, url, body, query, headers, null,
                response.statusCode ?? 200, durationMs,
                assembledContent: content)
            : null,
      );
    } on DioException catch (e) {
      final apiError = ApiException.fromDio(e, providerName: request.provider.name);
      throw apiError.copyWith(partialContent: buffer.toString());
    } catch (e) {
      // Stream failures can surface as SocketException/FormatException rather
      // than DioException after headers have already been received. Preserve
      // any long-answer content already delivered to the user.
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

  Map<String, String> _queryFor(AiTurnRequest request) {
    if (request.provider.authMethod != AuthMethod.queryParam) return const {};
    final name = request.provider.customAuthHeaderName.trim().isEmpty
        ? 'api_key'
        : request.provider.customAuthHeaderName.trim();
    return {name: request.apiKey};
  }

  ApiRequestRecord _makeRecord(
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
    final responseText = assembledContent ??
        (rawResponse == null ? null : jsonEncode(rawResponse));
    return AdapterSupport.buildRecord(
      options: options,
      requestBody: jsonEncode(body),
      status: status,
      responseBody: responseText,
      durationMs: durationMs,
    );
  }

  /// Extracts one SSE data payload's content delta.
  String? extractStreamDelta(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty || trimmed == '[DONE]') return null;
    if (!trimmed.startsWith('{')) {
      // Non-conforming gateway streaming raw text.
      return trimmed;
    }
    final json = safeDecode(trimmed);
    if (json is! Map<String, dynamic>) return null;
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final delta = first['delta'];
        if (delta is Map<String, dynamic>) {
          final c = delta['content'];
          if (c != null) return c.toString();
        }
        final msg = first['message'];
        if (msg is Map<String, dynamic>) {
          final c = msg['content'];
          if (c != null) return c.toString();
        }
        final text = first['text'];
        if (text != null) return text.toString();
      }
    }
    return null;
  }

  String extractContent(Map<String, dynamic>? json) {
    if (json == null) return '';
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          final c = message['content'];
          if (c != null) return c.toString();
        }
        final text = first['text'];
        if (text != null) return text.toString();
      }
    }
    return '';
  }

  @override
  Future<List<String>> listModels({
    required AIProvider provider,
    required String apiKey,
  }) async {
    final modelsUrl = _modelsUrl(_chatUrl(provider));
    final headers = _authHeaders(provider, apiKey);
    final query = provider.authMethod == AuthMethod.queryParam
        ? {
            provider.customAuthHeaderName.trim().isEmpty
                ? 'api_key'
                : provider.customAuthHeaderName.trim(): apiKey,
          }
        : const <String, String>{};
    final dio = AppDio.create(receiveTimeout: const Duration(seconds: 30));
    try {
      final response = await dio.get<Map<String, dynamic>>(
        modelsUrl,
        queryParameters: query,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
        ),
      );
      final list = response.data?['data'];
      if (list is List) {
        final names = <String>{};
        for (final item in list) {
          if (item is Map) {
            final id = (item['id'] ?? item['name'] ?? '').toString();
            if (id.isNotEmpty) names.add(id);
          }
        }
        return names.toList()..sort();
      }
      return const [];
    } on DioException catch (e) {
      throw ApiException.fromDio(e, providerName: provider.name);
    }
  }

  String _modelsUrl(String chatUrl) {
    final idx = chatUrl.lastIndexOf('/chat/completions');
    if (idx >= 0) return '${chatUrl.substring(0, idx)}/models';
    final slash = chatUrl.lastIndexOf('/');
    return slash > 'https://'.length
        ? '${chatUrl.substring(0, slash)}/models'
        : '${chatUrl}/models';
  }

  @override
  Future<ConnectionTestResult> testConnection(AiTurnRequest request) async {
    final url = _chatUrl(request.provider);
    final headers = _authHeaders(request.provider, request.apiKey);
    final query = _queryFor(request);
    final body = <String, dynamic>{
      'model': request.model,
      'messages': [
        {'role': 'user', 'content': 'Reply with the single word: ok'}
      ],
      'max_tokens': 1,
      'stream': false,
    };
    final description =
        'Sends a single short message (max_tokens=1) to $url using your '
        'configured model and authentication. No charge-worthy work.';
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
      extractContent(response.data); // ensure it is parseable
      return ConnectionTestResult(
        ok: true,
        summary: 'Connection successful — responded in ${durationMs} ms',
        detail: description,
        durationMs: durationMs,
        requestRecord: request.inspectorEnabled
            ? _makeRecord(request, url, body, query, headers, response.data,
                response.statusCode ?? 200, durationMs)
            : null,
      );
    } on DioException catch (e) {
      final wrapped =
          ApiException.fromDio(e, providerName: request.provider.name);
      final durationMs = DateTime.now().difference(started).inMilliseconds;
      return ConnectionTestResult(
        ok: false,
        summary: wrapped.message,
        detail: description,
        durationMs: durationMs,
        requestRecord: request.inspectorEnabled
            ? _makeRecord(request, url, body, query, headers, null,
                (e.response?.statusCode ?? 0), durationMs)
            : null,
      );
    }
  }
}
