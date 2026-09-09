import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final services = AppServices.create();
  // Loads settings, seeds built-in prompts and pulls providers.
  await services.init();

  runApp(UniversalAiHubApp(services: services));
}
