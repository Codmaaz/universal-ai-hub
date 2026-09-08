import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/app_settings.dart';
import '../../core/models/conversation.dart';
import '../../core/models/provider.dart';
import '../../core/models/system_prompt.dart';
import '../../core/models/types.dart';
import '../../core/utils/export_formatters.dart';
import '../../core/utils/ids.dart';
import '../../core/utils/secret_masker.dart';
import '../repositories/provider_repository.dart';
import '../repositories/prompt_repository.dart';

/// Result of importing provider configs.
class ImportResult {
  const ImportResult({
    required this.importedProviders,
    required this.skipped,
    this.message = '',
  });
  final int importedProviders;
  final int skipped;
  final String message;
}

/// Import / export of user data. By design exported provider configs do NOT
/// carry API keys (see [exportProvidersAsJson]) and any imported payload is
/// scrubbed for secret-like strings before it reaches storage.
class TransferService {
  TransferService({
    ProviderRepository? providerRepository,
    PromptRepository? promptRepository,
  })  : _providers = providerRepository ?? const ProviderRepository(),
        _prompts = promptRepository ?? const PromptRepository();

  final ProviderRepository _providers;
  final PromptRepository _prompts;

  // ---- Conversation export -------------------------------------------------

  /// Writes a conversation file into the app's temp folder and opens the OS
  /// share sheet. Returns the file path shared (or null when sharing failed).
  Future<String?> shareConversation(
    ChatConversation conversation,
    List<ChatMessage> messages, {
    required String format,
  }) async {
    final (content, ext, mime) = switch (format) {
      'md' => (
          ExportFormatters.conversationToMarkdown(conversation, messages),
          'md',
          'text/markdown'
        ),
      'json' => (
          ExportFormatters.conversationToJson(conversation, messages),
          'json',
          'application/json'
        ),
      _ => (
          ExportFormatters.conversationToText(conversation, messages),
          'txt',
          'text/plain'
        ),
    };
    final dir = await getTemporaryDirectory();
    final safeName =
        conversation.title.replaceAll(RegExp(r'[^\w\- ]+'), '_').trim();
    final file = File(
        p.join(dir.path, '${safeName.isEmpty ? 'chat' : safeName}.$ext'));
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mime)]),
    );
    return file.path;
  }

  // ---- Provider export (secrets never included) -----------------------------

  Future<String> exportProvidersAsJson() async {
    final providers = await _providers.listAll();
    final items = <Map<String, dynamic>>[];
    for (final p in providers) {
      final json = p.toJson();
      // Belt-and-braces: drop anything that looks like a secret.
      json.remove('apiKey');
      json.remove('api_key');
      if (json['customAuthHeaderValue'] is String) {
        json['customAuthHeaderValue'] =
            SecretMasker.scrubSecrets(json['customAuthHeaderValue'] as String);
      }
      if (json['customHeaders'] is List) {
        json['customHeaders'] = (json['customHeaders'] as List).map((h) {
          final map = Map<String, dynamic>.from(h as Map);
          map['value'] = SecretMasker.scrubSecrets(map['value']?.toString() ?? '');
          return map;
        }).toList();
      }
      items.add(json);
    }
    return jsonEncode({
      'format': 'universal_ai_hub_providers',
      'version': 1,
      'apiKeysIncluded': false,
      'note': 'API keys are intentionally not included. Re-enter keys after '
          'import.',
      'providers': items,
    });
  }

  Future<void> shareProviders() async {
    final content = await exportProvidersAsJson();
    await _shareText('providers-export.json', content, 'application/json');
  }

  // ---- System prompts export -----------------------------------------------

  Future<void> sharePrompts() async {
    final prompts = await _prompts.listAll();
    final content = jsonEncode({
      'format': 'universal_ai_hub_prompts',
      'version': 1,
      'prompts': [
        for (final pr in prompts)
          {'title': pr.title, 'content': pr.content, 'isFavorite': pr.isFavorite}
      ],
    });
    await _shareText('system-prompts-export.json', content, 'application/json');
  }

  // ---- Settings export ------------------------------------------------------

  Future<void> shareSettings(AppSettings settings) async {
    final json = settings.toJson();
    json['format'] = 'universal_ai_hub_settings';
    json['version'] = 1;
    await _shareText('settings-export.json', jsonEncode(json), 'application/json');
  }

  Future<void> _shareText(String name, String content, String mime) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mime)]),
    );
  }

  // ---- Provider import ------------------------------------------------------

  Future<ImportResult> importProvidersFromJsonFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return const ImportResult(importedProviders: 0, skipped: 0);
    }
    final bytes = picked.files.single.bytes;
    final path = picked.files.single.path;
    String raw;
    if (bytes != null) {
      raw = utf8.decode(bytes);
    } else if (path != null) {
      raw = await File(path).readAsString();
    } else {
      return const ImportResult(
          importedProviders: 0, skipped: 0, message: 'Could not read file.');
    }
    return importProvidersFromJson(raw);
  }

  Future<ImportResult> importProvidersFromJson(String raw) async {
    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(raw);
      root = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return const ImportResult(
          importedProviders: 0, skipped: 0, message: 'The file is not valid JSON.');
    }

    final List<dynamic> rawItems;
    if (root['providers'] is List) {
      rawItems = root['providers'] as List;
    } else if (root.isNotEmpty &&
        (root.containsKey('name') || root.containsKey('baseUrl'))) {
      rawItems = [root]; // a single provider object was pasted
    } else {
      rawItems = const [];
    }

    var imported = 0;
    var skipped = 0;
    for (final item in rawItems) {
      if (item is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      try {
        // Scrub accidental secrets from custom header values.
        final headersRaw = item['customHeaders'];
        if (headersRaw is List) {
          item['customHeaders'] = headersRaw.map((h) {
            final map = Map<String, dynamic>.from(h as Map);
            if (map['value'] is String) {
              map['value'] = _scrubKeyLike(map['value'] as String);
            }
            return map;
          }).toList();
        }
        if (item['customAuthHeaderValue'] is String) {
          item['customAuthHeaderValue'] =
              _scrubKeyLike(item['customAuthHeaderValue'] as String);
        }
        item['id'] = Ids.newId('prov');
        item.remove('apiKey');
        item.remove('api_key');
        item.remove('createdAt');
        item.remove('updatedAt');
        final parsed = AIProvider.fromJson(item);
        if (parsed.baseUrl.trim().isEmpty) {
          skipped++;
          continue;
        }
        final provider = parsed.name.trim().isEmpty
            ? parsed.copyWith(name: 'Imported provider')
            : parsed;
        await _providers.upsert(provider);
        imported++;
      } catch (_) {
        skipped++;
      }
    }
    return ImportResult(
      importedProviders: imported,
      skipped: skipped,
      message: imported == 0
          ? 'Nothing importable was found.'
          : 'Imported $imported provider(s). API keys were not included — '
              'enter them in each provider to enable requests.',
    );
  }

  /// Removes secret-looking substrings (e.g. sk-…, Bearer …) from imported
  /// free text so keys cannot sneak in through header templates.
  static String _scrubKeyLike(String value) {
    var out = value;
    out = out.replaceAllMapped(
      RegExp('(Bearer\\s+)?(sk-[A-Za-z0-9_\\-]{8,})'),
      (m) => (m.group(1) ?? '') + SecretMasker.mask(m.group(2) ?? ''),
    );
    out = out.replaceAllMapped(
      RegExp('[A-Za-z0-9_\\-]{32,}'),
      (m) => SecretMasker.mask(m.group(0) ?? ''),
    );
    return out;
  }

  /// Picks a JSON file and imports system prompts from it.
  Future<ImportResult> importPromptsFromPickedFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return const ImportResult(importedProviders: 0, skipped: 0);
    }
    final bytes = picked.files.single.bytes;
    final path = picked.files.single.path;
    String raw;
    if (bytes != null) {
      raw = utf8.decode(bytes);
    } else if (path != null) {
      raw = await File(path).readAsString();
    } else {
      return const ImportResult(
          importedProviders: 0, skipped: 0, message: 'Could not read file.');
    }
    return importPromptsFromJson(raw);
  }

  Future<ImportResult> importPromptsFromJson(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      final root = decoded is Map<String, dynamic> ? decoded : null;
      final list = root?['prompts'];
      if (list is! List || list.isEmpty) {
        return const ImportResult(
            importedProviders: 0, skipped: 0, message: 'No prompts found.');
      }
      var imported = 0;
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          await _prompts.create(
            title: (item['title'] ?? 'Imported prompt').toString(),
            content: (item['content'] ?? '').toString(),
          );
          imported++;
        }
      }
      return ImportResult(
          importedProviders: imported,
          skipped: 0,
          message: 'Imported $imported system prompt(s).');
    } catch (_) {
      return const ImportResult(
          importedProviders: 0,
          skipped: 0,
          message: 'The file is not valid JSON.');
    }
  }
}
