import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/api_client.dart';
import '../../core/config/app_env.dart';
import '../../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  dev.log('[FCM] Background message: ${message.messageId}', name: 'FcmService');
}

class FcmService {
  FcmService._();

  static bool _initialized = false;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Storage keys for local FCM token cache (Essen pattern)
  static const _keyFcmToken = 'fcm_token';
  static const _keyFcmSynced = 'fcm_token_synced';

  static Future<void> initialize(AppEnv env) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      if (env.isDev) {
        dev.log('[FCM] Dev flavor — skipping permission + token upload.', name: 'FcmService');
        return;
      }

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      _initialized = true;

      // When FCM rotates the token: save locally, reset synced flag, re-upload.
      messaging.onTokenRefresh.listen((token) async {
        final cached = await _storage.read(key: _keyFcmToken);
        if (cached != token) {
          await _storage.write(key: _keyFcmToken, value: token);
          await _storage.write(key: _keyFcmSynced, value: 'false');
          await _sendToBackend(token, env);
        }
      });

      FirebaseMessaging.onMessage.listen((msg) {
        dev.log('[FCM] Foreground: ${msg.notification?.title}', name: 'FcmService');
      });

      dev.log('[FCM] Initialized', name: 'FcmService');
    } catch (e, st) {
      dev.log('[FCM] Init failed: $e', name: 'FcmService', error: e, stackTrace: st);
    }
  }

  // Call after login. Skips upload if token hasn't changed since last sync.
  // On iOS, APNs may not be ready at login time — skip and rely on onTokenRefresh.
  static Future<void> syncAfterLogin(AppEnv env) async {
    if (!_initialized) {
      debugPrint('[FCM] syncAfterLogin skipped — not initialized');
      return;
    }

    // Skip if already synced with the same token
    final isSynced = await _storage.read(key: _keyFcmSynced) == 'true';
    if (isSynced) {
      debugPrint('[FCM] Token already synced — skipping');
      return;
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns == null) {
          debugPrint('[FCM] APNs not ready — onTokenRefresh will upload when ready');
          return;
        }
      }

      debugPrint('[FCM] getToken() calling...');
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('[FCM] getToken() result: ${token == null ? "NULL" : token.isEmpty ? "EMPTY" : "OK (${token.substring(0, 20)}...)"}');

      if (token == null || token.isEmpty) return;

      // Only upload if token changed
      final cached = await _storage.read(key: _keyFcmToken);
      if (cached == token) {
        // Token unchanged but wasn't marked synced — re-upload to be safe
        debugPrint('[FCM] Token unchanged, re-uploading to ensure sync');
      }

      await _sendToBackend(token, env);
      await _storage.write(key: _keyFcmToken, value: token);
      await _storage.write(key: _keyFcmSynced, value: 'true');
    } catch (e) {
      debugPrint('[FCM] syncAfterLogin failed: $e');
    }
  }

  // Call on logout — clears backend token, resets local sync state.
  static Future<void> clearToken(AppEnv env) async {
    if (!_initialized) return;
    try {
      final client = ApiClient(baseUrl: env.apiBaseUrl);
      await client.dio.patch('/auth/fcm-token', data: {'fcm_token': ''});
    } on DioException catch (_) {
      // Best-effort on logout — ignore failures.
    } finally {
      // Always reset sync state so next login re-registers the token
      await _storage.write(key: _keyFcmSynced, value: 'false');
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
