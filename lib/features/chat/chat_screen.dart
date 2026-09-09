import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../adapters/adapter_registry.dart';
import '../../app/app_services.dart';
import '../../app/shell/home_shell.dart';
import '../../core/models/api_request_record.dart';
import '../../core/models/conversation.dart';
import '../../core/models/generation_settings.dart';
import '../../core/models/provider.dart';
import '../../core/models/types.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/ids.dart';
import '../../data/services/chat_service.dart';
import 'widgets/api_error_dialog.dart';
import 'widgets/generation_settings_sheet.dart';
import 'widgets/inspector_sheet.dart';
import 'widgets/markdown_view.dart';
import 'widgets/picker_sheets.dart';

/// Chat view for a single conversation. Manages streaming, cancellation,
/// regeneration, editing/resending, message actions and context selectors.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatConversation? _conv;
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  // Streaming tail state (isolated from the message list so token updates do
  // not rebuild the whole history).
  final ValueNotifier<String> _pendingText = ValueNotifier('');
  bool _streaming = false;
  CancelToken? _cancelToken;
  ApiRequestRecordNotifier? _lastRecord;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  GenerationSettings _settings = const GenerationSettings();
  Timer? _scrollDebounce;
  DateTime _lastScrollAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _loadError;

  AIProvider? _provider;
  AppServices get _services => AppScope.of(context);

  @override
  void initState() {
    super.initState();
    _pendingText.addListener(_onPendingChanged);
    _load();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _scrollDebounce?.cancel();
    _pendingText
      ..removeListener(_onPendingChanged)
      ..dispose();
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onPendingChanged() {
    // Auto-scroll throttled while text streams in.
    final now = DateTime.now();
    if (now.difference(_lastScrollAt).inMilliseconds < 120) return;
    _lastScrollAt = now;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels < 300 || _streaming) {
      _scheduleJump();
    }
  }

  void _scheduleJump() {
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 60), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _load() async {
    final services = _services;
    final conv = await services.conversationRepository.findById(widget.conversationId);
    if (conv == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'This conversation no longer exists.';
        });
      }
      return;
    }
    final messages = await services.conversationRepository.messagesOf(conv.id);
    _conv = conv;
    _messages.addAll(messages);
    _settings = const GenerationSettings();
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
    await _syncProvider();
  }

  /// Ensures the conversation has a provider + model usable for sending.
  Future<void> _syncProvider({bool allowPick = false}) async {
    final conv = _conv;
    if (conv == null) return;
    var provider = _services.state.providerById(conv.providerId);
    if (provider == null || !provider.isEnabled) {
      if (!allowPick) {
        // Deleted or disabled provider — signal missing provider state.
        setState(() {});
        return;
      }
      final picked = await pickProvider(context, null);
      if (picked == null || !mounted) return;
      provider = picked;
      await _applyProviderToConversation(provider);
    }
    if (!mounted) return;
    setState(() => _provider = provider);
  }

  Future<void> _applyProviderToConversation(AIProvider provider) async {
    final conv = _conv!;
    var model = _provider?.id == provider.id ? _provider!.model : '';
    if (model.isEmpty && conv.model.isNotEmpty) model = conv.model;
    if (model.isEmpty) model = provider.model;
    final updated = conv.copyWith(
      providerId: provider.id,
      model: model,
      updatedAt: DateTime.now(),
    );
    _conv = updated;
    await _services.conversationRepository.upsertConversation(updated);
    setState(() => _provider = provider);
    await _services.state.rememberLastUsed(provider.id, model);
    _services.state.refreshProviders();
  }

  AIProvider? get _activeProvider => _provider;

  bool get _streamingAllowed {
    final p = _activeProvider;
    if (p == null) return false;
    final caps = AdapterRegistry.forType(p.type).capabilities;
    return caps.supportsStreaming &&
        p.streamingEnabled &&
        _services.state.settings.streamingEnabled;
  }

  // ---- Actions --------------------------------------------------------------

  Future<void> _pickProvider() async {
    final picked = await pickProvider(context, _conv?.providerId);
    if (picked == null || !mounted) return;
    await _applyProviderToConversation(picked);
  }

  Future<void> _pickModel() async {
    final p = _activeProvider ?? _provider;
    if (p == null) return;
    final model = await pickModel(context, provider: p, currentModel: _conv?.model);
    if (model == null || !mounted) return;
    final updated = _conv!.copyWith(model: model, updatedAt: DateTime.now());
    _conv = updated;
    await _services.conversationRepository.upsertConversation(updated);
    setState(() {});
  }

  Future<void> _pickPrompt() async {
    final prompts = await _services.promptRepository.listAll();
    final picked = await pickSystemPrompt(context,
        prompts: prompts, currentContent: _conv?.systemPrompt);
    if (picked == null || !mounted) return;
    final updated = _conv!.copyWith(
        systemPrompt: picked.id.startsWith('builtin_') || picked.id.startsWith('prompt_')
            ? picked.content
            : picked.content,
        updatedAt: DateTime.now());
    _conv = updated;
    await _services.conversationRepository.upsertConversation(updated);
    setState(() {});
  }

  Future<void> _clearPrompt() async {
    final updated =
        _conv!.copyWith(systemPrompt: '', updatedAt: DateTime.now());
    _conv = updated;
    await _services.conversationRepository.upsertConversation(updated);
    setState(() {});
  }

  Future<void> _openSettingsSheet() async {
    final p = _activeProvider;
    if (p == null) return;
    final result = await showGenerationSettingsSheet(context,
        provider: p, settings: _settings);
    if (result != null && mounted) {
      setState(() => _settings = result);
    }
  }

  void _rename() async {
    final ctrl = TextEditingController(text: _conv?.title ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (value == null || !mounted) return;
    final title = value.trim();
    if (title.isEmpty) return;
    await _services.conversationRepository.rename(widget.conversationId, title);
    _conv = _conv!.copyWith(title: title);
    setState(() {});
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (_conv == null) return;
    var p = _activeProvider ?? _provider;
    if (p == null) {
      await _syncProvider(allowPick: true);
      p = _provider;
      if (p == null || !mounted) return;
    }
    final model = _conv!.model.trim();
    if (model.isEmpty) {
      await _pickModel();
      if (_conv!.model.trim().isEmpty) return;
    }

    final userMsg = ChatMessage(
        id: Ids.newId('msg'), role: ChatMessageRole.user, content: text);
    _messages.add(userMsg);
    _input.clear();
    await _services.conversationRepository
        .insertMessage(widget.conversationId, userMsg);

    if (_conv!.title == 'New chat' || _conv!.title.isEmpty) {
      final short =
          text.length > 48 ? '${text.substring(0, 48)}…' : text;
      final title = short.replaceAll('\n', ' ');
      _conv = _conv!.copyWith(title: title);
      await _services.conversationRepository
          .rename(widget.conversationId, title);
    }

    // Remember model usage for the picker.
    _services.providerService.rememberModel(p.id, model);
    if (mounted) setState(() {});
    await _runTurn();
  }

  /// Sends with the current conversation history (user msg already appended).
  Future<void> _runTurn() async {
    final p = _activeProvider ?? _provider;
    final conv = _conv;
    if (p == null || conv == null) return;

    _cancelToken = CancelToken();
    _streaming = true;
    _pendingText.value = '';
    setState(() => _sending = true);

    final services = _services;
    try {
      final result = await services.chatService.sendTurn(SendTurnParams(
        provider: p,
        messages: List.of(_messages),
        model: conv.model,
        systemPrompt: conv.systemPrompt,
        settings: _settings,
        streaming: _streamingAllowed,
        cancelToken: _cancelToken,
        onDelta: (delta) => _pendingText.value += delta,
        inspectorEnabled: services.state.settings.requestInspectorEnabled,
        connectTimeout: Duration(
            seconds: services.state.settings.connectTimeoutSeconds),
        receiveTimeout: Duration(
            seconds: services.state.settings.receiveTimeoutSeconds),
      ));

      final content = result.content.trim();
      await _finishAssistant(content: content, cancelled: false);
      _lastRecord = ApiRequestRecordNotifier(result.requestRecord);
    } on ApiException catch (e) {
      if (e.isCancellation) {
        // Preserve partial output.
        await _finishAssistant(
            content: _pendingText.value.trim(), cancelled: true);
        _lastRecord = ApiRequestRecordNotifier(null);
        if (mounted) {
          showAppSnack(context, 'Generation stopped.');
        }
      } else {
        _lastRecord = ApiRequestRecordNotifier(null);
        if (mounted) showApiErrorDialog(context, e);
      }
    } on DioException {
      // Cancelled / aborted path surfaced as ApiException by adapters.
      if (mounted) showAppSnack(context, 'Request stopped.');
    } catch (e) {
      if (mounted) {
        showAppSnack(context, 'Could not send the message: ${e.toString().replaceFirst('Exception: ', '')}',
            error: true);
      }
    } finally {
      _streaming = false;
      _pendingText.value = '';
      if (mounted) setState(() => _sending = false);
      _cancelToken = null;
    }
  }

  Future<void> _finishAssistant(
      {required String content, required bool cancelled}) async {
    final buffer = _pendingText.value;
    final merged = content.isNotEmpty ? content : buffer.trim();
    if (merged.isNotEmpty) {
      final msg = ChatMessage(
        id: Ids.newId('msg'),
        role: ChatMessageRole.assistant,
        content: merged,
      );
      _messages.add(msg);
      await _services.conversationRepository
          .insertMessage(widget.conversationId, msg);
    }
    _pendingText.value = '';
    if (mounted) {
      setState(() {});
      _scheduleJump();
    }
  }

  Future<void> _stop() async {
    try {
      _cancelToken?.cancel();
    } catch (_) {}
  }

  /// Regenerate: drop trailing assistant content then resend the last user msg.
  Future<void> _regenerate() async {
    if (_sending) return;
    final lastUserIdx = _messages.lastIndexWhere(
        (m) => m.role == ChatMessageRole.user);
    if (lastUserIdx < 0) return;
    // Remove everything after the last user message.
    final removed =
        _messages.sublist(lastUserIdx + 1).map((m) => m.id).toSet();
    for (final id in removed) {
      await _services.conversationRepository
          .deleteMessage(widget.conversationId, id);
    }
    _messages.removeRange(lastUserIdx + 1, _messages.length);
    if (mounted) setState(() {});
    await _runTurn();
  }

  Future<void> _editAndResend(ChatMessage userMessage) async {
    if (_sending) return;
    final idx =
        _messages.indexWhere((m) => m.id == userMessage.id);
    if (idx < 0) return;
    final ctrl = TextEditingController(text: userMessage.content);
    final edited = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Message'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Send')),
        ],
      ),
    );
    if (edited == null || !mounted) return;
    final content = edited.trim();
    if (content.isEmpty) return;

    final updated = userMessage.copyWith(content: content);
    _messages[idx] = updated;
    await _services.conversationRepository
        .updateMessageContent(widget.conversationId, userMessage.id, content);

    // Remove everything after it and resend.
    final removed = _messages.sublist(idx + 1).map((m) => m.id).toSet();
    for (final id in removed) {
      await _services.conversationRepository
          .deleteMessage(widget.conversationId, id);
    }
    _messages.removeRange(idx + 1, _messages.length);
    setState(() {});
    await _runTurn();
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    _messages.removeWhere((m) => m.id == message.id);
    await _services.conversationRepository
        .deleteMessage(widget.conversationId, message.id);
    if (mounted) setState(() {});
  }

  Future<void> _copyMessage(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (mounted) showAppSnack(context, 'Message copied to clipboard.');
  }

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final conv = _conv;
    final providerName = _provider?.name ??
        (_conv == null
            ? ''
            : _services.state
                    .providerById(_conv!.providerId)
                    ?.name ??
                'No provider');
    final model = _conv?.model ?? '';

    return Scaffold(
      appBar: AppBar(
        title: _loading
            ? const Text('Chat')
            : InkWell(
                onTap: _rename,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conv?.title ?? 'Chat',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16)),
                    Text(
                      [if (providerName.isNotEmpty) providerName,
                        if (model.isNotEmpty) model]
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'Generation parameters',
            icon: const Icon(Icons.tune),
            onPressed: _activeProvider == null ? null : _openSettingsSheet,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'rename') {
                _rename();
              } else if (v == 'inspect') {
                final rec = _lastRecord?.record;
                if (rec != null) showRequestInspectorSheet(context, rec);
              } else if (v == 'export') {
                await _exportConversation();
              } else if (v == 'delete') {
                await _confirmDeleteConversation();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(
                  value: 'inspect',
                  enabled: _lastRecord?.record != null,
                  child: const Text('Inspect last request')),
              const PopupMenuItem(value: 'export', child: Text('Export…')),
              const PopupMenuItem(value: 'delete', child: Text('Delete chat')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _MissingConversation(message: _loadError!)
              : Column(
                  children: [
                    _contextBar(
                        providerName: providerName, model: model),
                    Expanded(child: _messageArea()),
                    _composerArea(),
                  ],
                ),
    );
  }

  Widget _contextBar({required String providerName, required String model}) {
    final caps = _activeProvider == null
        ? null
        : AdapterRegistry.forType(_activeProvider!.type).capabilities;
    final supportsPrompt = caps?.supportsSystemPrompt ?? true;
    final promptLabel = (_conv?.systemPrompt ?? '').trim().isEmpty
        ? 'No prompt'
        : 'Prompt';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _chip(
              icon: Icons.dns_outlined,
              label: providerName.isEmpty ? 'Choose provider' : providerName,
              onTap: _pickProvider,
            ),
            const SizedBox(width: 6),
            _chip(
              icon: Icons.smart_toy_outlined,
              label: model.isEmpty ? 'Model' : model,
              onTap: _pickModel,
            ),
            if (supportsPrompt) ...[
              const SizedBox(width: 6),
              _chip(
                icon: Icons.subject,
                label: promptLabel,
                onTap: _pickPrompt,
                onClear: (_conv?.systemPrompt ?? '').trim().isEmpty
                    ? null
                    : _clearPrompt,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(
      {required IconData icon,
      required String label,
      required VoidCallback onTap,
      VoidCallback? onClear}) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: cs.primary),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium),
              ),
              if (onClear != null) ...[
                const SizedBox(width: 2),
                InkWell(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 13, color: cs.outline),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageArea() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: _messages.length + (_streaming ? 1 : 0) + 1,
      itemBuilder: (context, i) {
        if (i == _messages.length + (_streaming ? 1 : 0)) {
          return const SizedBox(height: 8);
        }
        if (_streaming && i == _messages.length) {
          return _StreamingBubble(pendingText: _pendingText);
        }
        final m = _messages[i];
        return _MessageBubble(
          message: m,
          isUser: m.role == ChatMessageRole.user,
          onCopy: () => _copyMessage(m),
          onDelete: () => _deleteMessage(m),
          onEditResend:
              m.role == ChatMessageRole.user ? () => _editAndResend(m) : null,
          onRegenerate: m.role == ChatMessageRole.assistant && !m.error
              ? _regenerate
              : null,
        );
      },
    );
  }

  Widget _composerArea() {
    final sending = _sending && _streaming;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
              top: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.5))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sending)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Generating…',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('Stop'),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _activeProvider == null
                          ? 'Choose a provider to start…'
                          : 'Type a message…',
                      filled: true,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportConversation() async {
    final conv = _conv;
    if (conv == null) return;
    final format = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('Plain text (.txt)'),
                onTap: () => Navigator.pop(ctx, 'txt')),
            ListTile(
                leading: const Icon(Icons.code),
                title: const Text('Markdown (.md)'),
                onTap: () => Navigator.pop(ctx, 'md')),
            ListTile(
                leading: const Icon(Icons.data_object),
                title: const Text('JSON'),
                onTap: () => Navigator.pop(ctx, 'json')),
          ],
        ),
      ),
    );
    if (format == null) return;
    try {
      await _services.transferService
          .shareConversation(conv, _messages, format: format);
    } catch (_) {
      if (mounted) {
        showAppSnack(context, 'Sharing failed.', error: true);
      }
    }
  }

  Future<void> _confirmDeleteConversation() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: const Text(
            'The conversation and all its messages will be deleted locally.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (yes == true) {
      await _services.conversationRepository.delete(widget.conversationId);
      if (mounted) Navigator.of(context).pop();
    }
  }
}

