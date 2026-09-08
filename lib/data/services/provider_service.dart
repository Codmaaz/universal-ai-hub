import 'dart:async';

import 'package:dio/dio.dart';

import '../../adapters/ai_provider_adapter.dart';
import '../../adapters/adapter_registry.dart';
import '../../core/models/provider.dart';
import '../../core/models/types.dart';
import '../../core/network/api_exception.dart';
import '../../core/security/secure_token_store.dart';
import '../../core/utils/ids.dart';
import '../../data/repositories/provider_repository.dart';

/// Result of saving/validating a provider profile with its secret.
class ProviderSaveOutcome {
  const ProviderSaveOutcome({
    required this.provider,
    required this.validationError,
  });
  final AIProvider provider;
  final String? validationError;
}

/// Application service coordinating provider profiles, their secrets and the
/// network adapters. Everything at this level is testable with fakes.
class ProviderService {
  ProviderService({
    ProviderRepository? repository,
    SecureTokenStore? tokenStore,
    AdapterRegistryLookup? adapters,
  })  : _repo = repository ?? const ProviderRepository(),
        _tokens = tokenStore ?? SecureTokenStore(),
        _adapters = adapters ?? const _RealRegistry();

  final ProviderRepository _repo;
  final SecureTokenStore _tokens;
  final AdapterRegistryLookup _adapters;

  Future<List<AIProvider>> listAll() => _repo.listAll();

  Future<AIProvider?> findById(String id) => _repo.findById(id);

  /// True when a profile has a secret stored (i.e. it can send requests).
  Future<bool> hasKey(String id) => _tokens.hasKey(id);

  Future<String?> readKey(String id) => _tokens.readKey(id);

