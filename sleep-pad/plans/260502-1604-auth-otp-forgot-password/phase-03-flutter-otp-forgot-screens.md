---
phase: 3
title: "Flutter: OTP & Forgot Password Screens"
status: pending
priority: P1
effort: "3h"
dependencies: []
---

# Phase 3: Flutter OTP & Forgot Password Screens

## Overview
Tạo 3 màn hình mới theo đúng design system hiện tại (AppColors, StitchTextField, PrimaryButton, GoogleFonts.inter): OTP verify screen, forgot password screen, reset password screen.

## Requirements
- Functional:
  - `VerifyEmailScreen` — nhập 6 ô OTP, auto-submit khi đủ 6 số, resend countdown 60s
  - `ForgotPasswordScreen` — nhập email, submit gửi OTP
  - `ResetPasswordScreen` — nhập OTP 6 số + mật khẩu mới + confirm
- Non-functional:
  - Nhất quán với design hiện tại (dark theme, AppColors, font Inter)
  - OTP input: 6 ô riêng biệt, focus tự chuyển, hỗ trợ paste
  - Keyboard số cho OTP fields

## Architecture

```
lib/features/auth/
  verify_email_screen.dart     ← OTP 6 ô sau register
  forgot_password_screen.dart  ← nhập email
  reset_password_screen.dart   ← OTP + mật khẩu mới
  widgets/
    otp_input_field.dart       ← 6-cell OTP widget dùng chung
```

## Related Code Files
- Create: `flutter_app/lib/features/auth/verify_email_screen.dart`
- Create: `flutter_app/lib/features/auth/forgot_password_screen.dart`
- Create: `flutter_app/lib/features/auth/reset_password_screen.dart`
- Create: `flutter_app/lib/features/auth/widgets/otp_input_field.dart`

## Implementation Steps

1. **`OtpInputField` widget** (`widgets/otp_input_field.dart`):
   - 6 `TextFormField` trong `Row`, width cố định ~44px mỗi ô
   - `onChanged`: khi nhập 1 ký tự → `FocusScope.of(context).nextFocus()`
   - `onChanged`: khi xóa → `FocusScope.of(context).previousFocus()`
   - `keyboardType: TextInputType.number`
   - Paste handling: override `onChanged` để split 6 ký tự vào từng controller
   - `onCompleted(String otp)` callback khi đủ 6 số
   - Styling: border `AppColors.outline`, filled `AppColors.surface`

2. **`VerifyEmailScreen`** (`verify_email_screen.dart`):
   - Nhận `email` qua constructor (passed khi navigate)
   - Hiển thị: "Check your email", subtitle "We sent a code to {email}"
   - `OtpInputField` → auto-submit khi `onCompleted`
   - Resend button với countdown 60s (dùng `Timer.periodic`)
   - `_submit()`: gọi `authRepository.verifyEmail(email, otp)` → nếu OK → `context.go('/home')`
   - Error inline bên dưới OTP input

3. **`ForgotPasswordScreen`** (`forgot_password_screen.dart`):
   - `StitchTextField` nhập email
   - `PrimaryButton` "Send reset code"
   - `_submit()`: gọi `authRepository.forgotPassword(email)` → navigate `/reset-password?email={email}`
   - Luôn navigate sau submit (backend luôn 204, không leak)

4. **`ResetPasswordScreen`** (`reset_password_screen.dart`):
   - Nhận `email` qua query param
   - `OtpInputField` cho mã OTP
   - `StitchTextField` mật khẩu mới + confirm (có eye toggle)
   - Validate: password >= 8 ký tự, 2 field khớp nhau
   - `_submit()`: gọi `authRepository.resetPassword(email, otp, password)` → navigate `/login`

## Success Criteria
- [ ] OTP input tự chuyển focus khi nhập, backspace quay lại ô trước
- [ ] Paste OTP 6 số tự điền vào 6 ô
- [ ] Resend countdown hiển thị đúng, disable button trong 60s
- [ ] VerifyEmailScreen auto-submit khi nhập đủ 6 số
- [ ] ResetPasswordScreen validate 2 password field khớp nhau
- [ ] Tất cả màn hình nhất quán design với LoginScreen

## Risk Assessment
- **OTP paste** — cần test kỹ trên iOS Simulator vì iOS clipboard behavior khác Android
- **6 TextFormField focus management** — có thể dùng `FocusNode` list thay vì nextFocus() để kiểm soát tốt hơn
