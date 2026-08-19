---
phase: 2
title: "ARB Translation Files"
status: pending
priority: P1
effort: "1h"
dependencies: [phase-01-setup-i18n-infrastructure.md]
---

# Phase 2: ARB Translation Files

## Overview
Write all ~55 user-facing strings into `app_en.arb` (English) and `app_vi.arb` (Vietnamese), then regenerate `AppLocalizations`.

## Related Code Files
- Modify: `flutter_app/lib/l10n/app_en.arb`
- Modify: `flutter_app/lib/l10n/app_vi.arb`

## Full ARB Content

### `lib/l10n/app_en.arb`

```json
{
  "@@locale": "en",

  "appName": "Sleep Pad",

  "signIn": "Sign in",
  "signUp": "Sign up",
  "logIn": "Log in",
  "logOut": "Log out",
  "createAccount": "Create account",
  "getStarted": "Get started",
  "continue_": "Continue",
  "save": "Save",
  "saveChanges": "Save changes",
  "cancel": "Cancel",
  "retry": "Retry",
  "accept": "Accept",
  "decline": "Decline",
  "send": "Send",

  "welcomeBack": "Welcome back",
  "createYourAccount": "Create your account",
  "newHereSignUp": "New here? Sign up",
  "alreadyHaveAccount": "Already have an account? ",
  "forgotPassword": "Forgot password?",
  "forgotPasswordTitle": "Forgot password",
  "forgotPasswordSubtitle": "Enter your email and we'll send a reset code",
  "sendResetCode": "Send reset code",
  "backToSignIn": "Back to sign in",

  "emailAddress": "Email address",
  "password": "Password",
  "newPassword": "New password",
  "confirmPassword": "Confirm password",

  "checkYourEmail": "Check your email",
  "verifyEmailSubtitle": "We sent a 6-digit code to\n{email}",
  "@verifyEmailSubtitle": {
    "placeholders": { "email": { "type": "String" } }
  },
  "verify": "Verify",
  "resendCode": "Resend code",
  "resendIn": "Resend in {seconds}s",
  "@resendIn": {
    "placeholders": { "seconds": { "type": "int" } }
  },

  "resetPassword": "Reset password",
  "resetPasswordSubtitle": "Enter the code sent to {email}",
  "@resetPasswordSubtitle": {
    "placeholders": { "email": { "type": "String" } }
  },

  "enterValidEmail": "Enter a valid email address.",
  "passwordTooShort": "Password must be at least 8 characters.",
  "passwordsDoNotMatch": "Passwords do not match.",
  "enterSixDigitCode": "Enter the 6-digit code.",

  "settings": "Settings",
  "account": "Account",
  "notifications": "Notifications",
  "appearance": "Appearance",
  "deviceConnection": "Device Connection",
  "about": "About",
  "changePassword": "Change password",
  "enablePushNotifications": "Enable push notifications",
  "quietHours": "Quiet hours",
  "quietHoursValue": "10pm — 7am",
  "appVersion": "App version",
  "termsOfService": "Terms of Service",
  "privacyPolicy": "Privacy Policy",
  "supportEmail": "Support Email",
  "serverUrl": "Server URL",
  "advanced": "Advanced",
  "savedWifiCredentials": "Saved WiFi credentials",
  "invalidUrlFormat": "Invalid URL format",
  "language": "Language",

  "devices": "Devices",
  "deviceDetails": "Device Details",
  "noDevicesPaired": "No devices paired yet.",
  "addDevice": "Add device",
  "noDeviceSelected": "No device selected.",
  "deviceIdCopied": "Device ID copied",
  "failedToLoadDevice": "Failed to load device: {error}",
  "@failedToLoadDevice": {
    "placeholders": { "error": { "type": "String" } }
  },
  "pairedOn": "Paired {date}",
  "@pairedOn": {
    "placeholders": { "date": { "type": "String" } }
  },
  "activeAgo": "Active {time}",
  "@activeAgo": {
    "placeholders": { "time": { "type": "String" } }
  },
  "online": "Online",
  "offline": "Offline",
  "deviceName": "Device name",

  "setupSleepPad": "Setup Sleep Pad",
  "sleepPadReady": "Sleep Pad is ready",
  "monitorSleepTagline": "Monitor sleep,\nwithout wearables",
  "giveWifi": "Give your Sleep Pad WiFi",
  "wifiDescription": "Your Sleep Pad will use this network to send data to the cloud.",
  "networkName": "Network Name (SSID)",
  "saveAndGoHome": "Save and go home",
  "pairingWithDevice": "Pairing with your device...",
  "pairingDuration": "This usually takes 10–30 seconds",

  "sharing": "Share peace of mind",
  "sharingSubtitle": "Invite family members by email. They see the same sleep data in real time.",
  "sendInvite": "Send invite",
  "pendingInvites": "PENDING INVITES",
  "noDevicesShared": "No devices shared with you.",
  "inviteFrom": "Invite from {email}",
  "@inviteFrom": {
    "placeholders": { "email": { "type": "String" } }
  },

  "alerts": "Alerts",
  "alertDetail": "Alert Detail",
  "knowIfSomethingOff": "Know if something's off",
  "alertsSubtitle": "Set personalized thresholds. Get a notification the moment something changes.",
  "activeNotificationsEnabled": "Active notifications enabled",

  "sleepHistory": "Sleep History",
  "couldNotLoadHistory": "Could not load history",
  "notEnoughData": "Not enough data yet",
  "sleepDataWillAppear": "Sleep data will appear here once your device has been monitoring.",

  "noDevice": "No device"
}
```

