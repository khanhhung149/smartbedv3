# Phase 06 Flutter Review — Scaffold + Auth + BLE Provisioning

Review scope: wave 1 + wave 2 (29 files). Read fully: `ble_service.dart`, `provisioning_provider.dart`, `login_screen.dart`, `ble_provision_pairing_screen.dart`. Spot-checked `ble_scan_screen.dart`, `ble_provision_wifi_screen.dart`, `ble_provision_success_screen.dart`, `register_screen.dart`, `constants.dart`, `ble_scan_provider.dart`, `pubspec.yaml`, Android manifest, iOS Info.plist, login HTML.

## CRITICAL

### C1. BLE runtime permissions never requested → Android 12+ scan will silently fail
`permission_handler: ^11.3.1` is in `pubspec.yaml` but `grep -r permission_handler lib/` = zero matches. Manifest declares `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` (runtime permissions on API 31+), but `BleScanScreen.initState` never calls `Permission.bluetoothScan.request()` / `Permission.bluetoothConnect.request()` / `Permission.locationWhenInUse.request()` (needed on API ≤30). `FlutterBluePlus.startScan` will return empty on Android 12+ with no visible error, leaving the user stuck on "Searching for nearby devices..." forever. On iOS same issue: no permission prompt is triggered before scan starts, so the first scan after install will hang until user backgrounds the app.
**Fix:** In `BleScanScreen.initState`, call permission_handler to request scan/connect/location before invoking `ref.watch(bleScanProvider)`. Handle denial with a "open settings" CTA.

### C2. Protocol write order mismatch (docs vs code) — low real-world impact but contract violation
Protocol doc §3 step 4 lists order: `SSID → password → ServerHost → MqttScheme → MqttUser → MqttPassword`. `ble_service.dart:73-78` matches exactly. OK. Verified — **not an issue**, flagged then cleared. Keep last-write trigger = `MqttPassword`.

## HIGH

### H1. BLE device not disconnected if user navigates back mid-provision
`BleProvisionPairingScreen.initState` kicks `startProvisioning` on post-frame. If user taps back while `_ble.provision(device, ...)` is mid-await (e.g. during WiFi connect 30s wait), `_AppBar.onBack` calls `reset()` and `context.pop()` — but the async chain in `ProvisioningNotifier.startProvisioning` keeps running. The active `BluetoothDevice.connect()` session is only cleaned up when `provision()` reaches its `finally` (disconnect). Meanwhile the `Completer` is orphaned, `setNotifyValue(true)` subscription leaks, and Riverpod receives `state = ...` on a notifier whose screen is gone (harmless — notifier is a singleton, but state machine enters inconsistent `ProvisioningFailure` once the 60s timer fires with no UI watching). ESP32 is now paired but Flutter believes it failed. Next attempt will call `device.connect()` on a device that already has a live GATT link → plugin throws.
**Fix:** Either make `startProvisioning` cancellation-aware (accept a `CancelToken`/check state before each `state =` write), or in `dispose` of the pairing screen call `ref.read(provisioningProvider.notifier).cancel()` which internally calls `device.disconnect()`. At minimum, wrap the back button handler to `await ble.disconnect(device)` before popping.

### H2. `ble_service.scanForDevices` starts scan as a side-effect of stream construction
Line 23–26: calling `scanForDevices()` invokes `FlutterBluePlus.startScan` **before** the caller even subscribes. With `StreamProvider.autoDispose` this is usually fine, but the scan timer is decoupled from subscription lifetime — if the stream is listened twice in quick succession (hot reload, route rebuild), two scans stack. Also `scanResults` is a *global* broadcast stream shared with any other consumer; filtering here means any stale results from a prior scan still leak through on reconnect.
**Fix:** Gate startScan on `isScanningNow == false`, and make the stream a controller that calls `stopScan()` in `onCancel`. Or at minimum call `await FlutterBluePlus.stopScan()` before `startScan` inside the method.

### H3. `ble_provision_wifi_screen.dart` passes `BluetoothDevice` via GoRouter `extra` as `Map<String, dynamic>` — type-unsafe
Line 67–73: `extra: {'device': widget.device, 'ssid': ..., 'password': ...}`. On the receiving side (pairing screen), casts are implicit via the constructor. GoRouter `extra` is not serialized on deep-link restoration — if the OS reloads the route from a system killed state, `device` is `null` and the `required` constructor throws. Login/register `context.go('/home')` is fine; BLE flow is transient so less critical, but still a lurking NPE.
**Fix:** Add a null check and route back to scan screen with a friendly error if extra is lost.

### H4. `provisioning_provider.startProvisioning` swallows all exceptions to string
Line 168–170: `catch (e) { state = ProvisioningFailure(e.toString()); }` — any exception including raw `DioException` with status=401 (e.g. JWT expired at `POST /devices/pair`) shows the raw message (containing URL + headers on Dio) to the user. Potential info leak; also unfriendly.
**Fix:** Pattern-match on `BleException`, `DioException` (map 401→"session expired, please log in", 409/422→"device already paired"), fall back to generic "Something went wrong" for unknown.

