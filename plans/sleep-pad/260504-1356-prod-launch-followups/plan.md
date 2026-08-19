---
type: plan
date: 2026-05-04 13:56
slug: prod-launch-followups
status: pending
---

# Production launch follow-ups

Các task còn lại sau khi prod stack đầu tiên live tại `https://api.sleeptech.me` ngày 2026-05-04 (commit `1b33f76`).

Ưu tiên giảm dần. Mỗi item có thể thành 1 PR riêng.

## P0 — phải làm trong 24-48h

- [ ] **Check inbox `hi@sleeptech.me` (MXroute)** xác nhận test email "Reset your password – SleepTech" tới. Nếu không thấy → debug SMTP (kiểm tra log fastapi cho exception khi `await FastMail.send_message`).
- [ ] **Rotate secrets đã lộ trong session log**:
  - MXroute mail password (`MAIL_PASSWORD` trong `backend/.env.prod` cả local lẫn VPS)
  - Cloudflared tunnel token (`CLOUDFLARED_TUNNEL_TOKEN` — tạo tunnel mới trên Cloudflare Zero Trust + paste lại)
  - Sau khi rotate: `rsync` `.env.prod` lên VPS rồi `docker compose ... up -d` để restart container với token/pass mới
- [ ] **VPS disk monitor + cleanup** — xem audit report `plans/260504-1356-prod-launch-followups/disk-audit.md` (tạo tự động khi user hỏi disk usage). Plan giải pháp dựa trên kết quả.

## P1 — trước khi onboard user thật

- [ ] **Mobile app prod build → đổi `ProdEnv` URLs**: `flutter_app/lib/core/config/app_env.dart`
  - `apiBaseUrl: 'https://api.sleeppad.io'` → `'https://api.sleeptech.me'`
  - `wsBaseUrl: 'wss://api.sleeppad.io'` → `'wss://api.sleeptech.me'`
  - Rebuild qua `flutter build ipa -t lib/main/main_prod.dart` + ship app store
- [ ] **Real Firebase service account JSON cho FCM push**:
  - Hiện tại `backend/secrets/fcm.json` = `{}` placeholder, FastAPI log warning `FCM credentials file looks like a stub — push disabled`
  - Tạo Firebase project SleepTech → service account → download JSON → `scp` to VPS `/opt/sleeptech/backend/secrets/fcm.json` (`chmod 600`)
  - Restart fastapi container → log expect "FCM initialized" không còn warning

## P2 — chuyển từ POC sang real product

- [ ] **MQTT cho ESP32 prod (WSS)**: firmware hiện dùng `PubSubClient` (TCP only), prod chỉ expose `mqtt.sleeptech.me` qua WSS. Lựa chọn:
  - **(a) Upgrade firmware sang `espMqttClient` lib** — support WSS native, không cần expose extra port. Project memory đã list trong "Production TODOs". Đây là path đúng.
  - (b) Open thêm port 8883 (MQTT TCP TLS) trên VPS qua cloudflared TCP tunnel — phá pattern "no open ports", phức tạp hơn.
- [ ] **Mosquitto Dynamic Security per-device creds**: hiện 2 user fixed (`sleeppad-subscriber` cho backend + `sleeppad-device` shared). Khi nhiều thiết bị, share 1 password = leak 1 device → mọi device compromised. Per-device creds cần Dynamic Security plugin.
- [ ] **Alembic migrations**: schema hiện chỉ apply từ `postgres/init.sql` lúc volume mount lần đầu. Schema thay đổi tương lai sẽ cần `alembic init` + revisions + `alembic upgrade head` step trong deploy.
- [ ] **Backup Postgres + Redis volume**: `sleeppad_postgres_data` volume nằm trong docker. Cần daily snapshot scp về backup server / S3.
- [ ] **CI/CD auto deploy**: hiện deploy bằng tay (rsync + ssh). VPS đã có `gh-runner` self-hosted. Setup workflow trigger trên push main → rsync + restart compose.

## P3 — quality of life / hardening

- [ ] **`.env.prod.example` lên VPS** (optional) — placeholder tham khảo nếu cần re-create env file.
- [ ] **Healthcheck endpoint chi tiết hơn**: `/health` hiện chỉ 200. Thêm `/health/deep` check Postgres + Redis + MQTT connectivity.
- [ ] **Rate limiting global**: hiện chỉ rate-limit OTP (3/15min/email). API public lộ `auth/login` qua brute force. Thêm slowapi hoặc nginx-tier rate limit.
- [ ] **Sentry / error tracking**: capture exceptions trong FastAPI prod.
- [ ] **`docker logs` rotation**: docker JSON file driver mặc định không cap size → log vô tận. Add `max-size` + `max-file` to compose hoặc daemon.json.
- [ ] **Cloudflare WAF rules**: ban suspicious patterns (massive 4xx, OWASP top 10) ở edge.

## Reference docs đã có

- `docs/per-machine-dev-setup.md` — dev environment per-machine config (docker-compose + dart-define)
- `docs/protocols/ble-provisioning-and-mqtt-auth.md` — BLE UUIDs + MQTT %c ACL pattern (per project memory)
- `plans/reports/brainstorm-260503-1939-fastapi-mail-mxroute-setup.md` — SMTP migration design

## Unresolved questions

1. App store ship plan: iOS TestFlight first hay submit thẳng review? Cần `me.sleeptech.app` bundle ID (đã rebrand từ `com.sleeppad.sleepPad` per commit `40061a8`).
2. Khi nào chuyển từ shared MQTT device password sang per-device? Threshold nào (số device, threat model)?
3. VPS này share với `evsafe-*` project — có cần migrate ra VPS riêng cho SleepTech khi scale, hay co-exist OK?
