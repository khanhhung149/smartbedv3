import 'package:shared_preferences/shared_preferences.dart';

/// Where the app points and what it authenticates with.
///
/// Values come from `--dart-define` at build time and can be overridden at
/// runtime from the settings screen, so a tester can retarget a build without
/// a toolchain. Nothing here is ever written to a file in the repo: the dev
/// token is a real 30-day credential.
class AppConfig {
  const AppConfig({
    required this.baseUrl,
    required this.deviceId,
    required this.devToken,
  });

  final String baseUrl;
  final String deviceId;
  final String devToken;

  /// 10.0.2.2 is how the Android emulator reaches the host machine's localhost.
  /// A physical phone needs the host's LAN IP instead — see app/README.md.
  static const String _defaultBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
  static const String _defaultDeviceId =
      String.fromEnvironment('DEVICE_ID', defaultValue: '');
  static const String _defaultDevToken =
      String.fromEnvironment('DEV_TOKEN', defaultValue: '');

  static const _kBaseUrl = 'cfg.baseUrl';
  static const _kDeviceId = 'cfg.deviceId';
  static const _kDevToken = 'cfg.devToken';

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppConfig(
      baseUrl: prefs.getString(_kBaseUrl) ?? _defaultBaseUrl,
      deviceId: prefs.getString(_kDeviceId) ?? _defaultDeviceId,
      devToken: prefs.getString(_kDevToken) ?? _defaultDevToken,
    );
  }

  static Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, config.baseUrl);
    await prefs.setString(_kDeviceId, config.deviceId);
    await prefs.setString(_kDevToken, config.devToken);
  }

  AppConfig copyWith({String? baseUrl, String? deviceId, String? devToken}) =>
      AppConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        deviceId: deviceId ?? this.deviceId,
        devToken: devToken ?? this.devToken,
      );

  bool get isComplete =>
      baseUrl.isNotEmpty && deviceId.isNotEmpty && devToken.isNotEmpty;
}
