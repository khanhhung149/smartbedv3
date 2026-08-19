# Phase 06: Flutter Scaffold, Auth Flows, BLE Provisioning

**Date**: 2026-04-21 13:00
**Severity**: Medium
**Component**: Flutter app (scaffold, authentication UI, BLE integration)
**Status**: Resolved

## What Shipped

Flutter app baseline at `flutter_app/`. 29 Dart files across two subagent waves. 10 screens pixel-matched from Google Stitch HTML exports (Tailwind CSS + PNG reference). `flutter analyze` clean; `flutter build web --debug` succeeds. APK/iOS blocked by environment only (missing Android SDK; Xcode 26 beta broken plugin).

## Decision: Stitch HTML → Flutter Conversion Pipeline

User exported 21 Stitch screens as `code.html` (Tailwind CSS) + reference PNGs. Extracted canonical Tailwind config (40 color tokens, border-radius, typography) once into `core/app_colors.dart` + `core/app_theme.dart`, then mapped each screen 1:1: `p-5` → `EdgeInsets.all(20)`, `rounded-[20px]` → `BorderRadius.circular(20)`, hex colors verbatim. Single source of truth for bottom nav (`AppBottomNav` widget, teal `#5EE7DF` active state, `rounded-t-[32px]` backdrop blur) used everywhere despite Stitch variations across screens.

## Decision: Subagent Orchestration — Sequential Waves

10 screens + scaffold + BLE service exceeded single-agent context. Split into Wave 1 (scaffold + 5 auth/onboarding screens, 19 files) and Wave 2 (5 BLE screens + `BleService` + `DeviceRepository` + 9-state provisioning FSM, 10 files). Wave 2 inherited Wave 1 theme/widgets cleanly. **Total execution: ~18 minutes agent time.** Both waves used snake_case for file names (Dart convention), despite my kebab-case instruction — agents silently corrected language-specific guidance, which was right.

## Critical Fix: Runtime Bluetooth Permissions

Review flagged C1: `permission_handler` declared in pubspec but never requested at runtime. Android 12+ scan would silently return zero devices. Implemented proper `requestBluetoothScan()` + deny state handling with "Open settings" CTA banner per Material guidelines.

## Protocol Compliance Verified

BLE write order (SSID → Password → ServerHost → MqttScheme → MqttUser → MqttPassword), readDeviceId before writes, POST /devices/pair before GATT writes, 60s NOTIFY timeout, status strings — all match `docs/protocols/ble-provisioning-and-mqtt-auth.md` exactly. Reviewer validated contract compliance.

## Known Deviations (Non-Blocking)

- **Onboarding illustrations**: `Icon` placeholders (Stitch CDN URLs ephemeral; real PNGs committed later)
- **WiFi SSID dropdown**: Text input fallback (OS WiFi scan out of scope)
- **Real-device blockers documented**: Mid-provision nav leaks BluetoothDevice handle; scan side-effect in StreamProvider construction; GoRouter untyped `extra`; `_pollUntilOnline` swallows 401s. Flagged for Phase 07 refinement.

## Honest Assessment

Two-wave orchestration added coordination friction (19+10 file split required explicit shared-widget contracts), but kept each agent under context limits. Review surfaced 1 critical + 5 highs; critical blocked real testing. Fixed critical + 1 high (DioException URL leak). Remaining highs are real-device findings, not architecture failures.

Next: Phase 07 (Home realtime dashboard + History charts).
