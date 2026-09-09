import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/models/app_settings.dart';

/// Persists application settings as a small JSON file in the app documents
/// directory. Settings never contain secrets.
class SettingsRepository {
  const SettingsRepository();

  File _file(Directory dir) => File('${dir.path}/app_settings.json');

  Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return _file(dir);
  }

  Future<AppSettings> load() async {
    try {
      final f = await _settingsFile();
      if (!await f.exists()) return const AppSettings();
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return AppSettings.fromJson(json);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    try {
      final f = await _settingsFile();
      await f.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Best effort only.
    }
  }

  Future<void> wipe() async {
    try {
      final f = await _settingsFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
