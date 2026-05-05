import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../core/api_client.dart';
import '../../core/config/app_env.dart';
import '../../firebase_options.dart';

// Top-level background handler — must be top-level, registered before runApp.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  dev.log('[FCM] Background message: ${message.messageId}', name: 'FcmService');
}

class FcmService {
  FcmService._();

  static bool _initialized = false;

  // Call once from main() after WidgetsFlutterBinding.ensureInitialized().
  // Dev flavor: initializes Firebase but skips permission request and token upload.
  static Future<void> initialize(AppEnv env) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      if (env.isDev) {
        dev.log('[FCM] Dev flavor — Firebase init done, skipping permission request.', name: 'FcmService');
        return;
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      _initialized = true;

      // Token refresh — re-upload when FCM rotates the token.
      messaging.onTokenRefresh.listen((token) => _sendToBackend(token, env));

      // Foreground messages — shown as local notification (optional future work).
      FirebaseMessaging.onMessage.listen((msg) {
        dev.log('[FCM] Foreground: ${msg.notification?.title}', name: 'FcmService');
      });

      dev.log('[FCM] Initialized', name: 'FcmService');
    } catch (e, st) {
      dev.log('[FCM] Init failed: $e', name: 'FcmService', error: e, stackTrace: st);
    }
  }

  // Call after login / verify-email so FCM token is sent with a valid JWT.
  // On iOS, APNs token may not be ready yet at login time — skip and let
  // onTokenRefresh handle the upload once APNs is available.
  static Future<void> syncAfterLogin(AppEnv env) async {
    if (!_initialized) {
      debugPrint('[FCM] syncAfterLogin skipped — not initialized');
      return;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns == null) {
          debugPrint('[FCM] APNs not ready yet — onTokenRefresh will upload when ready');
          return;
        }
      }
      debugPrint('[FCM] getToken() calling...');
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('[FCM] getToken() result: ${token == null ? "NULL" : token.isEmpty ? "EMPTY STRING" : "OK (${token.substring(0, 20)}...)"}');
      if (token != null && token.isNotEmpty) {
        await _sendToBackend(token, env);
      }
    } catch (e) {
      debugPrint('[FCM] syncAfterLogin failed: $e');
    }
  }

  // Clear token on logout — backend stops sending pushes to this device.
  static Future<void> clearToken(AppEnv env) async {
    if (!_initialized) return;
    try {
      final client = ApiClient(baseUrl: env.apiBaseUrl);
      await client.dio.patch('/auth/fcm-token', data: {'fcm_token': ''});
    } on DioException catch (_) {
      // Best-effort on logout path — ignore failures.
    }
  }

  static Future<void> _sendToBackend(String token, AppEnv env) async {
    try {
      final client = ApiClient(baseUrl: env.apiBaseUrl);
      await client.dio.patch('/auth/fcm-token', data: {'fcm_token': token});
      dev.log('[FCM] Token uploaded', name: 'FcmService');
    } on DioException catch (e) {
      dev.log('[FCM] Upload failed: ${e.response?.statusCode}', name: 'FcmService');
    }
  }
}
