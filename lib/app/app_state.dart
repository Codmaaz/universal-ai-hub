import 'package:flutter/foundation.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/provider.dart';
import '../../core/models/system_prompt.dart';
import '../../data/repositories/prompt_repository.dart';
import '../../data/repositories/provider_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/provider_service.dart';

/// Central in-memory application state.
///
/// Kept intentionally small — screens pull large data sets (conversations,
/// messages) through the repositories directly and refresh on navigation.
class AppStateController extends ChangeNotifier {
  AppStateController({
    required SettingsRepository settingsRepository,
    required ProviderRepository providerRepository,
    required PromptRepository promptRepository,
    required ProviderService providerService,
  })  : _settingsRepo = settingsRepository,
        _providersRepo = providerRepository,
        _promptsRepo = promptRepository,
        _providerService = providerService;

  final SettingsRepository _settingsRepo;
  final ProviderRepository _providersRepo;
  final PromptRepository _promptsRepo;
  final ProviderService _providerService;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  List<AIProvider> _providers = [];
  List<AIProvider> get providers => List.unmodifiable(_providers);

  List<SystemPrompt> _prompts = [];
  List<SystemPrompt> get prompts => List.unmodifiable(_prompts);

  bool _ready = false;
  bool get ready => _ready;

  /// Providers that may be used for a new chat.
  List<AIProvider> get usableProviders =>
      _providers.where((p) => p.isEnabled).toList();

  AIProvider? providerById(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Loads persisted state (called once at startup).
  Future<void> init() async {
    _settings = await _settingsRepo.load();
    await _promptsRepo.seedBuiltins();
    await refreshAll();
    _ready = true;
    notifyListeners();
  }

  Future<void> refreshProviders() async {
    _providers = await _providersRepo.listAll();
    notifyListeners();
  }

  Future<void> refreshPrompts() async {
    _prompts = await _promptsRepo.listAll();
    notifyListeners();
  }

  Future<void> refreshAll() async {
    _providers = await _providersRepo.listAll();
    _prompts = await _promptsRepo.listAll();
    notifyListeners();
  }

  // ---- Settings mutations --------------------------------------------------

  Future<void> updateSettings(AppSettings next) async {
    _settings = next;
    notifyListeners();
    await _settingsRepo.save(next);
  }

  ThemePref get themePref => _settings.themeMode;

  Future<void> setTheme(ThemePref theme) =>
      updateSettings(_settings.copyWith(themeMode: theme));

  Future<void> setRequestInspector(bool enabled) =>
      updateSettings(_settings.copyWith(requestInspectorEnabled: enabled));

  Future<void> setDiagnosticLogging(bool enabled) =>
      updateSettings(_settings.copyWith(diagnosticLogging: enabled));

  // ---- Provider convenience wrappers ----------------------------------------

  Future<void> removeProvider(String id) async {
    await _providerService.delete(id);
    await refreshProviders();
  }

  Future<void> toggleProvider(String id) async {
    final p = providerById(id);
    if (p == null) return;
    await _providerService.setEnabled(id, !p.isEnabled);
    await refreshProviders();
  }

  Future<AIProvider?> duplicateProvider(String id) async {
    final copy = await _providerService.duplicate(id);
    await refreshProviders();
    return copy;
  }

  // ---- Privacy: clear data --------------------------------------------------

  Future<void> clearProviderData() async {
    for (final p in _providers) {
      await _providerService.delete(p.id);
    }
    await refreshProviders();
  }

  /// Wipes everything except app appearance/network settings.
  Future<void> clearAllData() async {
    await clearProviderData();
    await _promptsRepo
        .listAll()
        .then((list) async => Future.wait(list.map((p) async {
              if (!p.isBuiltIn) await _promptsRepo.delete(p.id);
            })));
    await refreshPrompts();
  }

  Future<void> rememberLastUsed(String providerId, String model) async {
    _settings = _settings.copyWith(
      lastUsedProviderId: providerId,
      lastUsedModel: model,
    );
    await _settingsRepo.save(_settings);
  }

  Future<void> forgetLastUsed() =>
      updateSettings(_settings.copyWith(clearLastUsed: true));
}
