import 'package:flutter/widgets.dart';

import '../app/app_state.dart';
import '../core/security/secure_token_store.dart';
import '../data/repositories/conversation_repository.dart';
import '../data/repositories/prompt_repository.dart';
import '../data/repositories/provider_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/chat_service.dart';
import '../data/services/provider_service.dart';
import '../data/services/transfer_service.dart';

/// Bundles every application service/repository. Constructed once in [main]
/// and exposed through an [AppScope] inherited widget so screens and
/// controllers do not need a DI framework.
class AppServices {
  AppServices._();

  static AppServices create() {
    final s = AppServices._();
    s.secureStorage = SecureTokenStore();
    s.providerRepository = const ProviderRepository();
    s.conversationRepository = const ConversationRepository();
    s.promptRepository = const PromptRepository();
    s.settingsRepository = const SettingsRepository();
    s.providerService = ProviderService(
      repository: s.providerRepository,
      tokenStore: s.secureStorage,
    );
    s.chatService = ChatService(providerService: s.providerService);
    s.transferService = TransferService(
      providerRepository: s.providerRepository,
      promptRepository: s.promptRepository,
    );
    s.state = AppStateController(
      settingsRepository: s.settingsRepository,
      providerRepository: s.providerRepository,
      promptRepository: s.promptRepository,
      providerService: s.providerService,
    );
    return s;
  }

  late final SecureTokenStore secureStorage;
  late final ProviderRepository providerRepository;
  late final ConversationRepository conversationRepository;
  late final PromptRepository promptRepository;
  late final SettingsRepository settingsRepository;
  late final ProviderService providerService;
  late final ChatService chatService;
  late final TransferService transferService;
  late final AppStateController state;

  Future<void> init() => state.init();
}

/// Inherited accessor to [AppServices].
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above this context');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      services != oldWidget.services;
}
