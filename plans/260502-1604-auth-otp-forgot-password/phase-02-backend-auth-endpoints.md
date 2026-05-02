---
phase: 2
title: "Backend: Auth Endpoints"
status: pending
priority: P1
effort: "2h"
dependencies: [1]
---

# Phase 2: Backend Auth Endpoints

## Overview
Thêm 4 endpoints mới vào `auth/router.py` và update `register` để tự động gửi OTP sau khi tạo tài khoản. Update `login` để block user chưa verify.

## Requirements
- Functional:
  - `POST /auth/verify-email` — verify OTP sau register
  - `POST /auth/resend-otp` — gửi lại OTP verify
  - `POST /auth/forgot-password` — gửi OTP reset password
  - `POST /auth/reset-password` — verify OTP + đặt mật khẩu mới
  - `POST /auth/register` — tự động gửi OTP verify sau khi tạo user
  - `POST /auth/login` — trả 403 nếu email chưa verified
- Non-functional:
  - Không expose thông tin user tồn tại hay không qua forgot-password response
  - Inject Redis từ `request.app.state` (pattern đã dùng trong app)

## Architecture

```
Endpoints mới:
  POST /auth/verify-email      { email, otp }         → { access_token }
  POST /auth/resend-otp        { email }               → 204
  POST /auth/forgot-password   { email }               → 204 (luôn 204, không leak)
  POST /auth/reset-password    { email, otp, password } → 204

Register update:
  - Sau INSERT user thành công → gọi send_otp_email(email, otp, "verify")
  - Không trả JWT nữa (user phải verify trước)

Login update:
  - Check email_verified = TRUE, nếu False → HTTP 403 "email not verified"
```

## Related Code Files
- Modify: `backend/app/auth/router.py`
- Modify: `backend/app/auth/models.py` — thêm request/response schemas mới
- Modify: `backend/app/main.py` — kiểm tra Redis inject pattern

## Implementation Steps

1. **Thêm Pydantic schemas** vào `auth/models.py`:
   ```python
   class OtpVerifyRequest(BaseModel):
       email: EmailStr
       otp: str = Field(min_length=6, max_length=6, pattern=r'^\d{6}$')

   class ResendOtpRequest(BaseModel):
       email: EmailStr

   class ForgotPasswordRequest(BaseModel):
       email: EmailStr

   class ResetPasswordRequest(BaseModel):
       email: EmailStr
       otp: str = Field(min_length=6, max_length=6, pattern=r'^\d{6}$')
       password: str = Field(min_length=8, max_length=128)
   ```

2. **Update `register`** — sau khi tạo user, gửi OTP (fire & forget, không fail register nếu email lỗi):
   ```python
   otp = await generate_and_store(request.app.state.redis, "verify", payload.email)
   asyncio.create_task(send_otp_email(payload.email, otp, "verify"))
   # Trả UserOut (không trả token — phải verify trước)
   ```

3. **Update `login`** — thêm check verified:
   ```python
   if not row["email_verified"]:
       raise HTTPException(status.HTTP_403_FORBIDDEN, "email not verified")
   ```

4. **`POST /auth/verify-email`**:
   ```python
   ok = await verify(redis, "verify", payload.email, payload.otp)
   if not ok:
       raise HTTPException(400, "invalid or expired OTP")
   await pool.execute("UPDATE users SET email_verified=TRUE WHERE email=$1", payload.email)
   row = await pool.fetchrow("SELECT id FROM users WHERE email=$1", payload.email)
   return Token(access_token=create_access_token(row["id"]))
   ```

5. **`POST /auth/resend-otp`**:
   ```python
   row = await pool.fetchrow("SELECT email_verified FROM users WHERE email=$1", payload.email)
   if row and not row["email_verified"]:
       otp = await generate_and_store(redis, "verify", payload.email)
       asyncio.create_task(send_otp_email(payload.email, otp, "verify"))
   # Luôn 204 dù email không tồn tại (tránh enumeration)
   ```

6. **`POST /auth/forgot-password`**:
   ```python
   row = await pool.fetchrow("SELECT id FROM users WHERE email=$1", payload.email)
   if row:
       otp = await generate_and_store(redis, "reset", payload.email)
       asyncio.create_task(send_otp_email(payload.email, otp, "reset"))
   # Luôn 204
   ```

7. **`POST /auth/reset-password`**:
   ```python
   ok = await verify(redis, "reset", payload.email, payload.otp)
   if not ok:
       raise HTTPException(400, "invalid or expired OTP")
   pwd_hash = hash_password(payload.password)
   await pool.execute("UPDATE users SET password_hash=$1 WHERE email=$2", pwd_hash, payload.email)
   ```

## Success Criteria
- [ ] `POST /auth/register` gửi OTP email, không trả token
- [ ] `POST /auth/login` trả 403 nếu chưa verified
- [ ] `POST /auth/verify-email` với OTP đúng trả JWT
- [ ] `POST /auth/verify-email` với OTP sai trả 400
- [ ] `POST /auth/forgot-password` luôn trả 204
- [ ] `POST /auth/reset-password` đổi password thành công

## Risk Assessment
- **asyncio.create_task trong FastAPI** — cần đảm bảo event loop còn sống khi task chạy; dùng `BackgroundTasks` của FastAPI thay thế nếu gặp vấn đề
- **Redis chưa inject vào request.app.state** — kiểm tra `main.py` xem Redis được khởi tạo như thế nào
