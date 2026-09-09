import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/media_item.dart';
import '../../core/models/provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/app_dio.dart';
import '../../core/network/auth_headers.dart';
import '../../core/security/secure_token_store.dart';
import '../../core/utils/ids.dart';
import '../../adapters/json_path.dart';
import '../repositories/media_repository.dart';
import 'provider_service.dart';

class _ImageOutput {
  const _ImageOutput({this.url, this.base64, this.extension = 'png'});
  final String? url;
  final String? base64;
  final String extension;
}

/// Multimodal generation service. It intentionally keeps provider-specific
/// endpoint details configurable: chat compatibility does not imply image or
/// video compatibility.
class MediaService {
  MediaService({required this.providerService, MediaRepository? repository, SecureTokenStore? tokenStore})
      : _repo = repository ?? const MediaRepository(),
        _tokens = tokenStore ?? SecureTokenStore();

  final ProviderService providerService;
  final MediaRepository _repo;
  final SecureTokenStore _tokens;

  Future<List<MediaItem>> history({MediaKind? kind}) => _repo.list(kind: kind);
  Future<void> delete(String id) => _repo.delete(id);

  Future<MediaItem> generateImage({
    required String providerId,
    required String model,
    required String prompt,
    String size = '1024x1024',
    int n = 1,
    String? negativePrompt,
  }) async {
    final provider = await _provider(providerId);
    final item = MediaItem(
      id: Ids.newId('img'), kind: MediaKind.image, providerId: provider.id,
      providerName: provider.name, model: model, prompt: prompt,
      negativePrompt: negativePrompt ?? '', status: MediaStatus.processing,
      createdAt: DateTime.now(), updatedAt: DateTime.now(),
      metadata: {'size': size, 'n': n},
    );
    await _repo.upsert(item);
    try {
      final isUniversal = provider.type == ProviderType.universalHttp;
      final apiKey = await _tokens.readKey(provider.id) ?? '';
      final configuredEndpoint = isUniversal
          ? provider.capabilityEndpoints['image_generation']
          : provider.type == ProviderType.custom ? provider.endpoint : null;
      final endpoint = (configuredEndpoint ?? '').trim().isNotEmpty
          ? configuredEndpoint!.trim()
          : '/images/generations';
      final configuredTemplate = isUniversal
          ? provider.capabilityRequestTemplates['image_generation']
          : provider.type == ProviderType.custom ? provider.requestBodyTemplate : null;
      final body = configuredTemplate != null && configuredTemplate.trim().isNotEmpty
          ? _renderMediaTemplate(configuredTemplate, model: model, prompt: prompt, size: size, n: n, negativePrompt: negativePrompt ?? '', apiKey: apiKey)
          : <String, dynamic>{
              'model': model,
              'prompt': prompt,
              'size': size,
              'n': n,
              if ((negativePrompt ?? '').trim().isNotEmpty)
                'negative_prompt': negativePrompt!.trim(),
            };
      final data = await _requestJson(provider, endpoint, body, method: isUniversal ? _effectiveUniversalMethod(provider, 'image_generation', 'POST') : 'POST');
      var outputs = _extractImageOutputs(data);
      if (outputs.isEmpty && (isUniversal || provider.type == ProviderType.custom)) {
        final path = isUniversal
            ? (provider.capabilityResponsePaths['image_generation'] ?? '')
            : provider.responsePath;
        if (path.trim().isNotEmpty) {
          final mapped = resolveJsonPath(path, data);
          outputs = _extractImageOutputs(mapped);
        }
      }
      if (outputs.isEmpty) {
        throw ApiException(
          kind: ApiErrorKind.parseError,
          message: 'The provider returned no usable image output.',
          tip: 'The API may use a different image response format. OpenAI-compatible URLs and b64_json responses are supported.',
          sanitizedBody: _safeResponsePreview(data),
        );
      }

      String? remoteUrl;
      String? localPath;
      final urls = <String>[];
      final localFiles = <String>[];
      final mediaDir = await _mediaDirectory();
      for (var i = 0; i < outputs.length; i++) {
        final output = outputs[i];
        if (output.url != null && output.url!.isNotEmpty) {
          urls.add(output.url!);
          remoteUrl ??= output.url;
        }
        if (output.base64 != null && output.base64!.isNotEmpty) {
          try {
            final bytes = _decodeBase64Image(output.base64!);
            final target = p.join(mediaDir.path, '${item.id}_$i.${output.extension}');
            await File(target).writeAsBytes(bytes, flush: true);
            localFiles.add(target);
            localPath ??= target;
          } on FormatException catch (e) {
            throw ApiException(
              kind: ApiErrorKind.parseError,
              message: 'The provider returned invalid base64 image data.',
              tip: 'Try URL output if the provider supports it, or check the image model response format.',
              sanitizedBody: e.message,
            );
          }
        }
      }

      final done = item.copyWith(
        status: MediaStatus.completed,
        remoteUrl: remoteUrl,
        localPath: localPath,
        metadata: {
          ...item.metadata,
          'urls': urls,
          'local_files': localFiles,
          'output_count': outputs.length,
        },
        updatedAt: DateTime.now(),
      );
      await _repo.upsert(done);
      return done;
    } catch (e) {
      await _repo.upsert(item.copyWith(status: MediaStatus.failed, error: e.toString(), updatedAt: DateTime.now()));
      rethrow;
    }
  }

