---
phase: 1
title: "Backend: OTP & Email Service"
status: pending
priority: P1
effort: "3h"
dependencies: []
---

# Phase 1: Backend OTP & Email Service

## Overview
Xây dựng 2 service mới: `otp_service.py` (generate/store/verify OTP qua Redis) và `email_service.py` (gửi email qua Resend API). Thêm DB migration cho `email_verified` column. Cấu hình env vars.

## Requirements
- Functional:
  - Generate OTP 6 số ngẫu nhiên
  - Lưu OTP vào Redis với TTL 10 phút
  - Rate limit: max 3 request OTP / 15 phút / email
  - Max 5 lần verify sai → invalidate OTP
  - Gửi email HTML đẹp qua Resend API
  - DB: thêm `email_verified BOOLEAN DEFAULT FALSE` vào bảng `users`
- Non-functional:
  - Constant-time OTP compare (tránh timing attack)
  - Không log OTP value

## Architecture

```
Redis keys:
  otp:{purpose}:{email}        → 6-digit code, TTL 600s
  otp_attempts:{purpose}:{email} → int count, TTL 600s
  otp_rl:{email}               → int count, TTL 900s (rate limit)

Email flow:
  email_service.send_otp_email(email, otp, purpose)
    → POST https://api.resend.com/emails
    → Authorization: Bearer {RESEND_API_KEY}
```

## Related Code Files
- Create: `backend/app/auth/otp_service.py`
- Create: `backend/app/auth/email_service.py`
- Modify: `backend/app/config.py` — thêm `resend_api_key`, `email_from`
- Modify: `backend/postgres/init.sql` — thêm `email_verified` column
- Modify: `backend/app/requirements.txt` — thêm `httpx`
- Modify: `backend/.env.dev` — thêm `RESEND_API_KEY`, `EMAIL_FROM`

## Implementation Steps

1. **DB migration** — thêm vào `postgres/init.sql`:
   ```sql
   ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;
   ```
   Vì init.sql chỉ chạy lần đầu, cần migrate thủ công:
   ```bash
   docker exec sleeppad-postgres psql -U sleeppad -d sleeppad \
     -c "ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;"
   ```

2. **Config** — thêm vào `config.py`:
   ```python
   resend_api_key: str = ""
   email_from: str = "SleepPad <noreply@yourdomain.com>"
   ```

3. **OTP Service** — tạo `auth/otp_service.py`:
   ```python
   import secrets, hmac
   from redis.asyncio import Redis

   OTP_TTL = 600        # 10 min
   RL_TTL = 900         # 15 min rate-limit window
   MAX_ATTEMPTS = 5
   MAX_REQUESTS = 3

   async def generate_and_store(redis: Redis, purpose: str, email: str) -> str:
       rl_key = f"otp_rl:{email}"
       count = await redis.incr(rl_key)
       if count == 1:
           await redis.expire(rl_key, RL_TTL)
       if count > MAX_REQUESTS:
           raise RateLimitError()
       otp = str(secrets.randbelow(900000) + 100000)  # 100000–999999
       await redis.set(f"otp:{purpose}:{email}", otp, ex=OTP_TTL)
       await redis.delete(f"otp_attempts:{purpose}:{email}")
       return otp

   async def verify(redis: Redis, purpose: str, email: str, code: str) -> bool:
       stored = await redis.get(f"otp:{purpose}:{email}")
       if not stored:
           return False
       attempts_key = f"otp_attempts:{purpose}:{email}"
       attempts = await redis.incr(attempts_key)
       if attempts == 1:
           await redis.expire(attempts_key, OTP_TTL)
       if attempts > MAX_ATTEMPTS:
           await redis.delete(f"otp:{purpose}:{email}")
           return False
       if not hmac.compare_digest(stored, code.encode()):
           return False
       await redis.delete(f"otp:{purpose}:{email}", attempts_key)
       return True
   ```

4. **Email Service** — tạo `auth/email_service.py` dùng `httpx.AsyncClient`:
   ```python
   import httpx
   from config import get_settings

   async def send_otp_email(to_email: str, otp: str, purpose: str) -> None:
       settings = get_settings()
       subject = "Verify your email" if purpose == "verify" else "Reset your password"
       html = _build_html(otp, purpose)
       async with httpx.AsyncClient() as client:
           resp = await client.post(
               "https://api.resend.com/emails",
               headers={"Authorization": f"Bearer {settings.resend_api_key}"},
               json={"from": settings.email_from, "to": [to_email],
                     "subject": subject, "html": html},
               timeout=10,
           )
           resp.raise_for_status()
   ```

5. **requirements.txt** — thêm `httpx==0.28.1`

6. **Rebuild Docker image** sau khi thêm httpx:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev up -d --build fastapi
   ```

## Success Criteria
- [ ] Column `email_verified` tồn tại trong DB
- [ ] `otp_service.generate_and_store` lưu key vào Redis đúng TTL
- [ ] `otp_service.verify` trả về True khi đúng, False khi sai/hết hạn
- [ ] Rate limit block sau 3 lần request trong 15 phút
- [ ] `email_service.send_otp_email` gọi Resend API thành công (test với email thật)

## Risk Assessment
- **Resend API key chưa có** → cần tạo account resend.com trước
- **init.sql không tự migrate** → cần chạy ALTER TABLE thủ công trên container đang chạy
- **httpx timeout** → đặt timeout=10s, email gửi async (không block request)