### `lib/l10n/app_vi.arb`

```json
{
  "@@locale": "vi",

  "appName": "Sleep Pad",

  "signIn": "Đăng nhập",
  "signUp": "Đăng ký",
  "logIn": "Đăng nhập",
  "logOut": "Đăng xuất",
  "createAccount": "Tạo tài khoản",
  "getStarted": "Bắt đầu",
  "continue_": "Tiếp tục",
  "save": "Lưu",
  "saveChanges": "Lưu thay đổi",
  "cancel": "Hủy",
  "retry": "Thử lại",
  "accept": "Chấp nhận",
  "decline": "Từ chối",
  "send": "Gửi",

  "welcomeBack": "Chào mừng trở lại",
  "createYourAccount": "Tạo tài khoản của bạn",
  "newHereSignUp": "Chưa có tài khoản? Đăng ký",
  "alreadyHaveAccount": "Đã có tài khoản? ",
  "forgotPassword": "Quên mật khẩu?",
  "forgotPasswordTitle": "Quên mật khẩu",
  "forgotPasswordSubtitle": "Nhập email và chúng tôi sẽ gửi mã đặt lại",
  "sendResetCode": "Gửi mã đặt lại",
  "backToSignIn": "Quay lại đăng nhập",

  "emailAddress": "Địa chỉ email",
  "password": "Mật khẩu",
  "newPassword": "Mật khẩu mới",
  "confirmPassword": "Xác nhận mật khẩu",

  "checkYourEmail": "Kiểm tra email của bạn",
  "verifyEmailSubtitle": "Chúng tôi đã gửi mã 6 chữ số đến\n{email}",
  "@verifyEmailSubtitle": {
    "placeholders": { "email": { "type": "String" } }
  },
  "verify": "Xác minh",
  "resendCode": "Gửi lại mã",
  "resendIn": "Gửi lại sau {seconds}s",
  "@resendIn": {
    "placeholders": { "seconds": { "type": "int" } }
  },

  "resetPassword": "Đặt lại mật khẩu",
  "resetPasswordSubtitle": "Nhập mã đã gửi đến {email}",
  "@resetPasswordSubtitle": {
    "placeholders": { "email": { "type": "String" } }
  },

  "enterValidEmail": "Nhập địa chỉ email hợp lệ.",
  "passwordTooShort": "Mật khẩu phải có ít nhất 8 ký tự.",
  "passwordsDoNotMatch": "Mật khẩu không khớp.",
  "enterSixDigitCode": "Nhập mã 6 chữ số.",

  "settings": "Cài đặt",
  "account": "Tài khoản",
  "notifications": "Thông báo",
  "appearance": "Giao diện",
  "deviceConnection": "Kết nối thiết bị",
  "about": "Về ứng dụng",
  "changePassword": "Đổi mật khẩu",
  "enablePushNotifications": "Bật thông báo đẩy",
  "quietHours": "Giờ yên tĩnh",
  "quietHoursValue": "10pm — 7am",
  "appVersion": "Phiên bản ứng dụng",
  "termsOfService": "Điều khoản dịch vụ",
  "privacyPolicy": "Chính sách bảo mật",
  "supportEmail": "Email hỗ trợ",
  "serverUrl": "URL máy chủ",
  "advanced": "Nâng cao",
  "savedWifiCredentials": "Thông tin WiFi đã lưu",
  "invalidUrlFormat": "Định dạng URL không hợp lệ",
  "language": "Ngôn ngữ",

  "devices": "Thiết bị",
  "deviceDetails": "Chi tiết thiết bị",
  "noDevicesPaired": "Chưa có thiết bị nào được ghép.",
  "addDevice": "Thêm thiết bị",
  "noDeviceSelected": "Chưa chọn thiết bị.",
  "deviceIdCopied": "Đã sao chép ID thiết bị",
  "failedToLoadDevice": "Không thể tải thiết bị: {error}",
  "@failedToLoadDevice": {
    "placeholders": { "error": { "type": "String" } }
  },
  "pairedOn": "Đã ghép {date}",
  "@pairedOn": {
    "placeholders": { "date": { "type": "String" } }
  },
  "activeAgo": "Hoạt động {time}",
  "@activeAgo": {
    "placeholders": { "time": { "type": "String" } }
  },
  "online": "Trực tuyến",
  "offline": "Ngoại tuyến",
  "deviceName": "Tên thiết bị",

  "setupSleepPad": "Cài đặt Sleep Pad",
  "sleepPadReady": "Sleep Pad đã sẵn sàng",
  "monitorSleepTagline": "Theo dõi giấc ngủ,\nkhông cần đeo thiết bị",
  "giveWifi": "Kết nối WiFi cho Sleep Pad",
  "wifiDescription": "Sleep Pad sẽ dùng mạng này để gửi dữ liệu lên đám mây.",
  "networkName": "Tên mạng (SSID)",
  "saveAndGoHome": "Lưu và về trang chủ",
  "pairingWithDevice": "Đang ghép đôi thiết bị...",
  "pairingDuration": "Thường mất 10–30 giây",

  "sharing": "Chia sẻ sự an tâm",
  "sharingSubtitle": "Mời thành viên gia đình qua email. Họ xem cùng dữ liệu giấc ngủ theo thời gian thực.",
  "sendInvite": "Gửi lời mời",
  "pendingInvites": "LỜI MỜI CHỜ XỬ LÝ",
  "noDevicesShared": "Chưa có thiết bị nào được chia sẻ với bạn.",
  "inviteFrom": "Lời mời từ {email}",
  "@inviteFrom": {
    "placeholders": { "email": { "type": "String" } }
  },

  "alerts": "Cảnh báo",
  "alertDetail": "Chi tiết cảnh báo",
  "knowIfSomethingOff": "Biết ngay khi có bất thường",
  "alertsSubtitle": "Đặt ngưỡng cá nhân. Nhận thông báo ngay khi có thay đổi.",
  "activeNotificationsEnabled": "Thông báo đang bật",

  "sleepHistory": "Lịch sử giấc ngủ",
  "couldNotLoadHistory": "Không thể tải lịch sử",
  "notEnoughData": "Chưa đủ dữ liệu",
  "sleepDataWillAppear": "Dữ liệu giấc ngủ sẽ xuất hiện sau khi thiết bị theo dõi.",

  "noDevice": "Không có thiết bị"
}
```

## Implementation Steps

1. Replace stub content in `lib/l10n/app_en.arb` with full EN content above
2. Replace stub content in `lib/l10n/app_vi.arb` with full VI content above
3. Run `flutter gen-l10n` to regenerate `AppLocalizations`
4. Verify all keys resolve without compile errors: `flutter build apk --debug` or `flutter analyze`

## Success Criteria
- [ ] `flutter gen-l10n` produces no errors or warnings
- [ ] All ARB keys match between `app_en.arb` and `app_vi.arb`
- [ ] Parameterized strings (`{email}`, `{seconds}`, etc.) have matching `@` entries in both files

## Notes
- `continue_` uses trailing underscore to avoid Dart keyword conflict
- `appName` ("Sleep Pad") intentionally untranslated — brand name stays in EN for both locales
- `quietHoursValue` ("10pm — 7am") left same in VI — no locale-specific time format needed
