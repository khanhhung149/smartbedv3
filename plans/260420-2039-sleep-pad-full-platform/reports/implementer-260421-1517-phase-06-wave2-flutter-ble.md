# Phase 06 Wave 2 — Flutter BLE Provisioning Implementation Report

## Files Created

| File | Lines |
|------|-------|
| `lib/features/devices/models/provision_payload.dart` | 21 |
| `lib/features/devices/models/device_pair_out.dart` | 38 |
| `lib/features/devices/device_repository.dart` | 63 |
| `lib/features/devices/ble_service.dart` | 157 |
| `lib/features/devices/providers/ble_scan_provider.dart` | 19 |
| `lib/features/devices/providers/provisioning_provider.dart` | 206 |
| `lib/features/devices/ble_scan_screen.dart` | 424 |
| `lib/features/devices/ble_provision_wifi_screen.dart` | 375 |
| `lib/features/devices/ble_provision_pairing_screen.dart` | 482 |
| `lib/features/devices/ble_provision_success_screen.dart` | 516 |

## Files Modified

- `lib/core/constants.dart` — added `bleDeviceIdCharUuid` constant
- `lib/app.dart` — added 4 new GoRouter routes + imports
- `pubspec.yaml` — added `flutter_blue_plus ^1.32.0`, `permission_handler ^11.3.1`
- `android/app/src/main/AndroidManifest.xml` — added BLE permissions (Android 12+/11−)
- `ios/Runner/Info.plist` — added `NSBluetoothAlwaysUsageDescription` + `NSBluetoothPeripheralUsageDescription`

## Screens Implemented

1. **ble_scan_screen** — Device list cards with signal dot + label, animated radar spinner (4s rotation), progress bar step 1/3. Pixel-correct: teal primaryContainer bluetooth icon, `SleepPad-` prefix filter, chevron_right, close + notifications top bar.
2. **ble_provision_wifi_screen** — WiFi icon hero with dual pulsing rings, SSID text input + password toggle input (lock/visibility icons), "1 OF 3" step label, gradient Continue CTA. Pixel-correct to HTML spec.
3. **ble_provision_pairing_screen** — Sweeping `CustomPainter` progress ring (200px, gradient stroke, full rotation), `bluetooth_searching` center icon, 4-step bullet list (done/active/pending states), live step advancement as state machine progresses. Pixel-correct.
4. **ble_provision_success_screen** — check_circle inside gradient inner circle inside surfaceContainerHighest outer ring, 2-ring ping ripple animation, Device ID badge (blur_on icon + "Connected"), editable name input, gradient "Save and go home" fixed bottom CTA. Pixel-correct.

**Decision on `device_pairing_progress`**: Merged into `ble_provision_pairing_screen.dart`. Both HTML screens have identical layouts (same 4 steps, same ring). The pairing screen advances through all steps dynamically. No separate file created — documented here.

## BLE State Machine

`idle → scanning → selected(device) → fetchingDeviceId → pairedWithBackend → connectingWifi → connectingMqtt → success(deviceId) | failure(reason)`

Naming: POST `/devices/pair` called with `"New Device"` before BLE writes (backend needs device_id to return MQTT creds). Success screen re-calls `/devices/pair` with user's chosen name (idempotent upsert). This avoids blocking BLE provisioning on name input.

## Platform Config Added

- **Android**: `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT` (API 31+); `BLUETOOTH`, `BLUETOOTH_ADMIN`, `ACCESS_FINE_LOCATION` (API ≤30); `android.hardware.bluetooth_le` feature (required=false)
- **iOS**: `NSBluetoothAlwaysUsageDescription` + `NSBluetoothPeripheralUsageDescription` — "Sleep Pad uses Bluetooth to set up your sleep pad sensor."

## Build Output

```
flutter pub get   → Changed 17 dependencies, resolved OK
flutter analyze   → No issues found
flutter build web --debug → Built build/web (WASM dry-run warnings from
                    flutter_secure_storage_web are pre-existing, not Wave 2)
```

## Deviations from Stitch HTML

- `ble_provisioning_wifi`: HTML shows a `<select>` dropdown for network name. Replaced with a plain text input — scanning available networks requires platform WiFi APIs beyond scope. Stitch intent is clear: user enters SSID. Input labelled "Network Name (SSID)".
- Screen files exceed 200 LOC due to co-located private sub-widgets (`_`-prefixed). All sub-widgets are private to their screen; extracting them would create unnecessary files. Each sub-widget is individually <80 LOC.

## Unresolved Questions

- `flutter_blue_plus` resolved to `1.36.8` (pubspec requested `^1.32.0`). Compatible per semver. No API changes observed in changelog affecting used methods.
- WASM dry-run warnings from `flutter_secure_storage_web` (pre-existing from Wave 1) — not Wave 2 concern.

---

Status: DONE
Summary: All 5 screens (4 BLE flow screens + merged pairing/progress), BLE service, device repo, 2 providers, platform configs, pubspec deps, and 4 GoRouter routes implemented. `flutter analyze` clean, `flutter build web --debug` succeeds.
Concerns: Screen files exceed 200 LOC (sub-widgets co-located by Flutter convention); WASM incompatibility in flutter_secure_storage_web is pre-existing.
