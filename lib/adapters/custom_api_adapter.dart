import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/models/api_request_record.dart';
import '../core/models/provider.dart';
import '../core/models/types.dart';
import '../core/network/api_exception.dart';
import '../core/network/app_dio.dart';
import '../core/network/auth_headers.dart';
import '../core/utils/secret_masker.dart';
import 'ai_provider_adapter.dart';
import 'json_path.dart';

/// Adapter for arbitrary HTTP APIs that are not OpenAI/Anthropic/Gemini
/// shaped. Everything is user configurable:
///   - HTTP method, full endpoint
///   - request body template with {{...}} placeholders
///   - a JSON pointer to the assistant text in the response
class CustomApiAdapter implements AIProviderAdapter {
  const CustomApiAdapter();

  @override
  ProviderType get type => ProviderType.custom;

  @override
  String get label => 'Custom API';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        supportsChat: true,
        supportsStreaming: false,
        supportsModelListing: false,
        supportsSystemPrompt: false,
        supportsTemperature: false,
        supportsMaxTokens: false,
        supportsTopP: false,
      );

  @override
  String? validateConfiguration(AIProvider provider) {
    if (provider.baseUrl.trim().isEmpty) {
      return 'Endpoint URL is required for a Custom API.';
    }
    if (provider.type == ProviderType.universalHttp && provider.enabledCapabilities.isEmpty) {
      return 'Select at least one capability for the Universal HTTP API.';
    }
    final tpl = _effectiveTemplate(provider, 'chat').trim();
    if (tpl.isNotEmpty && !_isValidJsonTemplate(tpl)) {
      return 'The request body template must be valid JSON (with '
          '{{PLACEHOLDERS}} allowed inside string values).';
    }
    if (provider.type == ProviderType.custom &&
        _effectiveResponsePath(provider, 'chat').trim().isEmpty &&
        provider.httpMethod != HttpMethod.get) {
      return 'A response JSON path is required (e.g. response.text or '
          'choices[0].message.content).';
    }
    if (provider.type == ProviderType.universalHttp) {
      for (final capability in provider.enabledCapabilities) {
        final key = capability.name;
        final endpoint = provider.capabilityEndpoints[key] ?? provider.endpoint;
        final template = provider.capabilityRequestTemplates[key] ?? provider.requestBodyTemplate;
        if (endpoint.trim().isEmpty) return 'Add an endpoint for ${capability.label}.';
        if (capability != AiCapability.chat && template.trim().isEmpty &&
            provider.capabilityEndpoints[key]!.trim().isEmpty) {
          return 'Add a request template for ${capability.label}, or use a standard endpoint.';
        }
      }
    }
    return null;
  }

  static bool _isValidJsonTemplate(String template) {
    // Replace placeholders with dummy JSON strings then validate.
    var probe = template;
    for (final token in TemplateTokens.all) {
      probe = probe.replaceAll(token, '"probe"');
    }
    try {
      jsonDecode(probe);
      return true;
    } catch (_) {
      // Top-level JSON strings are tolerated for raw body apis.
      return template.trimLeft().startsWith('"');
    }
  }

  String _resolveEndpoint(AIProvider provider) =>
      AdapterSupport.resolveUrl(provider);

  /// Substitutes template placeholders with live request values.
  String _renderBody(AiTurnRequest request) {
    final template = _effectiveTemplate(request.provider, 'chat').trim();
    final provider = request.provider;

    final userMessages = request.wireMessages
        .where((m) => m.role == ChatMessageRole.user)
        .map((m) => m.content)
        .join('\n');
    final prompt = request.wireMessages.isNotEmpty
        ? request.wireMessages.last.content
        : userMessages;
    final messagesJson = jsonEncode([
      for (final m in request.wireMessages)
        {'role': m.role.wireName, 'content': m.content}
    ]);

    String body;
    if (template.isEmpty) {
      body = jsonEncode({
        if (request.model.isNotEmpty) 'model': request.model,
        'messages': [
          for (final m in request.wireMessages)
            {'role': m.role.wireName, 'content': m.content}
        ],
      });
    } else {
      body = template;
    }

    var out = body;
    // Tokens can appear either inside JSON strings or as raw JSON values.
    // Use JSON-aware placeholders first, then fall back to escaped text.
    out = _replaceJsonToken(out, TemplateTokens.systemPrompt, request.systemPrompt);
    out = _replaceJsonToken(out, TemplateTokens.prompt, prompt);
    out = _replaceRawJsonToken(out, TemplateTokens.messages, messagesJson);
    out = _replaceJsonToken(out, TemplateTokens.model, request.model);
    out = _replaceJsonToken(out, TemplateTokens.apiKey, request.apiKey);
    return out;
  }

  String _replaceJsonToken(String source, String token, String value) {
    // If the token is quoted, replace the whole quoted token with an escaped
    // JSON string. If it is unquoted, emit a JSON string value.
    final quoted = '"$token"';
    if (source.contains(quoted)) return source.replaceAll(quoted, jsonEncode(value));
    return source.replaceAll(token, jsonEncode(value));
  }

  String _replaceRawJsonToken(String source, String token, String jsonValue) {
    final quoted = '"$token"';
    if (source.contains(quoted)) return source.replaceAll(quoted, jsonValue);
    return source.replaceAll(token, jsonValue);
  }

  String _effectiveTemplate(AIProvider provider, String capability) {
    if (provider.type == ProviderType.universalHttp) {
      return provider.capabilityRequestTemplates[capability] ?? provider.requestBodyTemplate;
    }
    return provider.requestBodyTemplate;
  }

  String _effectiveResponsePath(AIProvider provider, String capability) {
    if (provider.type == ProviderType.universalHttp) {
      return provider.capabilityResponsePaths[capability] ?? provider.responsePath;
    }
    return provider.responsePath;
  }

  HttpMethod effectiveMethod(AIProvider provider, String capability) {
    if (provider.type == ProviderType.universalHttp) {
      return HttpMethodX.fromWire(provider.capabilityMethods[capability] ?? provider.httpMethod.wire);
    }
    return provider.httpMethod;
  }

  String effectiveEndpoint(AIProvider provider, String capability) {
    if (provider.type == ProviderType.universalHttp) {
      return provider.capabilityEndpoints[capability] ?? provider.endpoint;
    }
    return provider.endpoint;
  }

  @override
  Future<AiTurnResult> send(AiTurnRequest request) async {
    // Custom adapter v1 is non-streaming by design (capability gate).
    final provider = request.provider;
    final method = effectiveMethod(provider, 'chat');
    final effective = provider.type == ProviderType.universalHttp
        ? provider.copyWith(endpoint: effectiveEndpoint(provider, 'chat'), requestBodyTemplate: _effectiveTemplate(provider, 'chat'), responsePath: _effectiveResponsePath(provider, 'chat'), httpMethod: method)
        : provider;
    final url = _resolveEndpoint(effective);
    final dio = AppDio.create(
      connectTimeout: request.connectTimeout,
      receiveTimeout: request.receiveTimeout,
    );
    final started = DateTime.now();

    final decoration =
        AuthHeaderBuilder.build(provider: provider, apiKey: request.apiKey);
    final headers = <String, String>{
      if (method != HttpMethod.get && method != HttpMethod.delete)
        'Content-Type': 'application/json',
      ...decoration.headers,
    };
    final query = Map<String, String>.from(decoration.queryParameters);
    final bodyText = _renderBody(request);
    final hasBody = bodyText.isNotEmpty &&
        method != HttpMethod.get &&
        method != HttpMethod.delete;

    try {
      Response<String> response;
      switch (method) {
        case HttpMethod.get:
          response = await dio.get<String>(url,
              queryParameters: query,
              options: Options(
                  headers: headers, responseType: ResponseType.plain));
        case HttpMethod.post:
          response = await dio.post<String>(url,
              data: hasBody ? bodyText : null,
              queryParameters: query,
              options: Options(
                  headers: headers, responseType: ResponseType.plain));
        case HttpMethod.put:
          response = await dio.put<String>(url,
              data: hasBody ? bodyText : null,
              queryParameters: query,
              options: Options(
                  headers: headers, responseType: ResponseType.plain));
        case HttpMethod.patch:
          response = await dio.patch<String>(url,
              data: hasBody ? bodyText : null,
              queryParameters: query,
              options: Options(
                  headers: headers, responseType: ResponseType.plain));
        case HttpMethod.delete:
          response = await dio.delete<String>(url,
              queryParameters: query,
              options: Options(
                  headers: headers, responseType: ResponseType.plain));
      }

      final raw = response.data ?? '';
      final durationMs = DateTime.now().difference(started).inMilliseconds;
      dynamic parsed;
      String content;
      try {
        parsed = jsonDecode(raw);
      } catch (_) {
        parsed = raw;
      }
      if (parsed is String) {
        content = parsed;
      } else {
        final found = resolveJsonPath(_effectiveResponsePath(provider, 'chat'), parsed);
        content = found == null ? '' : found.toString();
        if (content.isEmpty) {
          // Fall back to common conventions when no path configured.
          content = _fallbackText(parsed);
        }
      }

      return AiTurnResult(
        content: content,
        providerName: provider.name,
        requestRecord: request.inspectorEnabled
            ? _record(url, method.wire, headers, query, hasBody ? bodyText : null,
                response.statusCode ?? 200, raw, durationMs)
            : null,
      );
    } on DioException catch (e) {
      final wrapped =
          ApiException.fromDio(e, providerName: provider.name);
      throw ApiException.message(
        wrapped.kind,
        wrapped.message,
        tip: wrapped.tip,
        providerName: provider.name,
        httpStatus: wrapped.httpStatus,
        sanitizedBody: wrapped.sanitizedBody,
      );
    }
  }

  String _fallbackText(dynamic parsed) {
    if (parsed is Map) {
      for (final key in ['text', 'output', 'response', 'answer', 'message', 'content']) {
        if (parsed[key] is String) return parsed[key] as String;
        if (parsed[key] is List && (parsed[key] as List).isNotEmpty) {
          final first = (parsed[key] as List).first;
          if (first is Map && first['text'] is String) return first['text'] as String;
        }
      }
    }
    return '';
  }

  ApiRequestRecord _record(String url, String method,
      Map<String, String> headers, Map<String, String> query, String? body,
      int status, String responseBody, int durationMs) {
    final options = RequestOptions(
      path: url,
      method: method,
      headers: headers,
      queryParameters: query,
    );
    return AdapterSupport.buildRecord(
      options: options,
      requestBody: body,
      status: status,
      responseBody: responseBody,
      durationMs: durationMs,
    );
  }

  @override
  Future<List<String>> listModels({
    required AIProvider provider,
    required String apiKey,
  }) async {
    throw UnsupportedError('Custom APIs do not expose a model listing here. '
        'Enter the model name manually if your template uses {{MODEL}}.');
  }

  @override
  Future<ConnectionTestResult> testConnection(AiTurnRequest request) async {
    final provider = request.provider;
    final description = _describe(request);
    if (provider.httpMethod == HttpMethod.delete) {
      return const ConnectionTestResult(
        ok: false,
        summary: 'Not tested — DELETE is destructive.',
        detail:
            'Connection auto-testing is disabled for destructive methods. '
            'Configure a GET or POST to probe this API instead.',
      );
    }
    final start = DateTime.now();
    try {
      // Run a light probe with the shortest possible payload.
      final probe = AiTurnRequest(
        provider: provider,
        apiKey: request.apiKey,
        messages: const [
          ChatMessage(
              id: 'probe',
              role: ChatMessageRole.user,
              content: 'ping'),
        ],
        model: request.model,
        systemPrompt: request.systemPrompt,
        settings: request.settings,
        streaming: false,
      );
      final result = await send(probe);
      final ms = DateTime.now().difference(start).inMilliseconds;
      final okText = result.content.isNotEmpty
          ? 'Connection successful — got a response in $ms ms.'
          : 'Connection reached the server (HTTP 2xx) but the response did '
              'not contain text. Check your response JSON path.';
      return ConnectionTestResult(
        ok: true,
        summary: okText,
        detail: description,
        durationMs: ms,
        requestRecord: result.requestRecord,
      );
    } on ApiException catch (e) {
      return ConnectionTestResult(
        ok: false,
        summary: e.message,
        detail: description,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        requestRecord: e.httpStatus != null
            ? _record(_resolveEndpoint(provider), provider.httpMethod.wire,
                const {}, const {}, null, e.httpStatus!, e.sanitizedBody ?? '',
                0)
            : null,
      );
    }
  }

  String _describe(AiTurnRequest request) {
    final p = request.provider;
    final url = _resolveEndpoint(p);
    final sb = StringBuffer()
      ..writeln('Sends: ${p.httpMethod.wire} $url')
      ..writeln('Auth: ${p.authMethod.label}');
    if (p.customHeaders.isNotEmpty) {
      sb.writeln('Custom headers: '
          '${p.customHeaders.map((h) => h.name).join(', ')}');
    }
    if (p.requestBodyTemplate.trim().isNotEmpty) {
      sb.writeln('Body template: ${SecretMasker.scrubSecrets(p.requestBodyTemplate)}');
      sb.writeln('Placeholders resolve from the current conversation.');
    }
    return sb.toString();
  }
}
