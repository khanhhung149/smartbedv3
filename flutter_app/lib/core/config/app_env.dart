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
final class DevEnv extends AppEnv {
  const DevEnv()
      : super(
          apiBaseUrl: 'http://192.168.1.15:8000',
          wsBaseUrl: 'ws://192.168.1.15:8000',
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
