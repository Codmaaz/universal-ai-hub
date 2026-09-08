import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell/home_shell.dart';
import '../../core/models/system_prompt.dart';
import 'prompt_editor_sheet.dart';

/// System Prompt manager: create/edit/delete/duplicate/favorite/search plus
/// import/export.
class PromptsScreen extends StatefulWidget {
  const PromptsScreen({super.key});

  @override
  State<PromptsScreen> createState() => _PromptsScreenState();
}

class _PromptsScreenState extends State<PromptsScreen> {
  String _query = '';
  bool _busy = false;

  List<SystemPrompt> _filter(List<SystemPrompt> all) {
    if (_query.trim().isEmpty) return all;
    final q = _query.trim().toLowerCase();
    return all
        .where((p) =>
            p.title.toLowerCase().contains(q) ||
            p.content.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _openEditor([SystemPrompt? existing]) async {
    final services = AppScope.of(context);
    final result = await showPromptEditor(context, existing: existing);
    if (result == null) return;
    if (existing == null) {
      await services.promptRepository.create(
        title: result.title,
        content: result.content,
      );
    } else {
      await services.promptRepository
          .update(existing.copyWith(title: result.title, content: result.content));
    }
    await services.state.refreshPrompts();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompts'),
        actions: [
          IconButton(
            tooltip: 'Import prompts',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _busy ? null : () => _import(),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'export') {
                await services.transferService.sharePrompts();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Export prompts')),
            ],
          ),
          IconButton(
            tooltip: 'New prompt',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              leading: const Icon(Icons.search, size: 20),
              hintText: 'Search prompts…',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: services.state,
              builder: (context, _) {
                final prompts = services.state.prompts;
                final filtered = _filter(prompts)
                  ..sort((a, b) {
                    if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
                    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
                  });
                if (filtered.isEmpty) {
                  return const _EmptyPrompts();
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(indent: 60),
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    return ListTile(
                      leading: p.isFavorite
                          ? const Icon(Icons.star, color: Colors.amber)
                          : Icon(Icons.subject,
                              color: Theme.of(context).colorScheme.primary),
                      title: Text(p.title),
                      subtitle: Text(p.content,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _openEditor(p),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            _openEditor(p);
                          } else if (v == 'favorite') {
                            await services.promptRepository
                                .toggleFavorite(p.id);
                            await services.state.refreshPrompts();
                          } else if (v == 'duplicate') {
                            await services.promptRepository.duplicate(p);
                            await services.state.refreshPrompts();
                          } else if (v == 'delete') {
                            await services.promptRepository.delete(p.id);
                            await services.state.refreshPrompts();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                              value: 'favorite',
                              child: Text(p.isFavorite
                                  ? 'Remove favorite'
                                  : 'Favorite')),
                          const PopupMenuItem(
                              value: 'duplicate', child: Text('Duplicate')),
                          if (!p.isBuiltIn)
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete',
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error)),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final services = AppScope.of(context);
    final result = await services.transferService.importPromptsFromPickedFile();
    await services.state.refreshPrompts();
    if (!mounted) return;
    showAppSnack(context,
        result.message.isEmpty ? 'Import finished.' : result.message);
  }
}

class _EmptyPrompts extends StatelessWidget {
  const _EmptyPrompts();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notes_outlined, size: 64, color: cs.outline),
            const SizedBox(height: 12),
            Text('No system prompts yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Create reusable instructions — coding assistant, translator, '
              'teacher — and attach them to any chat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