### H5. `_pollUntilOnline` swallows all errors silently and runs 30s even on auth failure
Line 195–197: every network error during polling is ignored. If JWT expired between `pairDevice` and polling (unlikely in 30s but possible on slow network), Flutter will poll a 401 loop for 30s then return false and treat as success — user sees success screen for a device the backend forgot. Minor because of the short window.
**Fix:** On 401 specifically, break the loop and surface auth failure.

## SUGGESTIONS

### S1. File size rule (≤200 LOC) — acceptable deviation
`ble_provision_success_screen.dart` = 516, `ble_provision_pairing_screen.dart` = 482, `ble_scan_screen.dart` = 424. Each file's public screen class is ~60–160 LOC; the rest are private sub-widgets. For Flutter pixel-parity screens this colocation aids readability (one flow = one file). **Accept as-is** — do not split for the sake of line count. If you ever want to split, pull `_SuccessHero`, `_PairingRing`, and the custom painters into `shared/widgets/`.

### S2. `bleScanProvider` subscribes in `ref.listen` + mutates local `_devices` map — off-pattern
`ble_scan_screen.dart:61-69` listens to the StreamProvider and manually dedups into a `Map` in widget state. Riverpod-idiomatic would be a `StateNotifier`/`Notifier` that exposes `List<ScanResult>`. Not broken, just unusual.

### S3. Fidelity check — login screen vs login HTML
Spot-check: HTML uses `bg-background` (#101419) → `AppColors.background`. `text-3xl` = 30px → code uses `AppTextSize.xl3` (assumed 30). "Welcome back" weight is `font-medium` (500) → matches `AppFontWeight.medium`. Button "Sign in" gradient `rounded-full` → `PrimaryButton`. **Pass.** One minor: HTML centers branding with `mt-8 mb-16` (32+64=96 total); code has `SizedBox(32) + SizedBox(64) = 96`. Matches.

### S4. Fidelity check — pairing screen ring spec
HTML SVG uses `r=46, strokeDasharray=289, strokeDashoffset=144` (half-circle fill). Code's `_RingPainter` draws a 180° sweep (`sweepAngle = π`) rotating around full circle — visually equivalent; Flutter doesn't do dash offsets easily. **Acceptable.**

### S5. `withValues(alpha:)` Dart 3 requirement
`pubspec.yaml` SDK constraint is `^3.11.1` — Flutter 3.27+ which bundles Dart 3.6+. `withValues` was introduced in Flutter 3.27 / Dart 3.6. **OK.** No action.

### S6. `constants.dart` hardcodes `http://192.168.1.100:8000`
Dev-only. Fine for Phase 06 but flag for Phase 07+ — should come from `--dart-define` or a compile-time env.

### S7. Forgot-password button is a no-op
`login_screen.dart:196`: `onPressed: () {}`. Either hide until implemented or show a "coming soon" snackbar — silent dead buttons look like bugs in QA.

### S8. `startProvisioning` → first state write is `ProvisioningFetchingDeviceId` — skips `ProvisioningScanning` and `ProvisioningSelected` transitions
The enum has 9 states but only 6 are emitted by the provider (never `Scanning`, `Selected` written by `startProvisioning`; `selectDevice` sets it but nothing reads). Consider removing the unused states or route scan screen through them for completeness. **YAGNI-acceptable.**

## Positive Observations

- Protocol compliance: `readDeviceId` runs BEFORE writes (§3 step 3), `pairDevice` call precedes GATT writes (so MQTT creds in hand first), 60s NOTIFY timeout matches §3 step 6, status values `connected`/`wifi_failed`/`mqtt_failed` match table.
- GATT service/char UUIDs in `constants.dart` match the protocol doc table exactly.
- BLE service `finally` blocks always disconnect — no stuck connections on success path.
- JWT auto-login after register is correct (`AuthRepository().register` → `login` → `setToken` → `context.go('/home')`).
- Android manifest correctly uses `neverForLocation` flag and gates legacy permissions by `maxSdkVersion=30`. iOS Info.plist has both `NSBluetoothAlwaysUsageDescription` and the legacy `NSBluetoothPeripheralUsageDescription`.
- Sealed state machine + Riverpod `Notifier` is clean; `ref.listen` on terminal states in pairing screen is the right pattern.

## Unresolved Questions

1. Should `reset()` also `disconnect()` the active BluetoothDevice? Currently it only clears state.
2. Protocol doc says poll `/devices/mine` "every 2s until online=true" — no max. Code caps at 15 iterations (30s). Is 30s acceptable product spec, or should it match BLE's 60s window?
3. `renameDevice` failure is silently swallowed (line 181–183). Should user get a toast if rename fails after pairing succeeds?

---

**Status:** DONE_WITH_CONCERNS
**Summary:** BLE protocol contract is correctly implemented (writes order, readDeviceId-before-writes, 60s NOTIFY). One critical gap: no runtime permission requests → scan will silently fail on Android 12+ and iOS first-run. Mid-provision cancellation leaks the GATT connection. Fidelity to Stitch HTML is solid.
**Concerns/Blockers:** C1 must be fixed before real-device testing. H1–H5 before production.
