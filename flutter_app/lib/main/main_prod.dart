import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/config/app_env.dart';
import '../shared/providers/app_env_provider.dart';
import '../shared/services/fcm_service.dart';

// Production entry point — uses ProdEnv (live API at api.sleeppad.io).
// Run with: flutter run -t lib/main/main_prod.dart
// Build with: flutter build apk -t lib/main/main_prod.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const env = ProdEnv();
  await FcmService.initialize(env);
  runApp(
    ProviderScope(
      overrides: [appEnvProvider.overrideWithValue(env)],
      child: const SleepPadApp(),
    ),
  );
}
