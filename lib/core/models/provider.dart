import 'types.dart';

/// Header entry with a templated value. Secret values are never stored here;
/// use the `{{API_KEY}}` placeholder instead and it is resolved at request
/// time from secure storage.
class HttpHeader {
  const HttpHeader({required this.name, required this.value});

  final String name;
  final String value;

  HttpHeader copyWith({String? name, String? value}) =>
      HttpHeader(name: name ?? this.name, value: value ?? this.value);

  Map<String, dynamic> toJson() => {'name': name, 'value': value};

  static HttpHeader fromJson(Map<String, dynamic> json) => HttpHeader(
        name: (json['name'] ?? '') as String,
        value: (json['value'] ?? '') as String,
      );
}

/// HTTP methods allowed by the Custom API adapter.
enum HttpMethod { get, post, put, patch, delete }

extension HttpMethodX on HttpMethod {
  String get wire {
    switch (this) {
      case HttpMethod.get:
        return 'GET';
      case HttpMethod.post:
        return 'POST';
      case HttpMethod.put:
        return 'PUT';
      case HttpMethod.patch:
        return 'PATCH';
      case HttpMethod.delete:
        return 'DELETE';
    }
  }

  static HttpMethod fromWire(String? value) {
    return HttpMethod.values.firstWhere(
      (m) => m.wire == (value ?? '').toUpperCase(),
      orElse: () => HttpMethod.post,
    );
  }
}

/// Placeholders available inside custom API templates.
abstract final class TemplateTokens {
  static const apiKey = r'{{API_KEY}}';
  static const model = r'{{MODEL}}';
  static const prompt = r'{{PROMPT}}';
  static const systemPrompt = r'{{SYSTEM_PROMPT}}';
  static const messages = r'{{MESSAGES}}';

  static const all = [apiKey, model, prompt, systemPrompt, messages];
}

/// Static facts about what an adapter can do. The UI adapts to these instead
/// of assuming every provider is the same.
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.supportsChat,
    this.supportsStreaming = true,
    this.supportsModelListing = false,
    this.supportsSystemPrompt = true,
    this.supportsImages = false,
    this.supportsFiles = false,
    this.supportsAudio = false,
    this.supportsTemperature = true,
    this.supportsMaxTokens = true,
    this.supportsTopP = true,
    this.supportsFrequencyPenalty = false,
    this.supportsPresencePenalty = false,
    this.supportsStopSequences = false,
    this.supportsSeed = false,
  });

  final bool supportsChat;
  final bool supportsStreaming;
  final bool supportsModelListing;
  final bool supportsSystemPrompt;
  final bool supportsImages;
  final bool supportsFiles;
  final bool supportsAudio;
  final bool supportsTemperature;
  final bool supportsMaxTokens;
  final bool supportsTopP;
  final bool supportsFrequencyPenalty;
  final bool supportsPresencePenalty;
  final bool supportsStopSequences;
  final bool supportsSeed;

  /// Feature matrix merged with the effective capabilities of [other].
  ProviderCapabilities mergeWith(ProviderCapabilities other) => ProviderCapabilities(
        supportsChat: supportsChat && other.supportsChat,
        supportsStreaming: supportsStreaming && other.supportsStreaming,
        supportsModelListing: supportsModelListing && other.supportsModelListing,
        supportsSystemPrompt: supportsSystemPrompt && other.supportsSystemPrompt,
        supportsImages: supportsImages && other.supportsImages,
        supportsFiles: supportsFiles && other.supportsFiles,
        supportsAudio: supportsAudio && other.supportsAudio,
        supportsTemperature: supportsTemperature && other.supportsTemperature,
        supportsMaxTokens: supportsMaxTokens && other.supportsMaxTokens,
        supportsTopP: supportsTopP && other.supportsTopP,
        supportsFrequencyPenalty:
            supportsFrequencyPenalty && other.supportsFrequencyPenalty,
        supportsPresencePenalty:
            supportsPresencePenalty && other.supportsPresencePenalty,
        supportsStopSequences: supportsStopSequences && other.supportsStopSequences,
        supportsSeed: supportsSeed && other.supportsSeed,
      );
}

