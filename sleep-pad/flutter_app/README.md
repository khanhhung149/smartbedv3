# Sleep Tech — Flutter App

Mobile app for the Sleep Tech platform (sleeptech.me). Monitors sleep in real-time via BLE-provisioned devices.

## Requirements

- Flutter 3.x (stable channel)
- Dart 3.x
- Xcode 15+ (iOS builds)
- Android Studio / SDK (Android builds)

---

## Environments

| | Dev | Prod |
|---|---|---|
| Entry point | `lib/main/main_dev.dart` | `lib/main/main_prod.dart` |
| API | `http://localhost:8000` | `https://api.sleeptech.me` |
| WebSocket | `ws://localhost:8000` | `wss://api.sleeptech.me` |
| FCM | Skipped | Enabled |

---

## Run

```bash
# Development (local server)
flutter run -t lib/main/main_dev.dart

# Production
flutter run -t lib/main/main_prod.dart --release
```

---

## Build

### Android

```bash
# Debug APK (dev)
flutter build apk -t lib/main/main_dev.dart --debug

# Release APK (prod)
flutter build apk -t lib/main/main_prod.dart --release

# Release App Bundle — dùng khi upload lên Google Play
flutter build appbundle -t lib/main/main_prod.dart --release
```

### iOS

```bash
# Debug (dev)
flutter build ios -t lib/main/main_dev.dart --debug --no-codesign

# Release (prod) — cần Apple certificate
flutter build ios -t lib/main/main_prod.dart --release
```

---

## App IDs

| Platform | ID |
|---|---|
| Android `applicationId` | `me.sleeptech.app` |
| iOS Bundle ID | `me.sleeptech.app` |

---

## Localization

Strings quản lý trong `lib/l10n/`. Hỗ trợ EN và VI.

Sau khi chỉnh `.arb`, chạy:

```bash
flutter gen-l10n
```

---

## Codebase nhanh

```
lib/
├── main/
│   ├── main_dev.dart       # Entry point dev
│   └── main_prod.dart      # Entry point prod
├── core/
│   └── config/app_env.dart # DevEnv / ProdEnv config
├── features/               # Screens theo feature
├── shared/                 # Providers, widgets dùng chung
└── l10n/                   # ARB translation files
```
