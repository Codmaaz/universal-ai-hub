import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../../core/network/api_exception.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../app/app_services.dart';
import '../../core/models/media_item.dart';
import '../../data/services/media_service.dart';

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key, required this.kind});
  final MediaKind kind;
  @override State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  late final MediaService _service;
  bool _initialized = false, _busy = false;
  final _prompt = TextEditingController();
  final _negative = TextEditingController();
  final _model = TextEditingController();
  final _endpoint = TextEditingController(text: '/videos');
  final _statusEndpoint = TextEditingController(text: '/videos/{id}');
  String? _providerId, _file;
  String _imageSize = '1024x1024', _aspect = '16:9';
  int _count = 1, _duration = 5;
  List<MediaItem> _items = [];

  bool get _image => widget.kind == MediaKind.image;

  @override void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _service = MediaService(providerService: AppScope.of(context).providerService);
      _load();
    }
  }

  Future<void> _load() async {
    final items = await _service.history(kind: widget.kind);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
    if (r?.files.single.path != null && mounted) setState(() => _file = r!.files.single.path);
  }

  Future<void> _go() async {
    if (_busy) return;
    if (_providerId == null) return _snack('Select a provider.', true);
    if (_prompt.text.trim().isEmpty) return _snack('Enter a prompt.', true);
    if (_model.text.trim().isEmpty) return _snack('Enter or select a model ID.', true);
    setState(() => _busy = true);
    try {
      if (_image) {
        await _service.generateImage(providerId: _providerId!, model: _model.text.trim(),
          prompt: _prompt.text.trim(), size: _imageSize, n: _count, negativePrompt: _negative.text.trim());
      } else {
        await _service.startVideo(providerId: _providerId!, model: _model.text.trim(),
          prompt: _prompt.text.trim(), endpoint: _endpoint.text.trim().isEmpty ? '/videos' : _endpoint.text.trim(),
          sourceFilePath: _file, aspectRatio: _aspect, durationSeconds: _duration);
      }
      await _load();
      _snack(_image ? 'Image request completed.' : 'Video request submitted. Poll status if it is queued.');
    } catch (e) { _snack(_friendlyError(e), true); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _poll(MediaItem item) async {
    if (item.jobId == null) return;
    setState(() => _busy = true);
    final updated = await _service.pollVideo(item, statusEndpoint: _statusEndpoint.text.trim().isEmpty ? '/videos/{id}' : _statusEndpoint.text.trim());
    if (mounted) { await _load(); _snack('Status: ${updated.status.name}'); setState(() => _busy = false); }
  }

  Future<void> _download(MediaItem item) async {
    setState(() => _busy = true);
    try {
      final updated = await _service.download(item);
      await _load();
      _snack('Saved in app storage: ${updated.localPath!.split('/').last}');
    } catch (e) { _snack(_friendlyError(e), true); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  void _snack(String text, [bool error = false]) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? Theme.of(context).colorScheme.error : null)); }
  String _friendlyError(Object e) {
    if (e is ApiException) {
      final extra = e.sanitizedBody == null || e.sanitizedBody!.isEmpty ? '' : '\n\nProvider response: ${e.sanitizedBody}';
      return '${e.message}${e.tip == null ? '' : '\n${e.tip}'}$extra';
    }
    return e.toString().replaceFirst('Exception: ', '').replaceFirst("Instance of 'ResponseBody'", 'Provider returned an unreadable error response');
  }

  @override Widget build(BuildContext context) {
    final providers = AppScope.of(context).state.providers.where((p) => p.isEnabled && (p.capabilities.supportsImages || !_image)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(_image ? 'Image Generator' : 'Video Generator'), actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_image && providers.isEmpty) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('No configured provider advertises OpenAI-compatible image generation. Add an OpenAI-compatible provider that supports /images/generations.')),
        DropdownButtonFormField<String>(value: _providerId, decoration: const InputDecoration(labelText: 'Provider'),
          items: providers.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(), onChanged: (v) {
            final selected = providers.where((p) => p.id == v).cast<dynamic>().toList();
            setState(() {
              _providerId = v;
              if (selected.isNotEmpty && selected.first.model.trim().isNotEmpty) {
                _model.text = selected.first.model.trim();
              }
            });
          }),
        const SizedBox(height: 12),
        TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model', hintText: 'Model ID (required by most APIs)')),
        const SizedBox(height: 12),
        TextField(controller: _prompt, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: _image ? 'Image prompt' : 'Video prompt', border: const OutlineInputBorder())),
        if (_image) ...[
          const SizedBox(height: 12), TextField(controller: _negative, maxLines: 2, decoration: const InputDecoration(labelText: 'Negative prompt (if supported)')),
          const SizedBox(height: 12), Row(children: [Expanded(child: DropdownButtonFormField(value: _imageSize, decoration: const InputDecoration(labelText: 'Size'), items: const ['512x512','768x768','1024x1024','1024x1792','1792x1024'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => setState(() => _imageSize = v!))), const SizedBox(width: 12), Expanded(child: DropdownButtonFormField<int>(value: _count, decoration: const InputDecoration(labelText: 'Images'), items: const [1,2,3,4].map((x) => DropdownMenuItem(value: x, child: Text('$x'))).toList(), onChanged: (v) => setState(() => _count = v!)))])
        ] else ...[
          const SizedBox(height: 12), TextField(controller: _endpoint, decoration: const InputDecoration(labelText: 'Create endpoint', helperText: 'Example: /videos or provider-specific path')),
          const SizedBox(height: 12), TextField(controller: _statusEndpoint, decoration: const InputDecoration(labelText: 'Status endpoint', helperText: 'Use {id}, e.g. /videos/{id}')),
          const SizedBox(height: 12), Row(children: [Expanded(child: DropdownButtonFormField(value: _aspect, decoration: const InputDecoration(labelText: 'Aspect'), items: const ['16:9','9:16','1:1','4:3'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => setState(() => _aspect = v!))), const SizedBox(width: 12), Expanded(child: DropdownButtonFormField<int>(value: _duration, decoration: const InputDecoration(labelText: 'Seconds'), items: const [5,10,15].map((x) => DropdownMenuItem(value: x, child: Text('$x'))).toList(), onChanged: (v) => setState(() => _duration = v!))) ]),
          const SizedBox(height: 8), OutlinedButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.upload_file), label: Text(_file == null ? 'Upload input image/file' : 'Selected: ${_file!.split('/').last}')),
          if (_file != null) Text('File is uploaded as multipart field “input_file”. Provider-specific APIs may use another field name.', style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 16), FilledButton.icon(onPressed: _busy ? null : _go, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_image ? Icons.image : Icons.movie), label: Text(_busy ? 'Working…' : _image ? 'Generate image' : 'Generate video')),
        const SizedBox(height: 24), Text('History', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
        if (_items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No generations yet.'))),
        ..._items.map(_card),
      ]),
    );
  }

  Widget _card(MediaItem item) {
    final url = item.remoteUrl;
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(item.prompt, maxLines: 3, overflow: TextOverflow.ellipsis), const SizedBox(height: 6),
      Text('${item.providerName} • ${item.model} • ${item.status.name}'),
      if (item.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(item.error!, style: TextStyle(color: Theme.of(context).colorScheme.error), maxLines: 2, overflow: TextOverflow.ellipsis)),
      if (_image && item.localPath != null) ...[
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(item.localPath!), errorBuilder: (_, __, ___) => const Text('Local image preview unavailable'))),
      ] else if (url != null && _image) ...[
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(url, errorBuilder: (_, __, ___) => const Text('Image preview unavailable'))),
      ]
      if (url != null && !_image) ...[const SizedBox(height: 8), _VideoPreview(url: url)],
      const SizedBox(height: 4), Wrap(spacing: 4, children: [
        if (!_image && item.jobId != null && item.status != MediaStatus.completed && item.status != MediaStatus.failed) OutlinedButton.icon(onPressed: _busy ? null : () => _poll(item), icon: const Icon(Icons.sync), label: const Text('Check status')),
        if (url != null || item.localPath != null) OutlinedButton.icon(onPressed: _busy ? null : () => _download(item), icon: const Icon(Icons.download), label: const Text('Download')),
        if (item.localPath != null) OutlinedButton.icon(onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(item.localPath!)])), icon: const Icon(Icons.share), label: const Text('Share file')) else if (url != null) OutlinedButton.icon(onPressed: () => SharePlus.instance.share(ShareParams(text: url)), icon: const Icon(Icons.share), label: const Text('Share link')),
        OutlinedButton.icon(onPressed: () async { await _service.delete(item.id); await _load(); }, icon: const Icon(Icons.delete_outline), label: const Text('Delete')),
      ])
    ])));
  }

  @override void dispose() { _prompt.dispose(); _negative.dispose(); _model.dispose(); _endpoint.dispose(); _statusEndpoint.dispose(); super.dispose(); }
}

class _VideoPreview extends StatefulWidget { const _VideoPreview({required this.url}); final String url; @override State<_VideoPreview> createState() => _VideoPreviewState(); }
class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  @override void initState() { super.initState(); _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))..initialize().then((_) { if (mounted) setState(() {}); }).catchError((_) {}); }
  @override Widget build(BuildContext context) { final c = _controller; if (c == null || !c.value.isInitialized) return const Padding(padding: EdgeInsets.all(8), child: Text('Video ready. Preview loading…')); return Column(children: [AspectRatio(aspectRatio: c.value.aspectRatio == 0 ? 16/9 : c.value.aspectRatio, child: VideoPlayer(c)), IconButton(icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow), onPressed: () { setState(() => c.value.isPlaying ? c.pause() : c.play()); })]); }
  @override void dispose() { _controller?.dispose(); super.dispose(); }
}
