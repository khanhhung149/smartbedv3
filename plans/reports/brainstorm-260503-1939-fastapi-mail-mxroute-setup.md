---
type: brainstorm
date: 2026-05-03 19:39
slug: fastapi-mail-mxroute-setup
status: approved
---

# Brainstorm — Switch OTP email từ Mailgun REST sang FastAPI-Mail SMTP (MXroute)

## Problem
- Hiện tại OTP email (verify + forgot-password) gửi qua Mailgun REST API (`backend/app/auth/email_service.py`).
- User muốn switch sang SMTP, dùng MXroute (`ocean.mxroute.com:465`) cho prod.
- Dev không gửi email thật — chỉ log OTP ra docker stdout.

## Current mechanism (audit)
- `email_service.send_otp_email()`: `httpx.AsyncClient` POST → `api.mailgun.net/v3/{domain}/messages`, basic auth `api:${MAILGUN_API_KEY}`, 10s timeout.
- Env vars: `mailgun_api_key`, `mailgun_domain`, `email_from` (hardcode default `"SleepPad <noreply@sleeppad.io>"`).
- Dev fallback: empty `MAILGUN_API_KEY` → log warning + skip.
- Triggered từ `register`, `resend-otp`, `forgot-password` qua FastAPI `BackgroundTasks` (non-blocking).
- Body: HTML only (no plain text fallback).
- OTP layer (`otp_service.py`): 6-digit, Redis 10min TTL, 5 attempts, 3 sends/15min/email.

## Approaches evaluated

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| **FastAPI-Mail** (chosen) | Env vars match user's paste 1:1 (`MAIL_*`, `USE_CREDENTIALS`, `VALIDATE_CERTS`); built-in `ConnectionConfig` Pydantic; aiosmtplib bên dưới; ~30 LOC | +1 dep | ✅ |
| aiosmtplib raw | Ít dep | Phải đổi env names sang SMTP_*; ~50-60 LOC; tự handle MIME multipart | ❌ |
| Both providers (env switch) | Linh hoạt | Over-engineer cho POC; YAGNI | ❌ |

## Final design