  /// Validates, stores the profile and stores its secret separately.
  Future<ProviderSaveOutcome> save({
    required String? existingId,
    required String name,
    required ProviderType type,
    required String baseUrl,
    required AuthMethod authMethod,
    required String authHeaderName,
    required String authHeaderValue,
    required String apiKey,
    required List<HttpHeader> customHeaders,
    String model = '',
    String endpoint = '',
    bool isEnabled = true,
    bool streamingEnabled = true,
    HttpMethod httpMethod = HttpMethod.post,
    String requestBodyTemplate = '',
    String responsePath = '',
  }) async {
    final trimmedBase = baseUrl.trim();
    // Light validation without network.
    final adapter = _adapters.forType(type);
    final probe = AIProvider(
      id: 'probe',
      name: name.trim().isEmpty ? 'Provider' : name.trim(),
      type: type,
      baseUrl: trimmedBase,
      authMethod: authMethod,
      customAuthHeaderName: authHeaderName.trim(),
      customAuthHeaderValue: authHeaderValue,
      customHeaders: customHeaders,
      model: model.trim(),
      endpoint: endpoint.trim(),
      isEnabled: isEnabled,
      streamingEnabled: streamingEnabled,
      httpMethod: httpMethod,
      requestBodyTemplate: requestBodyTemplate,
      responsePath: responsePath.trim(),
    );
    final adapterError = adapter.validateConfiguration(probe);
    if (adapterError != null) {
      return ProviderSaveOutcome(
          provider: probe, validationError: adapterError);
    }
    if (name.trim().isEmpty) {
      return const ProviderSaveOutcome(
          provider: AIProvider(
              id: '',
              name: '',
              type: ProviderType.openaiCompatible,
              baseUrl: '',
              authMethod: AuthMethod.bearerToken),
          validationError: 'Give this provider a name.');
    }

    final now = DateTime.now();
    final existing = existingId == null ? null : await _repo.findById(existingId);
    final provider = AIProvider(
      id: existingId ?? Ids.newId('prov'),
      name: name.trim(),
      type: type,
      baseUrl: trimmedBase,
      authMethod: authMethod,
      customAuthHeaderName: authHeaderName.trim(),
      customAuthHeaderValue: authHeaderValue,
      customHeaders: customHeaders,
      model: model.trim(),
      endpoint: endpoint.trim(),
      isEnabled: isEnabled,
      streamingEnabled: streamingEnabled,
      httpMethod: httpMethod,
      requestBodyTemplate: requestBodyTemplate,
      responsePath: responsePath.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _repo.upsert(provider);
    if (apiKey.trim().isNotEmpty) {
      await _tokens.writeKey(provider.id, apiKey.trim());
    }
    return ProviderSaveOutcome(provider: provider, validationError: null);
  }

  Future<void> updateKey(String providerId, String apiKey) async {
    if (apiKey.trim().isEmpty) return;
    await _tokens.writeKey(providerId, apiKey.trim());
  }

  Future<AIProvider> duplicate(String id, {String? newName}) async {
    final source = await _repo.findById(id);
    if (source == null) {
      throw StateError('Provider not found.');
    }
    final copy = await _repo.duplicate(source, newName: newName);
    final key = await _tokens.readKey(source.id);
    if (key != null) {
      await _tokens.writeKey(copy.id, key);
    }
    return copy;
  }

  Future<void> delete(String id) async {
    await _repo.delete(id);
    await _tokens.deleteKey(id);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _repo.setEnabled(id, enabled);
  }

  Future<void> rememberModel(String providerId, String model,
          {bool favorite = false}) =>
      _repo.rememberModel(providerId, model, favorite: favorite);

  Future<void> setModelFavorite(String providerId, String model, bool fav) =>
      _repo.setModelFavorite(providerId, model, fav);

  Future<List<String>> recentModels(String providerId) =>
      _repo.recentModels(providerId);

  Future<List<String>> favoriteModels(String providerId) =>
      _repo.favoriteModels(providerId);

  /// Lists models when the adapter supports it (OpenAI-compatible, Gemini).
  Future<List<String>> fetchModels(String providerId) async {
    final provider = await _repo.findById(providerId);
    if (provider == null) return const [];
    final adapter = _adapters.forType(provider.type);
    if (!adapter.capabilities.supportsModelListing) return const [];
    final key = await _tokens.readKey(providerId) ?? '';
    return adapter.listModels(provider: provider, apiKey: key);
  }

  /// Tests a provider draft that has not been persisted yet (wizard flow).
  Future<ConnectionTestResult> testDraft({
    required AIProvider draft,
    required String apiKey,
    bool inspectorEnabled = false,
  }) async {
    if (draft.baseUrl.trim().isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.configuration,
        message: 'Enter a base URL before testing.',
      );
    }
    if (apiKey.trim().isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.configuration,
        message: 'Enter an API key before testing.',
        tip: 'The tester needs the key to authenticate a real request.',
      );
    }
    final adapter = _adapters.forType(draft.type);
    final model = draft.model.trim();
    if (model.isEmpty && draft.type != ProviderType.custom) {
      throw const ApiException(
        kind: ApiErrorKind.configuration,
        message: 'Enter the model name before testing the connection.',
        tip: 'The test request must name a model the provider knows.',
      );
    }
    return adapter.testConnection(AiTurnRequest(
      provider: draft,
      apiKey: apiKey.trim(),
      messages: const [
        ChatMessage(
            id: 'test', role: ChatMessageRole.user, content: 'ping'),
      ],
      model: model,
      systemPrompt: '',
      streaming: false,
      inspectorEnabled: inspectorEnabled,
    ));
  }

  /// Safe connection probe for a persisted provider.
  Future<ConnectionTestResult> testConnection(String providerId,
      {bool inspectorEnabled = false}) async {
    final provider = await _repo.findById(providerId);
    if (provider == null) {
      throw const ApiException(
        kind: ApiErrorKind.configuration,
        message: 'Provider configuration was not found.',
      );
    }
    final key = await _tokens.readKey(providerId);
    if (key == null || key.isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.configuration,
        message: 'No API key is stored for this provider.',
        tip: 'Add the API key in provider settings before testing.',
      );
    }
    final adapter = _adapters.forType(provider.type);
    return adapter.testConnection(AiTurnRequest(
      provider: provider,
      apiKey: key,
      messages: const [
        ChatMessage(
            id: 'test',
            role: ChatMessageRole.user,
            content: 'Reply with the single word: ok'),
      ],
      model: provider.model.trim().isEmpty
          ? 'test-model'
          : provider.model.trim(),
      systemPrompt: '',
      streaming: false,
      inspectorEnabled: inspectorEnabled,
    ));
  }

  /// True if a streaming adapter exists for this provider.
  Future<bool> supportsStreaming(String providerId) async {
    final p = await _repo.findById(providerId);
    if (p == null) return false;
    return _adapters.forType(p.type).capabilities.supportsStreaming &&
        p.streamingEnabled;
  }

  CancelToken createCancelToken() => CancelToken();
}

/// Indirection so tests can inject adapters.
abstract interface class AdapterRegistryLookup {
  const AdapterRegistryLookup();
  AIProviderAdapter forType(ProviderType type);
  bool supports(ProviderType type);
}

class _RealRegistry implements AdapterRegistryLookup {
  const _RealRegistry();
  @override
  AIProviderAdapter forType(ProviderType type) => AdapterRegistry.forType(type);
  @override
  bool supports(ProviderType type) => AdapterRegistry.supports(type);
}
