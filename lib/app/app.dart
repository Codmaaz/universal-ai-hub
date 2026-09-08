import 'package:flutter/material.dart';

import '../core/models/app_settings.dart';
import '../core/theme/app_theme.dart';
import 'app_services.dart';
import 'shell/home_shell.dart';

/// Root widget. Reads the persisted [ThemePref] from app state and applies the
/// Material 3 theme.
class UniversalAiHubApp extends StatefulWidget {
  const UniversalAiHubApp({super.key, required this.services});

  final AppServices services;

  @override
  State<UniversalAiHubApp> createState() => _UniversalAiHubAppState();
}

class _UniversalAiHubAppState extends State<UniversalAiHubApp> {
  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: ListenableBuilder(
        listenable: widget.services.state,
        builder: (context, _) {
          final pref = widget.services.state.themePref;
          final themeMode = switch (pref) {
            ThemePref.light => ThemeMode.light,
            ThemePref.dark => ThemeMode.dark,
            ThemePref.system => ThemeMode.system,
          };
          return MaterialApp(
            title: 'Universal AI Hub',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeMode,
            builder: (context, child) {
              // Accessible text size scaling from settings.
              final scale = widget.services.state.settings.fontScale;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              );
            },
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}