  /// Starts a video request. If [sourceFilePath] is provided, the request is
  /// sent as multipart/form-data with field name `input_file`, which works for
  /// generic upload endpoints. Providers with a different field name should
  /// expose a custom adapter in a later provider-specific integration.
  Future<MediaItem> startVideo({
    required String providerId, required String model, required String prompt,
    String endpoint = '/videos', String? sourceFilePath, String? aspectRatio,
    int? durationSeconds,
  }) async {
    final provider = await _provider(providerId);
    final item = MediaItem(
      id: Ids.newId('vid'), kind: MediaKind.video, providerId: provider.id,
      providerName: provider.name, model: model, prompt: prompt,
      sourceFilePath: sourceFilePath, status: MediaStatus.processing,
      createdAt: DateTime.now(), updatedAt: DateTime.now(),
      metadata: {'endpoint': endpoint, if (aspectRatio != null) 'aspect_ratio': aspectRatio,
        if (durationSeconds != null) 'duration': durationSeconds},
    );
    await _repo.upsert(item);
    try {
      final isUniversal = provider.type == ProviderType.universalHttp;
      final apiKey = await _tokens.readKey(provider.id) ?? '';
      final effectiveEndpoint = isUniversal
          ? (provider.capabilityEndpoints['video_generation'] ?? endpoint)
          : endpoint;
      final configuredTemplate = isUniversal ? provider.capabilityRequestTemplates['video_generation'] : null;
      final fields = <String, dynamic>{'model': model, 'prompt': prompt,
        if (aspectRatio != null) 'aspect_ratio': aspectRatio,
        if (durationSeconds != null) 'duration': durationSeconds};
      final data = configuredTemplate != null && configuredTemplate.trim().isNotEmpty
          ? await _requestJson(provider, effectiveEndpoint, _renderMediaTemplate(configuredTemplate, model: model, prompt: prompt, aspectRatio: aspectRatio ?? '', duration: durationSeconds?.toString() ?? '', apiKey: apiKey), method: _effectiveUniversalMethod(provider, 'video_generation', 'POST'))
          : sourceFilePath == null
              ? await _requestJson(provider, effectiveEndpoint, fields, method: _effectiveUniversalMethod(provider, 'video_generation', 'POST'))
              : await _postMultipart(provider, effectiveEndpoint, fields, sourceFilePath);
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      var urls = _extractUrls(map);
      if (isUniversal && urls.isEmpty) {
        final path = provider.capabilityResponsePaths['video_generation'] ?? '';
        if (path.trim().isNotEmpty) urls = _extractUrls(resolveJsonPath(path, data));
      }
      final job = _firstString(map, const ['id', 'job_id', 'task_id', 'request_id']);
      final out = item.copyWith(
        status: urls.isNotEmpty ? MediaStatus.completed : MediaStatus.queued,
        remoteUrl: urls.isEmpty ? null : urls.first, jobId: job,
        metadata: {...item.metadata, 'response': map, if (urls.isNotEmpty) 'urls': urls},
        updatedAt: DateTime.now(),
      );
      await _repo.upsert(out);
      return out;
    } catch (e) {
      await _repo.upsert(item.copyWith(status: MediaStatus.failed, error: e.toString(), updatedAt: DateTime.now()));
      rethrow;
    }
  }

