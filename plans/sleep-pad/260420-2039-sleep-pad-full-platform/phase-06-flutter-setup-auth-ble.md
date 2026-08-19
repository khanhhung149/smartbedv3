---
phase: 06
status: completed
priority: critical
effort: large
sub_project: flutter
blockedBy: [phase-04]
---

# Phase 06: Flutter App — Setup, Auth & BLE Provisioning

## Overview

Scaffold Flutter project, implement JWT auth screens (register/login), and BLE provisioning flow that writes WiFi credentials + server URL to ESP32 GATT characteristics.

## Requirements

- Flutter 3+ project with clean structure
- Register + Login screens with JWT auth
- Persistent token storage (flutter_secure_storage)
- BLE scan → connect to "SleepPad-XXXX" → write SSID/password/server URL
- Poll /devices/mine after provisioning to confirm pairing
- Navigation: GoRouter with auth guard

## Project Structure

```
flutter_app/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── app.dart                     ← MaterialApp + GoRouter
│   ├── core/
│   │   ├── api-client.dart          ← Dio HTTP client, JWT interceptor
│   │   ├── auth-storage.dart        ← flutter_secure_storage wrapper
│   │   ├── constants.dart           ← BLE UUIDs, API base URL
│   │   └── app-theme.dart           ← dark theme, color palette
│   ├── features/
│   │   ├── auth/
│   │   │   ├── auth-repository.dart
│   │   │   ├── login-screen.dart
│   │   │   └── register-screen.dart
│   │   ├── devices/
│   │   │   ├── device-repository.dart
│   │   │   ├── ble-scan-screen.dart
│   │   │   └── ble-provision-screen.dart
│   │   ├── home/                    ← Phase 07
│   │   ├── history/                 ← Phase 07
│   │   ├── alerts/                  ← Phase 08
│   │   ├── sharing/                 ← Phase 08
│   │   └── settings/                ← Phase 08
│   └── shared/
│       ├── widgets/
│       │   └── loading-button.dart
│       └── providers/
│           └── auth-provider.dart   ← Riverpod: current user + token
```

## Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter_blue_plus: ^1.32.0
  dio: ^5.7.0
  flutter_secure_storage: ^9.2.2
  flutter_riverpod: ^2.5.1
  go_router: ^14.2.0
  fl_chart: ^0.69.0
  firebase_core: ^3.6.0
  firebase_messaging: ^15.1.3
  permission_handler: ^11.3.1
```

## BLE Provisioning Flow

```
1.  Request BLE + Location permissions
2.  Scan for devices advertising "SleepPad-" prefix
3.  Show list → user taps one (advertised name embeds device_id suffix)
4.  POST /devices/pair → receive DevicePairOut { mqtt_username, mqtt_password,
                                                 mqtt_host, mqtt_scheme, ... }
5.  Connect GATT
6.  Discover services → find kBleServiceUuid
7.  Write characteristics SEQUENTIALLY (await each; order matters):
      SSID → Password → ServerHost(mqtt_host) →
      MqttScheme → MqttUser → MqttPassword   (last write triggers ESP32 connect)
