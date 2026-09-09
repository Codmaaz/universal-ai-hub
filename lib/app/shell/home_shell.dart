import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat/conversation_list_screen.dart';
import '../../features/prompts/prompts_screen.dart';
import '../../features/providers/providers_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/media/media_screen.dart';
import '../../core/models/media_item.dart';
import '../app_services.dart';

/// Primary navigation shell: Chats / Providers / Prompts / Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ConversationListScreen(),
          MediaScreen(kind: MediaKind.image),
          MediaScreen(kind: MediaKind.video),
          ProvidersScreen(),
          PromptsScreen(),
          SettingsScreen(),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              key: const ValueKey('new_chat_fab'),
              heroTag: 'newChatFab',
              onPressed: () => _startNewChat(context, services),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('New chat'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.image_outlined),
            selectedIcon: Icon(Icons.image),
            label: 'Images',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie),
            label: 'Videos',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns),
            label: 'Providers',
          ),
          NavigationDestination(
            icon: Icon(Icons.notes_outlined),
            selectedIcon: Icon(Icons.notes),
            label: 'Prompts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Future<void> _startNewChat(BuildContext context, AppServices services) async {
    final providerId = services.state.settings.lastUsedProviderId;
    final model = services.state.settings.lastUsedModel ?? '';
    final conv = await services.conversationRepository.create(
      providerId: providerId ?? '',
      model: model,
      title: 'New chat',
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: conv.id),
      ),
    );
    // Refresh conversation list when returning.
    if (context.mounted) {
      setState(() {});
    }
  }
}

/// Snackbar helper used across the app.
void showAppSnack(BuildContext context, String message,
    {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
        backgroundColor: error
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.inverseSurface,
        duration: const Duration(seconds: 4),
      ),
    );
}

/// Screen/page title shown in app bars.
const String kAppName = AppConstants.appName;