  /// Poll a provider-specific status endpoint. Use a path such as
  /// `/videos/{id}`; `{id}` is replaced with the returned job id.
  Future<MediaItem> pollVideo(MediaItem item, {required String statusEndpoint}) async {
    if (item.jobId == null || item.jobId!.isEmpty) return item;
    final provider = await _provider(item.providerId);
    final endpoint = statusEndpoint.replaceAll('{id}', item.jobId!);
    try {
      final data = await _get(provider, endpoint);
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final urls = _extractUrls(map);
      final raw = (_firstString(map, const ['status', 'state']) ?? '').toLowerCase();
      final failed = raw.contains('fail') || raw.contains('error') || raw.contains('cancel');
      final done = urls.isNotEmpty || raw.contains('complete') || raw.contains('succeed') || raw == 'done';
      final next = item.copyWith(
        status: failed ? MediaStatus.failed : (done ? MediaStatus.completed : MediaStatus.processing),
        remoteUrl: urls.isEmpty ? null : urls.first,
        error: failed ? (_firstString(map, const ['error', 'message']) ?? 'Video generation failed.') : null,
        metadata: {...item.metadata, 'last_status': map, if (urls.isNotEmpty) 'urls': urls},
        updatedAt: DateTime.now(),
      );
      await _repo.upsert(next);
      return next;
    } catch (e) {
      final failed = item.copyWith(status: MediaStatus.failed, error: e.toString(), updatedAt: DateTime.now());
      await _repo.upsert(failed);
      return failed;
    }
  }

  /// Downloads a completed remote result into the app's documents directory.
  /// Android gallery export is deliberately separate because Play policy and
  /// Android media permissions vary by API level.
  Future<MediaItem> download(MediaItem item) async {
    if (item.localPath != null && await File(item.localPath!).exists()) return item;
    final url = item.remoteUrl;
    if (url == null || url.isEmpty) throw const ApiException(kind: ApiErrorKind.configuration, message: 'No downloadable output is available.');
    final mediaDir = await _mediaDirectory();
    final ext = _extensionFromUrl(url, item.kind == MediaKind.video ? 'mp4' : 'png');
    final target = p.join(mediaDir.path, '${item.id}.$ext');
    final dio = AppDio.create(receiveTimeout: const Duration(minutes: 10));
    await dio.download(url, target, onReceiveProgress: (_, __) {});
    final updated = item.copyWith(localPath: target, updatedAt: DateTime.now());
    await _repo.upsert(updated);
    return updated;
  }

  Future<AIProvider> _provider(String id) async {
    final p = await providerService.findById(id);
    if (p == null) throw const ApiException(kind: ApiErrorKind.configuration, message: 'Select a provider first.');
    return p;
  }

  Future<dynamic> _postJson(AIProvider pvd, String endpoint, Map<String, dynamic> body) =>
      _requestJson(pvd, endpoint, body, method: 'POST');

  Future<dynamic> _requestJson(AIProvider pvd, String endpoint, Map<String, dynamic> body, {required String method}) async {
    final auth = await _auth(pvd);
    final dio = AppDio.create(receiveTimeout: const Duration(minutes: 10));
    final options = Options(headers: {...auth.headers, 'Content-Type': 'application/json'});
    try {
      final url = _url(pvd, endpoint);
      final m = method.toUpperCase();
      late Response<dynamic> r;
      switch (m) {
        case 'GET': r = await dio.get(url, queryParameters: {...auth.queryParameters, ...body.map((k,v) => MapEntry(k, v.toString()))}, options: options); break;
        case 'PUT': r = await dio.put(url, data: body, queryParameters: auth.queryParameters, options: options); break;
        case 'PATCH': r = await dio.patch(url, data: body, queryParameters: auth.queryParameters, options: options); break;
        case 'DELETE': r = await dio.delete(url, data: body, queryParameters: auth.queryParameters, options: options); break;
        default: r = await dio.post(url, data: body, queryParameters: auth.queryParameters, options: options);
      }
      return r.data;
    } on DioException catch (e) { throw ApiException.fromDio(e, providerName: pvd.name); }
  }