### 1. Config (`backend/app/config.py`)
**Drop**: `mailgun_api_key`, `mailgun_domain`
**Add** (match user's paste verbatim, lowercase = pydantic auto):
```python
mail_username: str = ""
mail_password: str = ""
mail_from: str = "hi@sleeptech.me"
mail_from_name: str = "SleepTech"
mail_server: str = ""
mail_port: int = 465
mail_ssl_tls: bool = True
mail_starttls: bool = False
use_credentials: bool = True
validate_certs: bool = True
```
**Keep**: `email_from` removed (replaced by `mail_from` + `mail_from_name`).

### 2. `backend/app/auth/email_service.py` (rewrite ~50 LOC)
```python
"""SMTP email delivery via FastAPI-Mail (MXroute prod, console-log dev)."""
import logging
from fastapi_mail import ConnectionConfig, FastMail, MessageSchema, MessageType
from config import get_settings

logger = logging.getLogger(__name__)

def _conn_config(s) -> ConnectionConfig:
    return ConnectionConfig(
        MAIL_USERNAME=s.mail_username,
        MAIL_PASSWORD=s.mail_password,
        MAIL_FROM=s.mail_from,
        MAIL_FROM_NAME=s.mail_from_name,
        MAIL_SERVER=s.mail_server,
        MAIL_PORT=s.mail_port,
        MAIL_SSL_TLS=s.mail_ssl_tls,
        MAIL_STARTTLS=s.mail_starttls,
        USE_CREDENTIALS=s.use_credentials,
        VALIDATE_CERTS=s.validate_certs,
    )

async def send_otp_email(to_email: str, otp: str, purpose: str) -> None:
    s = get_settings()
    if not s.mail_server:
        # Dev mode: print OTP to docker logs instead of sending real email
        logger.info("EMAIL[dev] to=%s purpose=%s otp=%s (MAIL_SERVER unset, skipping)", to_email, purpose, otp)
        return
    subject = "Verify your email – SleepTech" if purpose == "verify" else "Reset your password – SleepTech"
    msg = MessageSchema(
        subject=subject,
        recipients=[to_email],
        body=_build_html(otp, purpose),
        subtype=MessageType.html,
    )
    try:
        await FastMail(_conn_config(s)).send_message(msg)
    except Exception:
        logger.exception("SMTP send failed for %s", to_email)
        # BackgroundTasks swallows; don't break user flow

def _build_html(otp: str, purpose: str) -> str:
    action = "verify your email" if purpose == "verify" else "reset your password"
    return f"""<div style="font-family:Inter,sans-serif;max-width:480px;margin:auto;padding:32px">
      <h2 style="color:#6366f1">SleepTech</h2>
      <p>Your code to {action}:</p>
      <div style="font-size:36px;font-weight:700;letter-spacing:8px;color:#6366f1;margin:24px 0">{otp}</div>
      <p style="color:#888;font-size:13px">This code expires in 10 minutes. Do not share it with anyone.</p>
    </div>"""
```
- Brand "SleepPad" → "SleepTech" trong subject + HTML body (theo rebrand commit `0ff2de0`).
- Plain text fallback: bỏ qua — FastAPI-Mail sẽ tự sinh từ HTML khi cần. (Nếu deliverability issue → thêm `MessageType.alternative` sau.)

### 3. `backend/app/requirements.txt`
- Add: `fastapi-mail>=1.5`
- `httpx` giữ lại (có thể dùng cho FCM/khác — verify trong implementation phase).

### 4. Env files

**`backend/.env.dev`**: KHÔNG đổi. `MAIL_SERVER` rỗng → console-log mode.

**`backend/.env.prod`** (gitignored, tạo mới — chứa MXroute creds):
```env
ENV=prod
API_DOMAIN=https://api.sleeptech.me
MQTT_DOMAIN=wss://mqtt.sleeptech.me

POSTGRES_USER=__FILL__
POSTGRES_PASSWORD=__FILL__
POSTGRES_DB=sleeptech

JWT_SECRET=__FILL_64+chars__

MQTT_USERNAME=__FILL__
MQTT_PASSWORD=__FILL__
MQTT_DEVICE_USERNAME=__FILL__
MQTT_DEVICE_PASSWORD=__FILL__

FCM_CREDENTIALS_HOST_PATH=./secrets/fcm.json

# SMTP via MXroute
MAIL_USERNAME=hi@sleeptech.me
MAIL_PASSWORD=<from-password-manager>
MAIL_FROM=hi@sleeptech.me
MAIL_FROM_NAME=SleepTech
MAIL_SERVER=ocean.mxroute.com
MAIL_PORT=465
MAIL_SSL_TLS=True
MAIL_STARTTLS=False
USE_CREDENTIALS=True
VALIDATE_CERTS=True
```

**`backend/.env.prod.example`** (gitignored.example sẽ commit, KHÔNG có creds):
- Same keys, all values empty/placeholder, có comment giải thích từng group.
- Để dev khác clone repo có template tham khảo.

### 5. Router (`auth/router.py`)
**Không sửa.** Call site `send_otp_email(email, otp, purpose)` giữ y nguyên.

### 6. Memory note update
`~/.claude/projects/-Users-michaelphan-projects-sleep-pad-ai/memory/dev-lan-endpoints.md`:
- Ghi: dev không có MAIL_* → OTP đọc qua `docker compose logs fastapi`.

## Risks & caveats

| Risk | Mitigation |
|---|---|
| MXroute password đã lộ trong session log | **Rotate password sau khi setup** (MXroute control panel → mail user → change password). |
| `BackgroundTasks` không retry — SMTP hiccup → email mất | Same risk như Mailgun hiện tại. Job queue (arq/celery) là follow-up nếu cần SLA email. YAGNI now. |
| FastAPI-Mail ConnectionConfig validate strict (Pydantic v2) | Test instantiation trong dev với MAIL_SERVER rỗng — nếu raise validation error, branch sớm trước khi gọi `_conn_config(s)`. |
| HTML-only có thể vào spam folder ở 1 số provider | Monitor deliverability sau prod launch. Thêm text/plain alternative nếu thấy issue. |
| Hardcoded subject string không dịch i18n | Out of scope — i18n lib mới chỉ cho mobile UI. Backend i18n là task khác. |

## Success criteria
- [ ] `flutter run -t lib/main/main_dev.dart` → register flow → OTP xuất hiện trong `docker compose logs fastapi`
- [ ] Forgot-password flow → OTP cũng log dev mode
- [ ] Prod env (manual smoke test với MAIL_SERVER set) → email thực tế đến `hi@sleeptech.me` inbox
- [ ] Brand subject + HTML hiển thị "SleepTech" không phải "SleepPad"
- [ ] No regressions: register/login/verify-email/resend-otp/reset-password endpoints same status codes

## Files affected
- modify: `backend/app/config.py` (drop mailgun_*, add mail_*)
- modify: `backend/app/auth/email_service.py` (rewrite)
- modify: `backend/app/requirements.txt` (+fastapi-mail)
- create: `backend/.env.prod` (gitignored, MXroute creds + placeholders)
- create: `backend/.env.prod.example` (template, no creds, gitignored.example sẽ override để commit)
- update memory: `dev-lan-endpoints.md`

## Unresolved questions
1. `.env.prod.example` có cần commit vào git không? `backend/.gitignore` có `.env.*.local` chứ không exclude `.env.prod.example` — nếu user muốn share template, để committed. Nếu để per-developer, gitignore thêm.
2. Khi rotate password MXroute, có muốn tôi tự động update `.env.prod` không, hay user manual?
3. `fastapi-mail` version range: pin `>=1.5,<2.0` hay open `>=1.5`? (Pin tránh breaking change tương lai.)
