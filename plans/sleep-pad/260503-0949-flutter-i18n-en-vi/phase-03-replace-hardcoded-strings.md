---
phase: 3
title: "Replace Hardcoded Strings"
status: pending
priority: P1
effort: "2h"
dependencies: [phase-02-arb-translation-files.md]
---

# Phase 3: Replace Hardcoded Strings

## Overview
Replace all hardcoded user-facing strings in 9 feature areas with `AppLocalizations.of(context)!.keyName` references.

## Related Code Files
- Modify: `flutter_app/lib/features/auth/login_screen.dart`
- Modify: `flutter_app/lib/features/auth/register_screen.dart`
- Modify: `flutter_app/lib/features/auth/verify_email_screen.dart`
- Modify: `flutter_app/lib/features/auth/forgot_password_screen.dart`
- Modify: `flutter_app/lib/features/auth/reset_password_screen.dart`
- Modify: `flutter_app/lib/features/devices/` (all screen files)
- Modify: `flutter_app/lib/features/settings/settings_screen.dart`
- Modify: `flutter_app/lib/features/sharing/` (all screen files)
- Modify: `flutter_app/lib/features/alerts/` (all screen files)
- Modify: `flutter_app/lib/features/history/` (all screen files)
- Modify: `flutter_app/lib/features/home/` (all screen files)
- Modify: `flutter_app/lib/features/onboarding/` (all screen files)

## Implementation Steps

### Step 0: Add import pattern to each modified file

```dart
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
```

Access via: `AppLocalizations.of(context)!` (or `l10n` local alias for brevity):
```dart
final l10n = AppLocalizations.of(context)!;
```

### Step 1: Auth screens

#### `login_screen.dart`
| Old string | New key |
|-----------|---------|
| `'Welcome back'` | `l10n.welcomeBack` |
| `'Email address'` (placeholder) | `l10n.emailAddress` |
| `'Password'` (placeholder) | `l10n.password` |
| `'Enter a valid email address.'` | `l10n.enterValidEmail` |
| `'Password must be at least 8 characters.'` | `l10n.passwordTooShort` |
| `'Sign in'` (button label) | `l10n.signIn` |
| `'New here? Sign up'` | `l10n.newHereSignUp` |
| `'Forgot password?'` | `l10n.forgotPassword` |

#### `register_screen.dart`
| Old string | New key |
|-----------|---------|
| `'Create your account'` | `l10n.createYourAccount` |
| `'Email address'` | `l10n.emailAddress` |
| `'Password'` | `l10n.password` |
| `'Confirm password'` | `l10n.confirmPassword` |
| `'Create account'` (button) | `l10n.createAccount` |
| `'Already have an account? '` | `l10n.alreadyHaveAccount` |
| `'Log in'` | `l10n.logIn` |
| `'Enter a valid email address.'` | `l10n.enterValidEmail` |
| `'Password must be at least 8 characters.'` | `l10n.passwordTooShort` |
| `'Passwords do not match.'` | `l10n.passwordsDoNotMatch` |

#### `verify_email_screen.dart`
| Old string | New key |
|-----------|---------|
| `'Check your email'` | `l10n.checkYourEmail` |
| `'We sent a 6-digit code to\n${widget.email}'` | `l10n.verifyEmailSubtitle(widget.email)` |
| `'Enter the 6-digit code.'` | `l10n.enterSixDigitCode` |
| `'Verify'` (button) | `l10n.verify` |
| `'Resend in ${_remaining}s'` | `l10n.resendIn(_remaining)` |
| `'Resend code'` | `l10n.resendCode` |

#### `forgot_password_screen.dart`
| Old string | New key |
|-----------|---------|
| `'Forgot password'` (title) | `l10n.forgotPasswordTitle` |
| `"Enter your email and we'll send a reset code"` | `l10n.forgotPasswordSubtitle` |
| `'Email address'` | `l10n.emailAddress` |
| `'Send reset code'` (button) | `l10n.sendResetCode` |
| `'Back to sign in'` | `l10n.backToSignIn` |

#### `reset_password_screen.dart`
| Old string | New key |
|-----------|---------|
| `'Reset password'` (title) | `l10n.resetPassword` |
| `'Enter the code sent to ${widget.email}'` | `l10n.resetPasswordSubtitle(widget.email)` |
| `'New password'` | `l10n.newPassword` |
| `'Confirm password'` | `l10n.confirmPassword` |
| `'Enter the 6-digit code.'` | `l10n.enterSixDigitCode` |
| `'Password must be at least 8 characters.'` | `l10n.passwordTooShort` |
| `'Passwords do not match.'` | `l10n.passwordsDoNotMatch` |
| `'Reset password'` (button) | `l10n.resetPassword` |

### Step 2: Settings screen