  Future<dynamic> _postMultipart(AIProvider pvd, String endpoint, Map<String, dynamic> fields, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw const ApiException(kind: ApiErrorKind.configuration, message: 'Selected file no longer exists.');
    final auth = await _auth(pvd);
    final form = FormData.fromMap({...fields, 'input_file': await MultipartFile.fromFile(filePath, filename: p.basename(filePath))});
    final dio = AppDio.create(receiveTimeout: const Duration(minutes: 10));
    try {
      final r = await dio.post(_url(pvd, endpoint), data: form,
        options: Options(headers: auth.headers), queryParameters: auth.queryParameters);
      return r.data;
    } on DioException catch (e) { throw ApiException.fromDio(e, providerName: pvd.name); }
  }

  Future<dynamic> _get(AIProvider pvd, String endpoint) async {
    final auth = await _auth(pvd);
    final dio = AppDio.create(receiveTimeout: const Duration(minutes: 2));
    try {
      final r = await dio.get(_url(pvd, endpoint), options: Options(headers: auth.headers), queryParameters: auth.queryParameters);
      return r.data;
    } on DioException catch (e) { throw ApiException.fromDio(e, providerName: pvd.name); }
  }

  Future<AuthDecoration> _auth(AIProvider pvd) async => AuthHeaderBuilder.build(provider: pvd, apiKey: await _tokens.readKey(pvd.id) ?? '');
  String _url(AIProvider pvd, String endpoint) {
    final raw = endpoint.trim();
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return raw;
    return '${pvd.baseUrl.replaceAll(RegExp(r'/+$'), '')}/${raw.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Future<Directory> _mediaDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'generated_media'));
    if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
    return mediaDir;
  }

  String _effectiveUniversalEndpoint(AIProvider provider, String capability, String fallback) =>
      (provider.capabilityEndpoints[capability] ?? fallback).trim();

  String _effectiveUniversalMethod(AIProvider provider, String capability, String fallback) =>
      (provider.capabilityMethods[capability] ?? fallback).toUpperCase();

  String _stripDataUri(String value) {
    final comma = value.indexOf(',');
    if (value.startsWith('data:') && comma >= 0) return value.substring(comma + 1);
    return value;
  }

  String _safeResponsePreview(dynamic data) {
    try {
      final text = data is String ? data : jsonEncode(data);
      return text.length <= 1200 ? text : '${text.substring(0, 1200)}…';
    } catch (_) {
      return 'Response could not be previewed.';
    }
  }

  List<_ImageOutput> _extractImageOutputs(dynamic data) {
    final out = <_ImageOutput>[];
    final seen = <String>{};

    String extensionForMime(String? mime) {
      final m = (mime ?? '').toLowerCase();
      if (m.contains('jpeg') || m.contains('jpg')) return 'jpg';
      if (m.contains('webp')) return 'webp';
      if (m.contains('gif')) return 'gif';
      return 'png';
    }

    void add(dynamic value) {
      if (value == null) return;
      if (value is String) {
        final v = value.trim();
        if (v.isEmpty) return;
        if (v.startsWith('data:image/')) {
          final semi = v.indexOf(';');
          final mime = semi > 5 ? v.substring(5, semi) : 'image/png';
          final key = 'b64:$v';
          if (seen.add(key)) out.add(_ImageOutput(base64: v, extension: extensionForMime(mime)));
          return;
        }
        final uri = Uri.tryParse(v);
        if (uri?.hasScheme == true) {
          final key = 'url:$v';
          if (seen.add(key)) out.add(_ImageOutput(url: v));
          return;
        }
        // A bare base64 string is accepted by a number of gateways.
        final compact = v.replaceAll(RegExp(r'\s+'), '');
        if (compact.length > 100 && RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(compact)) {
          final key = 'b64:$compact';
          if (seen.add(key)) out.add(_ImageOutput(base64: compact));
        }
        return;
      }
      if (value is List) {
        for (final x in value) add(x);
        return;
      }
      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);

      final imageUrl = map['url'] ?? map['image_url'] ?? map['imageUrl'] ??
          (map['image'] is Map ? (map['image'] as Map)['url'] : null);
      if (imageUrl is String) add(imageUrl);

      final mime = map['mime_type'] ?? map['mimeType'] ?? map['content_type'];
      final b64 = map['b64_json'] ?? map['b64Json'] ?? map['base64'] ??
          map['base64_json'] ?? map['image_base64'] ??
          (map['image'] is Map ? ((map['image'] as Map)['b64_json'] ?? (map['image'] as Map)['base64']) : null);
      if (b64 is String && b64.isNotEmpty) {
        final key = 'b64:$b64';
        if (seen.add(key)) out.add(_ImageOutput(base64: b64, extension: extensionForMime(mime?.toString())));
      }

      // Common nested wrappers used by gateways.
      for (final key in const ['data', 'output', 'outputs', 'images', 'result', 'results', 'artifacts']) {
        if (map.containsKey(key)) add(map[key]);
      }
    }

