import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell/home_shell.dart';
import '../../core/models/conversation.dart';
import '../../core/utils/date_utils.dart';
import 'chat_screen.dart';

/// Conversation history list with search, rename, delete and export.
class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({super.key, this.refreshSignal});

  final ValueNotifier<int>? refreshSignal;

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  List<ConversationSummary> _items = [];
  bool _loading = true;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_onExternalRefresh);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onExternalRefresh);
    super.dispose();
  }

  void _onExternalRefresh() => _load();

  Future<void> _load() async {
    final services = AppScope.of(context);
    try {
      final items = await services.conversationRepository.summaries(
          search: _query.trim().isEmpty ? null : _query.trim());
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load conversations.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'clear_all') await _confirmClearAll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'clear_all',
                  child: Text('Clear chat history')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              leading: const Icon(Icons.search, size: 20),
              hintText: 'Search conversations…',
              onChanged: (v) {
                _query = v;
                _load();
              },
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline,
        title: _error!,
        action: TextButton(onPressed: _load, child: const Text('Retry')),
      );
    }
    if (_items.isEmpty) {
      return const _MessageState(
        icon: Icons.forum_outlined,
        title: 'No conversations yet',
        message:
            'Tap “New chat” to start talking to any of your AI providers.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(indent: 72),
        itemBuilder: (context, i) => _ConversationTile(
          item: _items[i],
          onOpen: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChatScreen(conversationId: _items[i].id)));
            _load();
          },
          onRenamed: _load,
        ),
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear chat history?'),
        content: const Text(
            'All conversations and their messages will be deleted from this '
            'device. This cannot be undone. Provider settings and prompts are '
            'kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AppScope.of(context).conversationRepository.clearAll();
      _load();
    }
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.item,
    required this.onOpen,
    required this.onRenamed,
  });

  final ConversationSummary item;
  final VoidCallback onOpen;
  final VoidCallback onRenamed;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.secondaryContainer,
        child: Icon(Icons.chat_outlined, color: cs.onSecondaryContainer),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          [
            if (item.providerName.isNotEmpty) item.providerName,
            if (item.model.isNotEmpty) item.model,
            formatRelativeTime(item.updatedAt),
            item.messageCount == 0 ? null : '${item.messageCount} msgs',
          ].whereType<String>().join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onTap: onOpen,
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'rename') {
            final name = await _askName(context);
            if (name != null && name.trim().isNotEmpty) {
              await services.conversationRepository.rename(
                  item.id, name.trim());
              onRenamed();
            }
          } else if (v == 'export') {
            await _export(context);
          } else if (v == 'delete') {
            await services.conversationRepository.delete(item.id);
            onRenamed();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'export', child: Text('Export…')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Future<String?> _askName(BuildContext context) {
    final ctrl = TextEditingController(text: item.title);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final services = AppScope.of(context);
    final conv = await services.conversationRepository.findById(item.id);
    if (conv == null) return;
    final messages = await services.conversationRepository.messagesOf(item.id);

    if (!context.mounted) return;
    final format = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.ios_share),
              title: Text('Export conversation'),
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Plain text (.txt)'),
              onTap: () => Navigator.pop(ctx, 'txt'),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Markdown (.md)'),
              onTap: () => Navigator.pop(ctx, 'md'),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('JSON'),
              onTap: () => Navigator.pop(ctx, 'json'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (format == null) return;
    try {
      await services.transferService
          .shareConversation(conv, messages, format: format);
    } catch (e) {
      if (context.mounted) {
        showAppSnack(context, 'Export failed: could not open the share sheet.',
            error: true);
      }
    }
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState(
      {required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.outline),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.outline)),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
