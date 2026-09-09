/// App settings persisted as a local JSON file (no secrets ever).
class AppSettings {
  const AppSettings({
    this.themeMode = ThemePref.system,
    this.fontScale = 1.0,
    this.markdownRendering = true,
    this.streamingEnabled = true,
    this.connectTimeoutSeconds = 30,
    this.receiveTimeoutSeconds = 120,
    this.retryCount = 1,
    this.requestInspectorEnabled = false,
    this.diagnosticLogging = false,
    this.clearSecretsOnExport = true,
    this.lastUsedProviderId,
    this.lastUsedModel,
  });

  final ThemePref themeMode;
  final double fontScale;
  final bool markdownRendering;
  final bool streamingEnabled;
  final int connectTimeoutSeconds;
  final int receiveTimeoutSeconds;
  final int retryCount;
  final bool requestInspectorEnabled;
  final bool diagnosticLogging;

  /// Future-proof flag documenting the default privacy posture for exports.
  final bool clearSecretsOnExport;

  final String? lastUsedProviderId;
  final String? lastUsedModel;

  AppSettings copyWith({
    ThemePref? themeMode,
    double? fontScale,
    bool? markdownRendering,
    bool? streamingEnabled,
    int? connectTimeoutSeconds,
    int? receiveTimeoutSeconds,
    int? retryCount,
    bool? requestInspectorEnabled,
    bool? diagnosticLogging,
    bool? clearSecretsOnExport,
    String? lastUsedProviderId,
    String? lastUsedModel,
    bool clearLastUsed = false,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      markdownRendering: markdownRendering ?? this.markdownRendering,
      streamingEnabled: streamingEnabled ?? this.streamingEnabled,
      connectTimeoutSeconds: connectTimeoutSeconds ?? this.connectTimeoutSeconds,
      receiveTimeoutSeconds: receiveTimeoutSeconds ?? this.receiveTimeoutSeconds,
      retryCount: retryCount ?? this.retryCount,
      requestInspectorEnabled: requestInspectorEnabled ?? this.requestInspectorEnabled,
      diagnosticLogging: diagnosticLogging ?? this.diagnosticLogging,
      clearSecretsOnExport: clearSecretsOnExport ?? this.clearSecretsOnExport,
      lastUsedProviderId: clearLastUsed ? null : (lastUsedProviderId ?? this.lastUsedProviderId),
      lastUsedModel: clearLastUsed ? null : (lastUsedModel ?? this.lastUsedModel),
    );
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'fontScale': fontScale,
        'markdownRendering': markdownRendering,
        'streamingEnabled': streamingEnabled,
        'connectTimeoutSeconds': connectTimeoutSeconds,
        'receiveTimeoutSeconds': receiveTimeoutSeconds,
        'retryCount': retryCount,
        'requestInspectorEnabled': requestInspectorEnabled,
        'diagnosticLogging': diagnosticLogging,
        'clearSecretsOnExport': clearSecretsOnExport,
        'lastUsedProviderId': lastUsedProviderId,
        'lastUsedModel': lastUsedModel,
      };

  static AppSettings fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode: ThemePrefX.fromStorage(json['themeMode'] as String?),
        fontScale: ((json['fontScale'] as num?) ?? 1.0).toDouble(),
        markdownRendering: (json['markdownRendering'] as bool?) ?? true,
        streamingEnabled: (json['streamingEnabled'] as bool?) ?? true,
        connectTimeoutSeconds: (json['connectTimeoutSeconds'] as num?)?.toInt() ?? 30,
        receiveTimeoutSeconds: (json['receiveTimeoutSeconds'] as num?)?.toInt() ?? 120,
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 1,
        requestInspectorEnabled: (json['requestInspectorEnabled'] as bool?) ?? false,
        diagnosticLogging: (json['diagnosticLogging'] as bool?) ?? false,
        clearSecretsOnExport: (json['clearSecretsOnExport'] as bool?) ?? true,
        lastUsedProviderId: json['lastUsedProviderId'] as String?,
        lastUsedModel: json['lastUsedModel'] as String?,
      );
}

/// Appearance preference tri-state.
enum ThemePref { light, dark, system }

extension ThemePrefX on ThemePref {
  String get label {
    switch (this) {
      case ThemePref.light:
        return 'Light';
      case ThemePref.dark:
        return 'Dark';
      case ThemePref.system:
        return 'System';
    }
  }

  static ThemePref fromStorage(String? value) {
    return ThemePref.values.firstWhere((t) => t.name == value,
        orElse: () => ThemePref.system);
  }
}
