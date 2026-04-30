import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/config/app_env.dart';
import '../shared/providers/app_env_provider.dart';
import '../shared/services/fcm_service.dart';

// Development entry point — uses DevEnv (local LAN server).
// Run with: flutter run -t lib/main/main_dev.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const env = DevEnv();
  // FCM: skipped in dev flavor (no google-services.json configured).
  await FcmService.initialize(env);
  runApp(
    ProviderScope(
      overrides: [appEnvProvider.overrideWithValue(env)],
      child: const SleepPadApp(),
    ),
  );
}