/// Notifier wrapper so the AppBar menu can keep a nullable inspector record.
class ApiRequestRecordNotifier {
  ApiRequestRecordNotifier(this.record);
  final ApiRequestRecord? record;
}

/// User / assistant bubble.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isUser,
    required this.onCopy,
    required this.onDelete,
    this.onEditResend,
    this.onRegenerate,
  });

  final ChatMessage message;
  final bool isUser;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback? onEditResend;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () => _actions(context),
          child: Container(
            margin: const EdgeInsets.only(top: 6, bottom: 6, left: 48),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: const Radius.circular(16),
                bottomRight: const Radius.circular(4),
              ),
            ),
            child: SelectableText(message.content),
          ),
        ),
      );
    }

    if (message.error) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(Icons.error_outline, size: 18, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message.content,
                  style: TextStyle(fontSize: 13, color: cs.onErrorContainer))),
        ]),
      );
    }

    return GestureDetector(
      onLongPress: () => _actions(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            MarkdownView(data: message.content),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _actions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('Copy message'),
              onTap: () {
                Navigator.pop(ctx);
                onCopy();
              },
            ),
            if (onEditResend != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit and resend'),
                onTap: () {
                  Navigator.pop(ctx);
                  onEditResend!();
                },
              ),
            if (onRegenerate != null)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Regenerate response'),
                onTap: () {
                  Navigator.pop(ctx);
                  onRegenerate!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete message'),
              textColor: Theme.of(ctx).colorScheme.error,
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Pending assistant reply while streaming. Only this widget rebuilds as
/// tokens arrive (ValueNotifier), so long histories stay cheap.
class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({required this.pendingText});

  final ValueNotifier<String> pendingText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String>(
      valueListenable: pendingText,
      builder: (context, value, _) {
        final isEmpty = value.isEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: isEmpty
              ? Row(children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text('Thinking…',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ])
              : Text(
                  value,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
        );
      },
    );
  }
}

class _MissingConversation extends StatelessWidget {
  const _MissingConversation({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
