import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'shared/services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // FCM: no-op in dev (no google-services.json); logs warning and continues.
  // In production: add Firebase credentials + deps to enable push.
  await FcmService.initialize();
  runApp(
    const ProviderScope(
      child: SleepPadApp(),
    ),
  );
}
