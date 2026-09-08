import 'package:flutter/material.dart';

import '../../../adapters/adapter_registry.dart';
import '../../../app/app_services.dart';
import '../../../core/models/provider.dart';
import '../../../core/models/system_prompt.dart';
import '../../../core/models/types.dart';

/// Picks one of the enabled providers.
Future<AIProvider?> pickProvider(
    BuildContext context, String? currentProviderId) async {
  final services = AppScope.of(context);
  final providers = services.state.usableProviders;
  if (providers.isEmpty) return null;

  return showModalBottomSheet<AIProvider>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('Choose provider',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in providers)
                  ListTile(
                    leading: CircleAvatar(
                      child: Text(p.name.characters.first.toUpperCase()),
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                        '${p.type.label} · ${p.model.isEmpty ? 'no model set' : p.model}'),
                    selected: p.id == currentProviderId,
                    trailing: p.id == currentProviderId
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(ctx, p),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Picks or manually enters a model. Combines remote fetch (when the provider
/// supports it), favorites, recent, manual entry and per-type hints.
Future<String?> pickModel(
  BuildContext context, {
  required AIProvider provider,
  String? currentModel,
}) async {
  final services = AppScope.of(context);
  final caps = provider.capabilities;
  final recent = await services.providerService.recentModels(provider.id);
  final favorites = await services.providerService.favoriteModels(provider.id);

  if (!context.mounted) return null;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ModelPickerSheet(
      provider: provider,
      caps: caps,
      recent: recent,
      favorites: favorites,
      currentModel: currentModel,
    ),
  );
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({
    required this.provider,
    required this.caps,
    required this.recent,
    required this.favorites,
    this.currentModel,
  });

  final AIProvider provider;
  final ProviderCapabilities caps;
  final List<String> recent;
  final List<String> favorites;
  final String? currentModel;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _fetching = false;
  List<String> _remote = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.currentModel != null) _ctrl.text = widget.currentModel!;
  }

  void _use(String model) {
    if (model.trim().isEmpty) return;
    final services = AppScope.of(context);
    services.providerService.rememberModel(widget.provider.id, model.trim());
    Navigator.pop(context, model.trim());
  }

  Future<void> _fetch() async {
    setState(() {
      _fetching = true;
      _error = null;
    });
    final services = AppScope.of(context);
    try {
      final models =
          await services.providerService.fetchModels(widget.provider.id);
      if (!mounted) return;
      setState(() {
        _remote = models;
        _fetching = false;
        if (models.isEmpty) _error = 'The model list came back empty.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetching = false;
        _error = 'Could not fetch models. Check the API key and base URL.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final manualNote = Text(
      widget.caps.supportsModelListing
          ? 'Tip: fetch the list or type the exact id below.'
          : 'This provider type has no model-list API — type the exact model '
              'id (e.g. from the provider docs).',
      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
    );

    final sections = <Widget>[];
    final seen = <String>{};

    void add(String name, List<String> items, IconData icon) {
      final list = items.where((m) => seen.add(m)).toList();
      if (list.isEmpty) return;
      sections.add(_SectionHeader(label: name, icon: icon));
      for (final m in list) {
        sections.add(ListTile(
          dense: true,
          title: Text(m),
          trailing: IconButton(
            tooltip: 'Favorite',
            icon: Icon(
              m == widget.currentModel || widget.favorites.contains(m)
                  ? Icons.star
                  : Icons.star_border,
              color: widget.favorites.contains(m) ? Colors.amber : null,
              size: 20,
            ),
            onPressed: () {
              final services = AppScope.of(context);
              final fav = !widget.favorites.contains(m);
              services.providerService
                  .setModelFavorite(widget.provider.id, m, fav);
              setState(() => widget.favorites.contains(m)
                  ? widget.favorites.remove(m)
                  : widget.favorites.add(m));
            },
          ),
          onTap: () => _use(m),
        ));
      }
    }

    add('Favorites', widget.favorites, Icons.star);
    add('Recently used', widget.recent, Icons.history);
    if (_remote.isNotEmpty) add('Available from API', _remote, Icons.cloud_done);

    if (widget.caps.supportsModelListing) {
      sections.insert(
        0,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(children: [
            Expanded(
              child: TextButton.icon(
                onPressed: _fetching ? null : _fetch,
                icon: _fetching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_download_outlined),
                label: Text(_fetching ? 'Fetching…' : 'Fetch models from API'),
              ),
            ),
            if (_error != null)
              Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11)))
          ]),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Model',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _ctrl,
                autofocus: false,
                decoration: InputDecoration(
                  labelText: 'Model id (manual entry)',
                  hintText: 'e.g. gpt-4o-mini',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => _use(_ctrl.text),
                  ),
                ),
                onSubmitted: _use,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: manualNote,
            ),
            if (widget.caps.supportsModelListing ||
                AdapterRegistry.modelHints(widget.provider.type).isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final hint in [
                      ...AdapterRegistry.modelHints(widget.provider.type),
                    ])
                      ActionChip(
                        label: Text(hint, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          _ctrl.text = hint;
                          _use(hint);
                        },
                      ),
                  ],
                ),
              ),
            if (sections.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No saved models yet.'),
              )
            else ...[
              const Divider(height: 24),
              ...sections,
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Picks a system prompt, with search and preview.
Future<SystemPrompt?> pickSystemPrompt(
  BuildContext context, {
  required List<SystemPrompt> prompts,
  String? currentContent,
}) async {
  return showModalBottomSheet<SystemPrompt>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _PromptPickerSheet(
      prompts: prompts,
      currentContent: currentContent,
    ),
  );
}

class _PromptPickerSheet extends StatefulWidget {
  const _PromptPickerSheet({
    required this.prompts,
    this.currentContent,
  });

  final List<SystemPrompt> prompts;
  final String? currentContent;

  @override
  State<_PromptPickerSheet> createState() => _PromptPickerSheetState();
}

class _PromptPickerSheetState extends State<_PromptPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = [...widget.prompts]
      ..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return a.title.compareTo(b.title);
      });
    final filtered = _query.trim().isEmpty
        ? all
        : all
            .where((p) =>
                p.title.toLowerCase().contains(_query.trim().toLowerCase()) ||
                p.content.toLowerCase().contains(_query.trim().toLowerCase()))
            .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scrollController) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('System prompt',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search prompts…',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No matching prompts.'))
                : ListView.builder(
                    controller: scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final p = filtered[i];
                      final isCurrent =
                          p.content == widget.currentContent && p.content.isNotEmpty;
                      return ListTile(
                        leading: Icon(
                          p.isFavorite ? Icons.star : Icons.subject,
                          color:
                              p.isFavorite ? Colors.amber : null,
                        ),
                        title: Text(p.title),
                        subtitle: Text(
                          p.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: p.isBuiltIn
                            ? const Icon(Icons.auto_awesome, size: 16)
                            : null,
                        selected: isCurrent,
                        onTap: () => Navigator.pop(ctx, p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// “None / default” divider used in pickers.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}


