/// App-wide constants.
library;

/// Central registry of small configuration constants.
abstract final class AppConstants {
  /// Human-friendly application name.
  static const String appName = 'Universal AI Hub';

  /// App db/file version — bump when schema or key formats change.
  static const int schemaVersion = 2;

  static const String defaultSystemPrompt =
      'You are a helpful, friendly assistant. Keep answers clear, '
      'accurate and well structured.';
}

/// Timeouts used by the network layer (overridable in settings).
abstract final class DefaultNetworkSettings {
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 120);
  static const int maxRetries = 1; // Only transient errors are retried once.
}
