import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_router.dart';
import 'core/app_theme.dart';
import 'data/local/database_factory.dart';
import 'features/radar/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Vietnamese date formatting has to be initialised before any DateFormat('..',
  // 'vi') runs, or every card throws on first build.
  await initializeDateFormatting('vi');
  await initDatabaseFactory();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const SmartBedApp(),
    ),
  );
}

class SmartBedApp extends StatelessWidget {
  const SmartBedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SmartBed',
      theme: buildAppTheme(),
      routerConfig: buildRouter(),
      debugShowCheckedModeBanner: false,
    );
  }
}
