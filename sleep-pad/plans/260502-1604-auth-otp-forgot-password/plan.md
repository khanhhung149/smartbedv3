---
title: "Auth: OTP Email Verification & Forgot Password"
status: pending
created: 2026-05-02
---

# Auth: OTP Email Verification & Forgot Password

## Overview

Thêm 2 flow vào hệ thống auth hiện tại:
1. **Email OTP Verification** — sau khi register, user nhận OTP 6 số qua email để verify tài khoản
2. **Forgot Password** — user nhập email → nhận OTP → đặt lại mật khẩu

## Hướng làm OTP

**Stack được dùng:**
- **Redis** (đã có) — lưu OTP với TTL 10 phút, key pattern: `otp:{purpose}:{email}`
- **Resend** (email provider mới) — API đơn giản, free tier 3000 emails/month, không cần SMTP setup

**Luồng OTP:**
```
Register/ForgotPwd
    → generate 6-digit OTP
    → store Redis: SET otp:verify:{email} {otp} EX 600
    → send email via Resend API
    → Flutter hiển thị OTP input screen
    → user nhập OTP
    → backend verify: GET otp:verify:{email} → compare → DEL key
    → nếu đúng: mark verified / issue JWT
```

**Security:**
- Rate limit: max 3 lần request OTP / 15 phút / email (key: `otp_rl:{email}`)
- Max 5 lần verify sai → invalidate OTP (key: `otp_attempts:{email}`)
- OTP TTL: 10 phút
- Constant-time compare để tránh timing attack

## Phases

| # | Phase | Status | Effort |
|---|-------|--------|--------|
| 1 | [Backend: OTP & Email Service](phase-01-backend-otp-email-service.md) | pending | 3h |
| 2 | [Backend: Auth Endpoints](phase-02-backend-auth-endpoints.md) | pending | 2h |
| 3 | [Flutter: OTP & Forgot Screens](phase-03-flutter-otp-forgot-screens.md) | pending | 3h |
| 4 | [Flutter: Repository & Routing](phase-04-flutter-repository-routing.md) | pending | 2h |

## Key Dependencies

- Phase 2 blocks on Phase 1
- Phase 4 blocks on Phase 3
- Cần `RESEND_API_KEY` từ resend.com trước khi implement Phase 1
