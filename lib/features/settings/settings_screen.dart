import 'package:flutter/material.dart';
import '../../app/app_services.dart';
import '../../app/shell/home_shell.dart';
import '../../core/models/app_settings.dart';
import '../../core/security/secure_token_store.dart';

/// App settings: appearance, chat defaults, network, developer tools,
/// privacy actions and data import/export.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: services.state,
        builder: (context, _) {
          final settings = services.state.settings;
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _Section(
                title: 'Appearance',
                children: [
                  SegmentedButton<ThemePref>(
                    segments: [
                      for (final t in ThemePref.values)
                        ButtonSegment(
                            value: t,
                            label: Text(t.label),
                            icon: Icon(switch (t) {
                              ThemePref.light => Icons.light_mode,
                              ThemePref.dark => Icons.dark_mode,
                              ThemePref.system => Icons.brightness_auto,
                            })),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) =>
                        services.state.setTheme(s.first),
                  ),
                ],
              ),
              _Section(
                title: 'Chat',
                children: [
                  ListTile(
                    leading: const Icon(Icons.format_size),
                    title: const Text('Text size'),
                    subtitle: Slider(
                      value: settings.fontScale.clamp(0.85, 1.4),
                      min: 0.85,
                      max: 1.4,
                      divisions: 11,
                      label: '${(settings.fontScale * 100).round()}%',
                      onChanged: (v) => services.state
                          .updateSettings(settings.copyWith(fontScale: v)),
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.text_fields),
                    title: const Text('Render Markdown'),
                    subtitle: const Text(
                        'Format AI replies with headings, tables, code blocks.'),
                    value: settings.markdownRendering,
                    onChanged: (v) => services.state
                        .updateSettings(settings.copyWith(markdownRendering: v)),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.swap_vert_circle_outlined),
                    title: const Text('Stream replies by default'),
                    value: settings.streamingEnabled,
                    onChanged: (v) => services.state
                        .updateSettings(settings.copyWith(streamingEnabled: v)),
                  ),
                ],
              ),
              _Section(
                title: 'Network',
                children: [
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Connection timeout (seconds)'),
                    subtitle: Slider(
                      value: settings.connectTimeoutSeconds.toDouble(),
                      min: 10,
                      max: 120,
                      divisions: 22,
                      label: '${settings.connectTimeoutSeconds}s',
                      onChanged: (v) => services.state.updateSettings(
                          settings.copyWith(connectTimeoutSeconds: v.round())),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.hourglass_bottom),
                    title: const Text('Receive timeout (seconds)'),
                    subtitle: Slider(
                      value: settings.receiveTimeoutSeconds.toDouble(),
                      min: 30,
                      max: 600,
                      divisions: 57,
                      label: '${settings.receiveTimeoutSeconds}s',
                      onChanged: (v) => services.state.updateSettings(
                          settings.copyWith(receiveTimeoutSeconds: v.round())),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.replay),
                    title: const Text('Retry transient failures'),
                    subtitle: Slider(
                      value: settings.retryCount.toDouble().clamp(0, 3),
                      min: 0,
                      max: 3,
                      divisions: 3,
                      label: '${settings.retryCount}',
                      onChanged: (v) => services.state.updateSettings(
                          settings.copyWith(retryCount: v.round())),
                    ),
                  ),
                ],
              ),
              _Section(
                title: 'Developer',
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.terminal),
                    title: const Text('Request inspector'),
                    subtitle: const Text(
                        'Record sanitized request/response details for the '
                        'last request per chat (secrets are masked).'),
                    value: settings.requestInspectorEnabled,
                    onChanged: (v) =>
                        services.state.setRequestInspector(v),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.bug_report_outlined),
                    title: const Text('Sanitized diagnostic logs'),
                    subtitle: const Text(
                        'Writes non-sensitive operation logs. Keys and prompt '
                        'content are never logged.'),
                    value: settings.diagnosticLogging,
                    onChanged: (v) async {
                      AppLog.setEnabled(v);
                      await services.state.setDiagnosticLogging(v);
                    },
                  ),
                ],
              ),
              _Section(
                title: 'Data',
                children: [
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Export provider configurations'),
                    subtitle: const Text(
                        'JSON without API keys — keys are never exported.'),
                    onTap: () => services.transferService.shareProviders(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notes_outlined),
                    title: const Text('Export system prompts'),
                    onTap: () => services.transferService.sharePrompts(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_ethernet_outlined),
                    title: const Text('Export settings'),
                    subtitle: const Text('Appearance & network preferences.'),
                    onTap: () => services.transferService.shareSettings(settings),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.delete_sweep_outlined,
                        color: Theme.of(context).colorScheme.error),
                    title: Text('Clear chat history',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    subtitle: const Text('Deletes all local conversations.'),
                    onTap: () => _clearChats(context),
                  ),
                  ListTile(
                    leading: Icon(Icons.vpn_key_outlined,
                        color: Theme.of(context).colorScheme.error),
                    title: Text('Clear provider data',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    subtitle: const Text(
                        'Removes providers AND their stored API keys.'),
                    onTap: () => _clearProviders(context),
                  ),
                  ListTile(
                    leading: Icon(Icons.factory_outlined,
                        color: Theme.of(context).colorScheme.error),
                    title: Text('Clear all application data',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    subtitle:
                        const Text('Chats, providers, keys and custom prompts.'),
                    onTap: () => _clearEverything(context),
                  ),
                ],
              ),
              _Section(
                title: 'Privacy & architecture',
                children: [
                  const ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('Your keys stay on this device'),
                    subtitle: Text(
                        'API keys are stored with the operating system '
                        'encrypted storage (Android Keystore). The app never '
                        'sends them anywhere except to the provider you '
                        'choose, inside the request you asked for.',
                    ),
                  ),
                  const ListTile(
                    leading: Icon(Icons.hub_outlined),
                    title: Text('Direct connection — no proxy'),
                    subtitle: Text(
                        'The app is not a proxy and needs no account or '
                        'backend. Requests go straight from this device to '
                        'the selected AI provider. Messages are sent only '
                        'when you press send.',
                    ),
                  ),
                  const ListTile(
                    leading: Icon(Icons.public),
                    title: Text('Web/desktop note (CORS)'),
                    subtitle: Text(
                        'The Android app can call any provider directly. A '
                        'future web/PWA build would be limited by browser '
                        'CORS for providers that do not permit it — the app '
                        'will not tunnel your key through an insecure public '
                        'proxy.',
                    ),
                  ),
                ],
              ),
              _Section(
                title: 'About',
                children: [
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Universal AI Hub'),
                    subtitle: Text(
                        'Bring-your-own-key AI client. MVP 1.0 — OpenAI-'
                        'compatible, Anthropic, Gemini and Custom adapters.',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.policy_outlined),
                    title: const Text('Privacy policy'),
                    onTap: () => _privacyPolicy(context),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _clearChats(BuildContext context) async {
    final ok = await _confirm(context, 'Clear chat history?',
        'All conversations and messages will be deleted. Providers, prompts '
            'and settings are kept.');
    if (ok) {
      await AppScope.of(context).conversationRepository.clearAll();
      if (context.mounted) {
        showAppSnack(context, 'Chat history cleared.');
      }
    }
  }

  Future<void> _clearProviders(BuildContext context) async {
    final services = AppScope.of(context);
    final ok = await _confirm(context, 'Clear provider data?',
        'Every provider profile and its encrypted API key will be removed '
            'from this device.');
    if (ok) {
      await services.state.clearProviderData();
      if (context.mounted) {
        showAppSnack(context, 'Providers and stored keys removed.');
      }
    }
  }

  Future<void> _clearEverything(BuildContext context) async {
    final services = AppScope.of(context);
    final ok = await _confirm(
        context,
        'Clear ALL application data?',
        'Chats, providers, stored API keys and custom prompts will be '
            'deleted. This cannot be undone.',
        danger: true);
    if (ok) {
      await services.state.clearAllData();
      await services.secureStorage.wipeAll();
      await AppScope.of(context).conversationRepository.clearAll();
      if (context.mounted) {
        showAppSnack(context, 'All application data cleared.');
      }
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body,
      {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: danger ? const Icon(Icons.warning_amber) : null,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor:
                    danger ? Theme.of(ctx).colorScheme.error : null),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _privacyPolicy(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacy at a glance'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PolicyLine(
                  icon: Icons.lock_outline,
                  text: 'API keys are stored locally, encrypted with the OS '
                      'keychain. They are never sent to the app developer.'),
              SizedBox(height: 10),
              _PolicyLine(
                  icon: Icons.send_outlined,
                  text: 'Your messages are sent only to the AI provider you '
                      'select — the app is not a proxy and has no backend.'),
              SizedBox(height: 10),
              _PolicyLine(
                  icon: Icons.analytics_outlined,
                  text: 'No analytics or crash reporting of prompts or keys. '
                      'Diagnostic logs are opt-in and sanitized.'),
              SizedBox(height: 10),
              _PolicyLine(
                  icon: Icons.download_outlined,
                  text: 'Exports never include API keys. If key export is '
                      'ever added, it will require explicit confirmation and '
                      'encryption.'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }
}

class _PolicyLine extends StatelessWidget {
  const _PolicyLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: cs.primary)),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Column(children: children),
        ),
      ],
    );
  }
}
