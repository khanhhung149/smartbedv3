---
phase: 4
title: "Flutter: Repository & Routing Integration"
status: pending
priority: P1
effort: "2h"
dependencies: [3]
---

# Phase 4: Flutter Repository & Routing Integration

## Overview
Mở rộng `AuthRepository` + `AuthRepositoryImpl` với 4 method mới, thêm routes vào GoRouter, update `register` flow để navigate sang OTP screen, update `login` để handle 403 "email not verified", wire `ForgotPasswordScreen` vào login footer.

## Requirements
- Functional:
  - `AuthRepository` thêm: `verifyEmail`, `resendOtp`, `forgotPassword`, `resetPassword`
  - Register flow: sau submit thành công → navigate `/verify-email?email={email}` thay vì `/home`
  - Login flow: HTTP 403 → hiển thị lỗi "Please verify your email first" + link resend
  - Forgot password: login footer `onPressed` navigate `/forgot-password`
  - Router: thêm routes `/verify-email`, `/forgot-password`, `/reset-password`
- Non-functional:
  - Truyền email giữa screens qua GoRouter `extra` hoặc query params (không dùng global state)

## Related Code Files
- Modify: `flutter_app/lib/features/auth/auth_repository.dart`
- Modify: `flutter_app/lib/features/auth/auth_repository_impl.dart`
- Modify: `flutter_app/lib/features/auth/register_screen.dart`
- Modify: `flutter_app/lib/features/auth/login_screen.dart`
- Modify: `flutter_app/lib/app.dart`

## Implementation Steps

1. **`AuthRepository`** — thêm abstract methods:
   ```dart
   Future<String> verifyEmail(String email, String otp); // returns JWT
   Future<void> resendOtp(String email);
   Future<void> forgotPassword(String email);
   Future<void> resetPassword(String email, String otp, String password);
   ```

2. **`AuthRepositoryImpl`** — implement 4 methods:
   ```dart
   // POST /auth/verify-email → trả access_token
   Future<String> verifyEmail(String email, String otp) async {
     final res = await _client.dio.post('/auth/verify-email',
       data: {'email': email, 'otp': otp});
     final token = res.data['access_token'] as String;
     await _storage.writeToken(token);
     return token;
   }
   // POST /auth/resend-otp → 204
   // POST /auth/forgot-password → 204
   // POST /auth/reset-password → 204
   ```
   - Update `_mapDioError`: thêm case `400` → `'Invalid or expired code.'`
   - Thêm case `403` trong login error map → `'Please verify your email first.'`

3. **`RegisterScreen`** — update `_submit()`:
   ```dart
   // Trước: context.go('/home')
   // Sau:
   await ref.read(authRepositoryProvider).register(email, pass);
   if (!mounted) return;
   context.go('/verify-email', extra: email);
   ```

4. **`LoginScreen`** — update:
   - Forgot password `onPressed`: `context.go('/forgot-password')`
   - Error message: nếu `_errorMsg` contains "verify" → hiển thị thêm TextButton "Resend code" gọi `resendOtp`

5. **`app.dart`** — thêm 3 routes mới:
   ```dart
   GoRoute(
     path: '/verify-email',
     builder: (context, state) => VerifyEmailScreen(
       email: state.extra as String,
     ),
   ),
   GoRoute(
     path: '/forgot-password',
     builder: (_, __) => const ForgotPasswordScreen(),
   ),
   GoRoute(
     path: '/reset-password',
     builder: (context, state) => ResetPasswordScreen(
       email: state.extra as String,
     ),
   ),
   ```
   - Thêm `/verify-email`, `/forgot-password`, `/reset-password` vào `publicPaths`

## Success Criteria
- [ ] Register → navigate sang VerifyEmailScreen (không vào home)
- [ ] VerifyEmailScreen submit đúng OTP → vào `/home`
- [ ] Login với email chưa verified → hiển thị lỗi đúng
- [ ] Login footer "Forgot password?" navigate sang ForgotPasswordScreen
- [ ] ForgotPasswordScreen submit → navigate ResetPasswordScreen
- [ ] ResetPasswordScreen submit đúng → navigate `/login`
- [ ] Router publicPaths include 3 routes mới (không redirect về login)

## Risk Assessment
- **`state.extra` null safety** — nếu user deep-link trực tiếp vào `/verify-email` không có extra → cần handle redirect về `/login`
- **Existing test user** — user `test@test.com` đã tạo trước sẽ có `email_verified = FALSE`, cần update thủ công hoặc tạo user mới để test login