| Old string | New key |
|-----------|---------|
| `'Settings'` | `l10n.settings` |
| `'Account'` (section) | `l10n.account` |
| `'Change password'` | `l10n.changePassword` |
| `'Notifications'` (section) | `l10n.notifications` |
| `'Enable push notifications'` | `l10n.enablePushNotifications` |
| `'Quiet hours'` | `l10n.quietHours` |
| `'10pm — 7am'` | `l10n.quietHoursValue` |
| `'Appearance'` (section) | `l10n.appearance` |
| `'Device Connection'` (section) | `l10n.deviceConnection` |
| `'Server URL'` | `l10n.serverUrl` |
| `'Advanced'` | `l10n.advanced` |
| `'Saved WiFi credentials'` | `l10n.savedWifiCredentials` |
| `'About'` (section) | `l10n.about` |
| `'App version'` | `l10n.appVersion` |
| `'Terms of Service'` | `l10n.termsOfService` |
| `'Privacy Policy'` | `l10n.privacyPolicy` |
| `'Support Email'` | `l10n.supportEmail` |
| `'Log out'` | `l10n.logOut` |
| `'Cancel'` | `l10n.cancel` |
| `'Save'` | `l10n.save` |
| `'Save changes'` | `l10n.saveChanges` |
| `'Invalid URL format'` | `l10n.invalidUrlFormat` |

### Step 3: Devices screens

| Old string | New key |
|-----------|---------|
| `'Devices'` | `l10n.devices` |
| `'No devices paired yet.'` | `l10n.noDevicesPaired` |
| `'Add device'` | `l10n.addDevice` |
| `'Device Details'` | `l10n.deviceDetails` |
| `'Device name'` (hint) | `l10n.deviceName` |
| `'Device ID copied'` | `l10n.deviceIdCopied` |
| `'Failed to load device: $e'` | `l10n.failedToLoadDevice(e.toString())` |
| `'Paired ${_formatPairedDate(device.pairedAt)}'` | `l10n.pairedOn(_formatPairedDate(device.pairedAt))` |
| `'Active ${_relativeTime(device.lastSeen!)}'` | `l10n.activeAgo(_relativeTime(device.lastSeen!))` |
| `'Online'` | `l10n.online` |
| `'Offline'` | `l10n.offline` |
| `'No device selected.'` | `l10n.noDeviceSelected` |
| `deviceName ?? 'No device'` | `deviceName ?? l10n.noDevice` |

### Step 4: Sharing screens

| Old string | New key |
|-----------|---------|
| `'Share peace of mind'` | `l10n.sharing` |
| `'Invite family members by email...'` | `l10n.sharingSubtitle` |
| `'Send invite'` | `l10n.sendInvite` |
| `'Email address'` | `l10n.emailAddress` |
| `'PENDING INVITES'` | `l10n.pendingInvites` |
| `'No devices shared with you.'` | `l10n.noDevicesShared` |
| `'Invite from ${inv.ownerEmail}'` | `l10n.inviteFrom(inv.ownerEmail)` |
| `'Accept'` | `l10n.accept` |
| `'Decline'` | `l10n.decline` |

### Step 5: Alerts screens

| Old string | New key |
|-----------|---------|
| `'Alerts'` | `l10n.alerts` |
| `'Alert Detail'` | `l10n.alertDetail` |
| `"Know if something's off"` | `l10n.knowIfSomethingOff` |
| `'Set personalized thresholds...'` | `l10n.alertsSubtitle` |
| `'Active notifications enabled'` | `l10n.activeNotificationsEnabled` |

### Step 6: History screens

| Old string | New key |
|-----------|---------|
| `'Sleep History'` | `l10n.sleepHistory` |
| `'Could not load history'` | `l10n.couldNotLoadHistory` |
| `'Not enough data yet'` | `l10n.notEnoughData` |
| `'Sleep data will appear here...'` | `l10n.sleepDataWillAppear` |

### Step 7: Onboarding screens

| Old string | New key |
|-----------|---------|
| `'Monitor sleep,\nwithout wearables'` | `l10n.monitorSleepTagline` |
| `'Sleep Pad is ready'` | `l10n.sleepPadReady` |
| `'Setup Sleep Pad'` | `l10n.setupSleepPad` |
| `'Give your Sleep Pad WiFi'` | `l10n.giveWifi` |
| `'Your Sleep Pad will use this network...'` | `l10n.wifiDescription` |
| `'Network Name (SSID)'` | `l10n.networkName` |
| `'Password'` | `l10n.password` |
| `'Save and go home'` | `l10n.saveAndGoHome` |
| `'Continue'` (button) | `l10n.continue_` |
| `'Pairing with your device...'` | `l10n.pairingWithDevice` |
| `'This usually takes 10–30 seconds'` | `l10n.pairingDuration` |

## Success Criteria
- [ ] `flutter analyze` shows zero errors
- [ ] `flutter build ios --debug` compiles without errors
- [ ] Hot reload on iOS Simulator shows EN strings by default
- [ ] No hardcoded EN strings remain in any modified screen file (verify with `grep -r "'[A-Z]" lib/features/`)

## Notes
- Do NOT translate `'Sleep Pad'` brand name — leave as literal string
- `AppLocalizations.of(context)` returns nullable — use `!` operator (safe: delegates are always registered via `app.dart`)
- For `Text` widgets in `const` contexts: remove `const` keyword when switching to `l10n.*` (dynamic values)