8.  Subscribe to Status (notify)
9.  Wait up to 60s for Status == "connected"   (show error on wifi_failed / mqtt_failed)
10. Disconnect BLE
11. Poll /devices/mine every 2s until online:true → navigate Home
```

**Note:** `/devices/pair` is called BEFORE the BLE GATT writes so Flutter has the MQTT creds to ship to the ESP32. The backend pairs the device record immediately and lazily awaits MQTT LWT online/offline updates.

## BLE UUIDs (constants.dart)

**Authoritative contract:** [`docs/protocols/ble-provisioning-and-mqtt-auth.md`](../../../docs/sleep-pad/protocols/ble-provisioning-and-mqtt-auth.md).

```dart
const kBleServiceUuid         = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const kBleSsidCharUuid        = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
const kBlePasswordCharUuid    = 'beb5483e-36e1-4688-b7f5-ea07361b26a9';
const kBleServerHostCharUuid  = 'beb5483e-36e1-4688-b7f5-ea07361b26aa';
const kBleStatusCharUuid      = 'beb5483e-36e1-4688-b7f5-ea07361b26ab';
const kBleMqttUserCharUuid    = 'beb5483e-36e1-4688-b7f5-ea07361b26ac';
const kBleMqttPassCharUuid    = 'beb5483e-36e1-4688-b7f5-ea07361b26ad';
const kBleMqttSchemeCharUuid  = 'beb5483e-36e1-4688-b7f5-ea07361b26ae';
```

## Auth Flow

```dart
// auth-repository.dart
Future<String> login(String email, String password) async {
  final res = await _dio.post('/auth/login', data: {...});
  final token = res.data['access_token'];
  await _storage.write(key: 'jwt', value: token);
  return token;
}
```

GoRouter redirect: if no token in secure storage → redirect to /login.

## Related Files

- Create: `flutter_app/` (full project)
- Create: `flutter_app/pubspec.yaml`
- Create: `flutter_app/lib/main.dart`
- Create: `flutter_app/lib/app.dart`
- Create: `flutter_app/lib/core/api-client.dart`
- Create: `flutter_app/lib/core/auth-storage.dart`
- Create: `flutter_app/lib/core/constants.dart`
- Create: `flutter_app/lib/core/app-theme.dart`
- Create: `flutter_app/lib/features/auth/auth-repository.dart`
- Create: `flutter_app/lib/features/auth/login-screen.dart`
- Create: `flutter_app/lib/features/auth/register-screen.dart`
- Create: `flutter_app/lib/features/devices/device-repository.dart`
- Create: `flutter_app/lib/features/devices/ble-scan-screen.dart`
- Create: `flutter_app/lib/features/devices/ble-provision-screen.dart`
- Read:   `docs/protocols/ble-provisioning-and-mqtt-auth.md` (authoritative BLE + MQTT contract)
- Create: `flutter_app/lib/shared/providers/auth-provider.dart`

## Implementation Steps

1. `flutter create flutter_app --org com.sleeppad` (or manually scaffold)
2. Write `pubspec.yaml` with all dependencies
3. Write `core/constants.dart` — BLE UUIDs + API base URL from env
4. Write `core/app-theme.dart` — dark theme (deep navy/slate, accent teal)
5. Write `core/auth-storage.dart` — secure token read/write/delete
6. Write `core/api-client.dart` — Dio + JWT interceptor (auto attach Bearer)
7. Write `shared/providers/auth-provider.dart` — Riverpod auth state
8. Write `auth/auth-repository.dart` + login/register screens
9. Write `app.dart` — GoRouter with auth guard redirect
10. Write `devices/device-repository.dart` — /devices/mine, /devices/pair
11. Write `devices/ble-scan-screen.dart` — flutter_blue_plus scan + list
12. Write `devices/ble-provision-screen.dart` — GATT write flow + status polling
13. `flutter pub get` → `flutter build apk --debug` → verify compiles
14. Test on Android: BLE scan → provision → device appears in backend

## Todo

- [x] Flutter project scaffold
- [x] pubspec.yaml with all deps
- [x] core/ (theme, api-client, auth-storage, constants)
- [x] auth screens (login, register)
- [x] GoRouter + auth guard
- [x] BLE scan screen
- [x] BLE provisioning screen (GATT write flow)
- [x] `flutter build` verify 0 errors
- [x] BLE provisioning end-to-end test

## Success Criteria

- App compiles without errors on Flutter 3+
- Login → JWT stored securely → app navigates to home stub
- BLE scan shows "SleepPad-XXXX" devices
- Provisioning flow completes → Status char notifies "connected"
- Device appears in /devices/mine after provisioning

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| iOS BLE entitlements | NSBluetoothAlwaysUsageDescription in Info.plist; test on real device |
| BLE + Location permission on Android 12+ | Use permission_handler, request BLUETOOTH_SCAN + BLUETOOTH_CONNECT |
| GATT write order matters | Write chars sequentially with await, not in parallel |

## Security

- JWT stored in flutter_secure_storage (Keychain iOS / Keystore Android)
- Server URL configurable (not hardcoded) — supports dev and prod environments
