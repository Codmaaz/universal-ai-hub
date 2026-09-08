import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/secret_masker.dart';

/// Abstraction over the platform keychain / Android Keystore via
/// flutter_secure_storage. The only place API keys live on device.
class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;

  static String _keyFor(String providerId) => 'uaih_api_key_$providerId';

  /// Encrypted read of the API key for [providerId].
  Future<String?> readKey(String providerId) async {
    try {
      return await _storage.read(key: _keyFor(providerId));
    } catch (e) {
      // Storage failures must never crash the app.
      return null;
    }
  }

  Future<void> writeKey(String providerId, String apiKey) async {
    await _storage.write(key: _keyFor(providerId), value: apiKey);
  }

  /// Deletes the stored secret for [providerId] (no exception if absent).
  Future<void> deleteKey(String providerId) async {
    try {
      await _storage.delete(key: _keyFor(providerId));
    } catch (_) {}
  }

  /// Bulk wipe (used by "clear all app data").
  Future<void> wipeAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }

  /// Whether a secret exists (used to warn the user when a key is missing).
  Future<bool> hasKey(String providerId) async {
    final v = await readKey(providerId);
    return v != null && v.isNotEmpty;
  }

  /// Diagnostic helper — counts configured secrets only.
  Future<int> countConfiguredKeys(Iterable<String> providerIds) async {
    var n = 0;
    for (final id in providerIds) {
      if (await hasKey(id)) n++;
    }
    return n;
  }
}

/// Whitelisted, safe log sink. Records never contain secrets by design — use
/// [sanitize] on any free-form payload first.
abstract final class AppLog {
  static bool _enabled = false;

  static void setEnabled(bool value) => _enabled = value;

  static void info(String message) {
    if (_enabled) {
      // ignore: avoid_print
      print('[uaih] $message');
    }
  }

  static void warn(String message) {
    // Warnings go out regardless; payloads must already be sanitized.
    // ignore: avoid_print
    print('[uaih:warning] $message');
  }

  /// Safe call-site: masks [payload] with optional [knownSecret] knowledge.
  static String sanitize(String payload, {String? knownSecret}) =>
      SecretMasker.scrubSecrets(payload, knownSecret: knownSecret);
}