/// A user-defined provider profile.
///
/// IMPORTANT: never holds the API key — secrets live in platform encrypted
/// storage and are fetched separately by id. This class is safe to export.
class AIProvider {
  const AIProvider({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.authMethod,
    this.customAuthHeaderName = '',
    this.customAuthHeaderValue = '',
    this.customHeaders = const [],
    this.enabledCapabilities = const [AiCapability.chat],
    this.capabilityEndpoints = const {},
    this.capabilityMethods = const {},
    this.capabilityRequestTemplates = const {},
    this.capabilityResponsePaths = const {},
    this.model = '',
    this.endpoint = '',
    this.isEnabled = true,
    this.streamingEnabled = true,
    // Custom API mode fields (ignored for other types).
    this.httpMethod = HttpMethod.post,
    this.requestBodyTemplate = '',
    this.responsePath = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final ProviderType type;
  final String baseUrl;

  /// How the API key is attached to requests.
  final AuthMethod authMethod;

  /// Header/query-parameter name when auth is custom header or query param.
  final String customAuthHeaderName;

  /// Header value template when auth is a custom header. May embed
  /// `{{API_KEY}}`.
  final String customAuthHeaderValue;

  /// Extra headers — values may embed `{{API_KEY}}`.
  final List<HttpHeader> customHeaders;

  /// Capabilities and per-capability HTTP mappings for the universal connector.
  final List<AiCapability> enabledCapabilities;
  final Map<String, String> capabilityEndpoints;
  final Map<String, String> capabilityMethods;
  final Map<String, String> capabilityRequestTemplates;
  final Map<String, String> capabilityResponsePaths;

  /// Last used model (blank until the user picks or types one).
  final String model;

  /// Path appended to [baseUrl] when not left empty (e.g.
  /// `/chat/completions`). For Custom type this is the request path.
  final String endpoint;

  final bool isEnabled;
  final bool streamingEnabled;

  // ---- Custom API mode ------------------------------------------------
  final HttpMethod httpMethod;
  final String requestBodyTemplate;
  final String responsePath;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Default path for this provider kind when [endpoint] is empty.
  String get defaultEndpoint {
    switch (type) {
      case ProviderType.openaiCompatible:
        return '/chat/completions';
      case ProviderType.anthropic:
        return '/v1/messages';
      case ProviderType.gemini:
        return '';
      case ProviderType.custom:
        return '';
      case ProviderType.universalHttp:
        return '';
    }
  }

  ProviderCapabilities get capabilities {
    switch (type) {
      case ProviderType.openaiCompatible:
        return const ProviderCapabilities(
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
      case ProviderType.anthropic:
        return const ProviderCapabilities(
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
      case ProviderType.gemini:
        return const ProviderCapabilities(
          supportsChat: true,
          supportsStreaming: true,
          supportsModelListing: true,
          supportsSystemPrompt: true,
          supportsTemperature: true,
          supportsMaxTokens: true,
          supportsTopP: true,
          supportsStopSequences: false,
          supportsSeed: false,
        );
      case ProviderType.custom:
        return const ProviderCapabilities(
          supportsChat: true,
          supportsStreaming: false,
          supportsModelListing: false,
          supportsSystemPrompt: false,
          supportsTemperature: false,
          supportsMaxTokens: false,
          supportsTopP: false,
        );
      case ProviderType.universalHttp:
        return ProviderCapabilities(
          supportsChat: enabledCapabilities.contains(AiCapability.chat),
          supportsStreaming: false,
          supportsModelListing: false,
          supportsSystemPrompt: enabledCapabilities.contains(AiCapability.chat),
          supportsImages: enabledCapabilities.contains(AiCapability.imageGeneration),
          supportsFiles: enabledCapabilities.contains(AiCapability.files),
          supportsAudio: enabledCapabilities.contains(AiCapability.audioGeneration) ||
              enabledCapabilities.contains(AiCapability.speechToText) ||
              enabledCapabilities.contains(AiCapability.textToSpeech),
          supportsTemperature: false,
          supportsMaxTokens: false,
          supportsTopP: false,
        );
    }
  }

  AIProvider copyWith({
    String? name,
    ProviderType? type,
    String? baseUrl,
    AuthMethod? authMethod,
    String? customAuthHeaderName,
    String? customAuthHeaderValue,
    List<HttpHeader>? customHeaders,
    List<AiCapability>? enabledCapabilities,
    Map<String, String>? capabilityEndpoints,
    Map<String, String>? capabilityMethods,
    Map<String, String>? capabilityRequestTemplates,
    Map<String, String>? capabilityResponsePaths,
    String? model,
    String? endpoint,
    bool? isEnabled,
    bool? streamingEnabled,
    HttpMethod? httpMethod,
    String? requestBodyTemplate,
    String? responsePath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AIProvider(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      authMethod: authMethod ?? this.authMethod,
      customAuthHeaderName: customAuthHeaderName ?? this.customAuthHeaderName,
      customAuthHeaderValue: customAuthHeaderValue ?? this.customAuthHeaderValue,
      customHeaders: customHeaders ?? this.customHeaders,
      enabledCapabilities: enabledCapabilities ?? this.enabledCapabilities,
      capabilityEndpoints: capabilityEndpoints ?? this.capabilityEndpoints,
      capabilityMethods: capabilityMethods ?? this.capabilityMethods,
      capabilityRequestTemplates: capabilityRequestTemplates ?? this.capabilityRequestTemplates,
      capabilityResponsePaths: capabilityResponsePaths ?? this.capabilityResponsePaths,
      model: model ?? this.model,
      endpoint: endpoint ?? this.endpoint,
      isEnabled: isEnabled ?? this.isEnabled,
      streamingEnabled: streamingEnabled ?? this.streamingEnabled,
      httpMethod: httpMethod ?? this.httpMethod,
      requestBodyTemplate: requestBodyTemplate ?? this.requestBodyTemplate,
      responsePath: responsePath ?? this.responsePath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'baseUrl': baseUrl,
        'authMethod': authMethod.name,
        'customAuthHeaderName': customAuthHeaderName,
        'customAuthHeaderValue': customAuthHeaderValue,
        'customHeaders': customHeaders.map((e) => e.toJson()).toList(),
        'enabledCapabilities': enabledCapabilities.map((e) => e.name).toList(),
        'capabilityEndpoints': capabilityEndpoints,
        'capabilityMethods': capabilityMethods,
        'capabilityRequestTemplates': capabilityRequestTemplates,
        'capabilityResponsePaths': capabilityResponsePaths,
        'model': model,
        'endpoint': endpoint,
        'isEnabled': isEnabled,
        'streamingEnabled': streamingEnabled,
        'httpMethod': httpMethod.wire,
        'requestBodyTemplate': requestBodyTemplate,
        'responsePath': responsePath,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static AIProvider fromJson(Map<String, dynamic> json) => AIProvider(
        id: json['id'] as String,
        name: (json['name'] ?? '') as String,
        type: ProviderType.fromStorage(json['type'] as String?),
        baseUrl: (json['baseUrl'] ?? '') as String,
        authMethod: AuthMethod.fromStorage(json['authMethod'] as String?),
        customAuthHeaderName: (json['customAuthHeaderName'] ?? '') as String,
        customAuthHeaderValue: (json['customAuthHeaderValue'] ?? '') as String,
        customHeaders: ((json['customHeaders'] as List?) ?? const [])
            .map((e) => HttpHeader.fromJson(e as Map<String, dynamic>))
            .toList(),
        enabledCapabilities: ((json['enabledCapabilities'] as List?) ?? const ['chat'])
            .map((e) => AiCapability.fromStorage(e.toString()))
            .whereType<AiCapability>()
            .toList(),
        capabilityEndpoints: Map<String, String>.from((json['capabilityEndpoints'] as Map?) ?? const {}),
        capabilityMethods: Map<String, String>.from((json['capabilityMethods'] as Map?) ?? const {}),
        capabilityRequestTemplates: Map<String, String>.from((json['capabilityRequestTemplates'] as Map?) ?? const {}),
        capabilityResponsePaths: Map<String, String>.from((json['capabilityResponsePaths'] as Map?) ?? const {}),
        model: (json['model'] ?? '') as String,
        endpoint: (json['endpoint'] ?? '') as String,
        isEnabled: (json['isEnabled'] as bool?) ?? true,
        streamingEnabled: (json['streamingEnabled'] as bool?) ?? true,
        httpMethod:
            HttpMethodX.fromWire(json['httpMethod'] as String? ?? 'POST'),
        requestBodyTemplate: (json['requestBodyTemplate'] ?? '') as String,
        responsePath: (json['responsePath'] ?? '') as String,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String),
        updatedAt: DateTime.tryParse((json['updatedAt'] ?? '') as String),
      );
}
