// Generated from Firebase console config files.
// Android values from: android/app/google-services.json
// iOS values from: ios/Runner/GoogleService-Info.plist
// Firebase project: sleeptechdev

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions not supported on ${defaultTargetPlatform.name}',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBPx4dcc6aZvJxB8IPpVc1x7PC8mb78cZs',
    appId: '1:552649412097:android:3260299625c040801fba00',
    messagingSenderId: '552649412097',
    projectId: 'sleeptechdev',
    storageBucket: 'sleeptechdev.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyASrmczaILW3ar0Ks1D25Dl_Fl5D-6yWiI',
    appId: '1:552649412097:ios:402625f09f0e0d451fba00',
    messagingSenderId: '552649412097',
    projectId: 'sleeptechdev',
    storageBucket: 'sleeptechdev.firebasestorage.app',
  );
}