    add(data);
    return out;
  }

  Uint8List _decodeBase64Image(String value) {
    final raw = _stripDataUri(value).replaceAll(RegExp(r'\s+'), '');
    if (raw.isEmpty) throw const FormatException('Empty base64 image payload.');
    try {
      return base64Decode(raw);
    } catch (_) {
      // Some APIs use URL-safe base64 without padding.
      try {
        final normalized = raw.replaceAll('-', '+').replaceAll('_', '/');
        final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
        return base64Decode(padded);
      } catch (_) {
        throw const FormatException('The image payload is not valid base64.');
      }
    }
  }

  Map<String, dynamic> _renderMediaTemplate(String template,
      {required String model, required String prompt, String size = '', int n = 1,
      String negativePrompt = '', String aspectRatio = '', String duration = '', String apiKey = ''}) {
    var rendered = template;
    String replace(String token, String value) {
      final quoted = '"$token"';
      return rendered.contains(quoted)
          ? rendered.replaceAll(quoted, jsonEncode(value))
          : rendered.replaceAll(token, jsonEncode(value));
    }
    rendered = replace('{{API_KEY}}', apiKey);
    rendered = replace('{{MODEL}}', model);
    rendered = replace('{{PROMPT}}', prompt);
    rendered = replace('{{SYSTEM_PROMPT}}', '');
    rendered = replace('{{SIZE}}', size);
    rendered = replace('{{N}}', n.toString());
    rendered = replace('{{NEGATIVE_PROMPT}}', negativePrompt);
    rendered = replace('{{ASPECT_RATIO}}', aspectRatio);
    rendered = replace('{{DURATION}}', duration);
    try {
      final decoded = jsonDecode(rendered);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const FormatException('Custom media template must produce a JSON object.');
    } catch (_) {
      throw ApiException(
        kind: ApiErrorKind.configuration,
        message: 'The custom media request template is invalid JSON.',
        tip: 'Use a JSON object and JSON-safe placeholders such as {{MODEL}} and {{PROMPT}}.',
      );
    }
  }

  List<String> _extractUrls(dynamic data) {
    final out = <String>[];
    void add(dynamic v) { if (v is String && Uri.tryParse(v)?.hasScheme == true) out.add(v); }
    if (data is String) add(data);
    if (data is Map) {
      for (final key in const ['url', 'video_url', 'output_url', 'download_url']) add(data[key]);
      final d = data['data'] ?? data['output'] ?? data['outputs'];
      if (d is List) for (final x in d) { if (x is Map) add(x['url'] ?? x['video_url']); else add(x); }
      if (d is Map) add(d['url'] ?? d['video_url']);
    }
    return out.toSet().toList();
  }

  String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) { final v = map[k]; if (v != null && v.toString().isNotEmpty) return v.toString(); }
    return null;
  }

  String _extensionFromUrl(String url, String fallback) {
    final path = Uri.tryParse(url)?.path ?? '';
    final ext = p.extension(path).replaceFirst('.', '');
    return ext.isEmpty || ext.length > 5 ? fallback : ext;
  }
}
