// AppEnv sealed class: carries environment-specific config values.
// Use DevEnv for local development and ProdEnv for production builds.
// Injected via Riverpod — see lib/shared/providers/app_env_provider.dart.
sealed class AppEnv {
  const AppEnv({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.isDev,
  });

  final String apiBaseUrl;
  final String wsBaseUrl;
  final bool isDev;
}

/// Development flavor — points to local LAN server.
///
/// Defaults to `localhost:8000` (works for iOS Simulator + Android emulator that
/// can reach the host). Physical devices on the LAN need to override via
/// --dart-define since they can't resolve "localhost":
///
///   flutter run -t lib/main/main_dev.dart \
///     --dart-define=DEV_API_BASE_URL=http://192.168.1.11:8010 \
///     --dart-define=DEV_WS_BASE_URL=ws://192.168.1.11:8010
final class DevEnv extends AppEnv {
  const DevEnv()
      : super(
          apiBaseUrl: const String.fromEnvironment(
            'DEV_API_BASE_URL',
            defaultValue: 'http://localhost:8000',
          ),
          wsBaseUrl: const String.fromEnvironment(
            'DEV_WS_BASE_URL',
            defaultValue: 'ws://localhost:8000',
          ),
          isDev: true,
        );
}

/// Production flavor — points to the live API.
final class ProdEnv extends AppEnv {
  const ProdEnv()
      : super(
          apiBaseUrl: 'https://api.sleeppad.io',
          wsBaseUrl: 'wss://api.sleeppad.io',
          isDev: false,
        );
}
