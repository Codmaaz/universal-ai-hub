import 'package:dio/dio.dart';

import '../../adapters/ai_provider_adapter.dart';
import '../../adapters/adapter_registry.dart';
import '../../core/models/generation_settings.dart';
import '../../core/models/provider.dart';
import '../../core/models/types.dart';
import '../../core/network/api_exception.dart';
import '../../core/security/secure_token_store.dart';
import 'provider_service.dart';

/// Options describing one AI send for the [ChatService].
class SendTurnParams {
  const SendTurnParams({
    required this.provider,
    required this.messages,
    required this.model,
    this.systemPrompt = '',
    this.settings = const GenerationSettings(),
    required this.streaming,
    this.cancelToken,
    this.onDelta,
    this.inspectorEnabled = false,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 600),
    this.retryCount = 1,
  });

  final AIProvider provider;
  final List<ChatMessage> messages;
  final String model;
  final String systemPrompt;
  final GenerationSettings settings;
  final bool streaming;
  final CancelToken? cancelToken;
  final void Function(String partial)? onDelta;
  final bool inspectorEnabled;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  /// Retries only transient transport failures that occur before any
  /// streamed content has been received.
  final int retryCount;
}

/// Orchestrates one AI turn: fetch the secret, resolve the adapter, stream or
/// complete, and keep everything sanitized.
class ChatService {
  ChatService({
    ProviderService? providerService,
    SecureTokenStore? tokenStore,
  })  : _providerService = providerService ?? ProviderService(),
        _tokens = tokenStore ?? SecureTokenStore();

  final ProviderService _providerService;
  final SecureTokenStore _tokens;

  Future<String?> readKey(String providerId) => _tokens.readKey(providerId);

  Future<bool> hasValidConfiguration(String providerId) async {
    final p = await _providerService.findById(providerId);
    if (p == null) return false;
    if (!p.isEnabled) return false;
    return _tokens.hasKey(providerId);
  }

  /// Executes the turn. [onDelta] fires with each incremental token when
  /// streaming. Returns the assembled assistant text.
  Future<AiTurnResult> sendTurn(SendTurnParams params) async {
    final adapter = AdapterRegistry.forType(params.provider.type);
    final key = await _tokens.readKey(params.provider.id);
    if (key == null || key.isEmpty) {
      throw const ApiException(
        kind: ApiErrorKind.configuration,
        message: 'No API key is stored for this provider.',
        tip: 'Open the provider and add your API key, then try again.',
      );
    }
    var attempt = 0;
    var streamedAny = false;
    final maxRetries = params.retryCount.clamp(0, 3);

    while (true) {
      try {
        return await adapter.send(AiTurnRequest(
          provider: params.provider,
          apiKey: key,
          messages: params.messages,
          model: params.model,
          systemPrompt: params.systemPrompt,
          settings: params.settings,
          streaming: params.streaming,
          cancelToken: params.cancelToken,
          onDelta: (delta) {
            streamedAny = true;
            params.onDelta?.call(delta);
          },
          inspectorEnabled: params.inspectorEnabled,
          connectTimeout: params.connectTimeout,
          receiveTimeout: params.receiveTimeout,
        ));
      } on ApiException catch (e) {
        final transient = e.kind == ApiErrorKind.network ||
            e.kind == ApiErrorKind.timeout;
        if (!transient || streamedAny || attempt >= maxRetries ||
            params.cancelToken?.isCancelled == true) {
          if (streamedAny && e.partialContent == null) {
            throw e.copyWith(partialContent: '');
          }
          rethrow;
        }
        attempt++;
        await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
      }
    }
  }
}
