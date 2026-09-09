import 'dart:async';
import 'dart:io';
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
import '../repositories/media_repository.dart';
import 'provider_service.dart';

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
      final data = await _postJson(provider, '/images/generations', {
        'model': model, 'prompt': prompt, 'size': size, 'n': n,
        if ((negativePrompt ?? '').trim().isNotEmpty) 'negative_prompt': negativePrompt,
      });
      final urls = _extractUrls(data);
      if (urls.isEmpty) {
        throw const ApiException(kind: ApiErrorKind.parseError,
          message: 'The provider returned no image URL.',
          tip: 'This provider may not support the OpenAI Images API response format.');
      }
      final done = item.copyWith(status: MediaStatus.completed, remoteUrl: urls.first,
        metadata: {...item.metadata, 'urls': urls}, updatedAt: DateTime.now());
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
      final fields = <String, dynamic>{'model': model, 'prompt': prompt,
        if (aspectRatio != null) 'aspect_ratio': aspectRatio,
        if (durationSeconds != null) 'duration': durationSeconds};
      final data = sourceFilePath == null
          ? await _postJson(provider, endpoint, fields)
          : await _postMultipart(provider, endpoint, fields, sourceFilePath);
      final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final urls = _extractUrls(map);
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
    final url = item.remoteUrl;
    if (url == null || url.isEmpty) throw const ApiException(kind: ApiErrorKind.configuration, message: 'No remote output URL is available.');
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'generated_media'));
    if (!await mediaDir.exists()) await mediaDir.create(recursive: true);
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

  Future<dynamic> _postJson(AIProvider pvd, String endpoint, Map<String, dynamic> body) async {
    final auth = await _auth(pvd);
    final dio = AppDio.create(receiveTimeout: const Duration(minutes: 5));
    try {
      final r = await dio.post(_url(pvd, endpoint), data: body,
        options: Options(headers: {...auth.headers, 'Content-Type': 'application/json'}), queryParameters: auth.queryParameters);
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
  String _url(AIProvider pvd, String endpoint) => '${pvd.baseUrl.replaceAll(RegExp(r'/+$'), '')}/${endpoint.replaceFirst(RegExp(r'^/+'), '')}';

  List<String> _extractUrls(dynamic data) {
    final out = <String>[];
    void add(dynamic v) { if (v is String && Uri.tryParse(v)?.hasScheme == true) out.add(v); }
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
