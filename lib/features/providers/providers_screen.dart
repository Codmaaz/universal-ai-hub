import 'package:flutter/material.dart';

import '../../app/app_services.dart';
import '../../app/shell/home_shell.dart';
import '../../core/models/provider.dart';
import '../../core/models/types.dart';
import '../chat/widgets/connection_result_dialog.dart';
import 'provider_form_screen.dart';

/// Provider manager: list, add, edit, duplicate, delete, enable/disable,
/// test connection, import/export.
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key});

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Providers'),
        actions: [
          IconButton(
            tooltip: 'Import provider configurations',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _busy ? null : () => _importProviders(context),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'export') {
                await services.transferService.shareProviders();
              } else if (v == 'privacy') {
                _privacyNote(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'export',
                  child: Text('Export configurations (no keys)')),
              PopupMenuItem(
                  value: 'privacy',
                  child: Text('Where are my keys stored?')),
            ],
          ),
          IconButton(
            tooltip: 'Add provider',
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ProviderFormScreen(initial: null)));
              if (context.mounted) services.state.refreshProviders();
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: services.state,
        builder: (context, _) {
          final providers = services.state.providers;
          if (providers.isEmpty) {
            return const _EmptyProviders();
          }
          return RefreshIndicator(
            onRefresh: services.state.refreshProviders,
            child: ListView.separated(
              itemCount: providers.length,
              separatorBuilder: (_, __) => const Divider(indent: 76),
              itemBuilder: (context, i) {
                final p = providers[i];
                return _ProviderTile(
                  provider: p,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            ProviderFormScreen(initial: p)));
                    if (context.mounted) services.state.refreshProviders();
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _importProviders(BuildContext context) async {
    final services = AppScope.of(context);
    final result =
        await services.transferService.importProvidersFromJsonFile();
    await services.state.refreshProviders();
    if (!mounted) return;
    showAppSnack(
      context,
      result.message.isEmpty
          ? 'Import finished.'
          : result.message,
    );
  }

  void _privacyNote(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API key storage'),
        content: const Text(
          'Your API keys are stored only on this device using the operating '
          'system encrypted key storage (Android Keystore). They are never '
          'sent to us, never included in exports, and are attached only to '
          'requests you make to the provider you selected.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it')),
        ],
      ),
    );
  }
}

class _ProviderTile extends StatefulWidget {
  const _ProviderTile({required this.provider, required this.onTap});

  final AIProvider provider;
  final VoidCallback onTap;

  @override
  State<_ProviderTile> createState() => _ProviderTileState();
}

class _ProviderTileState extends State<_ProviderTile> {
  bool? _hasKey;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final has =
        await AppScope.of(context).providerService.hasKey(widget.provider.id);
    if (mounted) setState(() => _hasKey = has);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final services = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final enabled = p.isEnabled;
    final keyKnown = _hasKey ?? true;
    return ListTile(
      leading: Stack(children: [
        CircleAvatar(
          backgroundColor: enabled
              ? cs.secondaryContainer
              : cs.surfaceContainerHighest,
          child: Text(p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase()),
        ),
        if (p.type == ProviderType.custom)
          Positioned(
              right: -2,
              bottom: -2,
              child: Icon(Icons.extension, size: 13, color: cs.primary)),
      ]),
      title: Row(children: [
        Flexible(
            child: Text(p.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    decoration:
                        enabled ? null : TextDecoration.lineThrough))),
        if (p.type == ProviderType.custom) ...[
          const SizedBox(width: 6),
          Chip(
              label: const Text('Custom'),
              labelStyle: TextStyle(fontSize: 10, color: cs.onPrimaryContainer),
              backgroundColor: cs.primaryContainer,
              side: BorderSide.none,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ],
      ]),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          [
            p.type.label,
            p.baseUrl,
            if (p.model.isNotEmpty) p.model,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      isThreeLine: false,
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'edit') {
            widget.onTap();
          } else if (v == 'duplicate') {
            await services.providerService.duplicate(p.id);
            await services.state.refreshProviders();
          } else if (v == 'toggle') {
            await services.providerService.setEnabled(p.id, !p.isEnabled);
            await services.state.refreshProviders();
          } else if (v == 'test') {
            _testConnection();
          } else if (v == 'export_one') {
            await services.transferService.shareProviders();
          } else if (v == 'delete') {
            await _confirmDelete(p, services);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
          PopupMenuItem(
              value: 'toggle',
              child: Text(enabled ? 'Disable' : 'Enable')),
          const PopupMenuItem(value: 'test', child: Text('Test connection…')),
          const PopupMenuItem(value: 'export_one', child: Text('Export')),
          PopupMenuItem(
            value: 'delete',
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
      onTap: widget.onTap,
    );
  }

  Future<void> _testConnection() async {
    final services = AppScope.of(context);
    if (_hasKey == false) {
      if (!mounted) return;
      showAppSnack(context,
          'No API key stored for this provider. Edit the provider and add it first.',
          error: true);
      return;
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Testing connection…')),
        ]),
      ),
    );
    try {
      final result = await services.providerService.testConnection(
        widget.provider.id,
        inspectorEnabled: services.state.settings.requestInspectorEnabled,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showConnectionResultDialog(context, result,
          providerName: widget.provider.name);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      if (e is Exception) {
        showAppSnack(context, e.toString().replaceAll('Exception: ', ''),
            error: true);
      }
    }
  }

  Future<void> _confirmDelete(AIProvider p, AppServices services) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete provider?'),
        content: Text(
            '“${p.name}” and its stored API key will be removed. Existing '
            'chats are kept but will need a provider reassigned.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await services.providerService.delete(p.id);
      await services.state.refreshProviders();
    }
  }
}

class _EmptyProviders extends StatelessWidget {
  const _EmptyProviders();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, size: 72, color: cs.primary),
            const SizedBox(height: 16),
            Text('No AI providers yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Bring your own API key. Add an OpenAI-compatible, Anthropic, '
              'Gemini or fully custom API — requests go directly from this '
              'device to the provider. Nothing is routed through us.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ProviderFormScreen(initial: null)));
                if (context.mounted) services.state.refreshProviders();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add your first provider'),
            ),
          ],
        ),
      ),
    );
  }
}


