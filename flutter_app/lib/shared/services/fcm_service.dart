import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import '../../core/api_client.dart';

// FCM push notification service.
//
// Dev no-op design: Firebase packages are NOT included in pubspec.yaml for this
// POC because google-services.json / GoogleService-Info.plist are absent in the
// development environment. initialize() is a no-op that logs a warning and
// returns cleanly. When Firebase project credentials are added in production:
//   1. Add firebase_core, firebase_messaging, flutter_local_notifications to pubspec.yaml
//   2. Add google-services.json (Android) and GoogleService-Info.plist (iOS)
//   3. Uncomment the implementation below and remove the no-op guard.
//
// The upload-token method is wired to PATCH /auth/fcm-token regardless — it
// will simply never be called in dev until initialize() succeeds.

class FcmService {
  FcmService._();

  // ignore: prefer_final_fields — set to true when Firebase is wired in production
  static bool _initialized = false;

  // Call once from main() after WidgetsFlutterBinding.ensureInitialized().
  // Safe to call even when Firebase is not configured — logs warning, no-ops.
  static Future<void> initialize() async {
    try {
      // Production implementation (requires Firebase credentials):
      //
      // await Firebase.initializeApp(
      //   options: DefaultFirebaseOptions.currentPlatform,
      // );
      // final messaging = FirebaseMessaging.instance;
      // await messaging.requestPermission(alert: true, badge: true, sound: true);
      //
      // final token = await messaging.getToken();
      // if (token != null) await uploadToken(token);
      // messaging.onTokenRefresh.listen(uploadToken);
      //
      // // Foreground: show local notification
      // FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      //
      // // Background + terminated: handled by top-level _firebaseMessagingBackgroundHandler
      //
      // _initialized = true;
      // dev.log('[FCM] Initialized successfully', name: 'FcmService');

      dev.log(
        '[FCM] Firebase not configured — running in no-op mode. '
        'Add google-services.json and Firebase deps to enable push.',
        name: 'FcmService',
      );
    } catch (e, st) {
      // Graceful no-op: app continues to work without push notifications.
      dev.log(
        '[FCM] Initialization failed: $e',
        name: 'FcmService',
        error: e,
        stackTrace: st,
      );
    }
  }

  // Upload FCM token to backend so server can push to this device.
  // Called after login and on token refresh.
  static Future<void> uploadToken(String token) async {
    if (!_initialized) return;
    try {
      final client = ApiClient();
      await client.dio.patch(
        '/auth/fcm-token',
        data: {'fcm_token': token},
      );
      dev.log('[FCM] Token uploaded', name: 'FcmService');
    } on DioException catch (e) {
      dev.log(
        '[FCM] Token upload failed: ${e.response?.statusCode}',
        name: 'FcmService',
        error: e,
      );
      // Non-fatal: push may not work but app functions normally.
    }
  }

  // Clear FCM token on logout so stale tokens are not stored server-side.
  static Future<void> clearToken() async {
    if (!_initialized) return;
    try {
      final client = ApiClient();
      await client.dio.patch('/auth/fcm-token', data: {'fcm_token': ''});
    } on DioException catch (_) {
      // Best-effort — ignore failures on logout path.
    }
  }

  // Production foreground message handler (uncomment when Firebase is wired).
  // static Future<void> _handleForegroundMessage(RemoteMessage message) async {
  //   final data = message.data;
  //   // Show local notification via flutter_local_notifications
  //   // Deep-link: if data contains device_id + metric, navigate to alert detail
  //   dev.log('[FCM] Foreground message: ${message.messageId}', name: 'FcmService');
  // }
}

// Top-level background message handler — must be a top-level function, not a
// class method. Required by firebase_messaging for background/terminated state.
// Uncomment when Firebase deps are added:
//
// @pragma('vm:entry-point')
// Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
//   dev.log('[FCM] Background message: ${message.messageId}', name: 'FcmService');
// }
