# Per-machine dev setup — overrides without dirty git

Mỗi developer có IP LAN riêng và có thể có host port collision riêng. Repo hiện không hardcode bất kỳ IP/port nào của dev nào trong tracked files. Tất cả per-machine values đều ở:

- `backend/.env.dev` (gitignored) — backend env vars + docker port overrides
- `--dart-define=...` flags khi run `flutter run` — Flutter app dev API URL

## Vì sao

Trước đây `backend/docker-compose.dev.yml` hardcode `MQTT_DOMAIN: tcp://192.168.1.15:1883` và `flutter_app/lib/core/constants.dart` hardcode `apiBaseUrl: http://192.168.1.15:8000`. Mỗi dev có IP khác → mỗi lần pull lại merge conflict trên 2 file đó → phải edit lại liên tục → dễ nhầm commit IP của mình lên main → break dev khác.

Giải pháp: tracked files chỉ chứa **defaults + env var substitution**, mỗi dev có override riêng trong file gitignored.

## Backend (`backend/`)

`docker-compose.dev.yml` dùng `${VAR:-default}` syntax:

```yaml
postgres:
  ports:
    - "${POSTGRES_HOST_PORT:-5432}:5432"
redis:
  ports:
    - "${REDIS_HOST_PORT:-6379}:6379"
fastapi:
  ports:
    - "${FASTAPI_HOST_PORT:-8000}:8000"
```

`MQTT_DOMAIN` không còn override trong compose nữa — pydantic Settings đọc thẳng từ `.env.dev` qua `--env-file`.

### Setup `backend/.env.dev` (gitignored)

Copy từ `backend/.env.example` (nếu có) hoặc tạo mới với các keys sau. **Chỉ thêm các block bạn cần** — block "Per-machine port overrides" và `MQTT_DOMAIN` là tùy máy.

```env
ENV=dev
API_DOMAIN=http://<your-mac-lan-ip>:<fastapi-host-port>
MQTT_DOMAIN=tcp://<your-mac-lan-ip>:1883

POSTGRES_USER=sleeppad
POSTGRES_PASSWORD=sleeppad_dev
POSTGRES_DB=sleeppad

JWT_SECRET=dev_jwt_secret_change_me_local_only_192bits_minimum_xxxxxxx

MQTT_USERNAME=
MQTT_PASSWORD=
MQTT_DEVICE_USERNAME=
MQTT_DEVICE_PASSWORD=

FCM_CREDENTIALS_HOST_PATH=./secrets/fcm.json

# Per-machine port overrides — chỉ thêm nếu host port mặc định bị chiếm.
# VD máy đang chạy postgres host (5432), codex-wrapper (6379+8000):
# POSTGRES_HOST_PORT=5434
# REDIS_HOST_PORT=6380
# FASTAPI_HOST_PORT=8010

# SMTP — để rỗng cho dev. email_service sẽ log OTP ra docker stdout thay vì gửi.
# Đọc OTP qua: docker compose ... logs fastapi | grep EMAIL
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_SERVER=
```

### Tìm IP LAN của Mac

```bash
ipconfig getifaddr en0   # Wi-Fi (M-series Mac thường en0)
# hoặc
ipconfig getifaddr en1
```

ESP32 phải reach được IP này → **không dùng `mosquitto` hostname**, phải IP LAN.

### Run dev stack

```bash
cd backend
docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev up -d
```

Verify:
```bash
curl http://localhost:${FASTAPI_HOST_PORT:-8000}/health   # 200
docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev logs fastapi | grep EMAIL   # OTP nếu có register/forgot-password
```

## Flutter (`flutter_app/`)

`lib/core/config/app_env.dart` `DevEnv` đọc URL qua `String.fromEnvironment(...)` với fallback `localhost:8000`.

### Khi nào cần override

| Run target | Cần override không? | Lý do |
|---|---|---|
| iOS Simulator | Không | Simulator share network với Mac → `localhost` resolve được |
| Android emulator | Không (hoặc dùng `10.0.2.2`) | Emulator có DNS đặc biệt cho host |
| Physical iPhone / Android trên LAN | **Có** | Device không resolve được `localhost` của Mac |

### Run command với override

```bash
cd flutter_app
flutter run -t lib/main/main_dev.dart \
  --dart-define=DEV_API_BASE_URL=http://<your-mac-lan-ip>:<fastapi-host-port> \
  --dart-define=DEV_WS_BASE_URL=ws://<your-mac-lan-ip>:<fastapi-host-port>
```

VD máy tôi (Mac LAN `192.168.1.11`, fastapi host port `8010`):

```bash
flutter run -t lib/main/main_dev.dart \
  --dart-define=DEV_API_BASE_URL=http://192.168.1.11:8010 \
  --dart-define=DEV_WS_BASE_URL=ws://192.168.1.11:8010
```

### Cách rút gọn (optional)

**VS Code**: thêm vào `.vscode/launch.json` (đã gitignored hoặc tự gitignore):

```json
{
  "configurations": [
    {
      "name": "Flutter dev (LAN)",
      "request": "launch",
      "type": "dart",
      "program": "lib/main/main_dev.dart",
      "toolArgs": [
        "--dart-define=DEV_API_BASE_URL=http://192.168.1.11:8010",
        "--dart-define=DEV_WS_BASE_URL=ws://192.168.1.11:8010"
      ]
    }
  ]
}
```

**Shell alias** (`~/.zshrc`):

```bash
alias fdev='flutter run -t lib/main/main_dev.dart \
  --dart-define=DEV_API_BASE_URL=http://192.168.1.11:8010 \
  --dart-define=DEV_WS_BASE_URL=ws://192.168.1.11:8010'
```

## OTP email trong dev

`backend/app/auth/email_service.py` check `MAIL_SERVER` trong env — rỗng → skip SMTP send + log OTP ra stdout. Đọc qua docker logs:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev logs -f fastapi | grep EMAIL
```

Output:
```
sleeppad-fastapi | INFO auth.email_service: EMAIL[dev] to=dev@example.com purpose=verify otp=123456 (MAIL_SERVER unset, skipping send)
```

Prod gửi thật qua MXroute SMTP — config trong `backend/.env.prod` (gitignored, copy từ `backend/.env.prod.example`).

## Rule mới cho team

- ✋ **Không commit IP, host port shift, hoặc MAC-LAN-specific value vào tracked files.** Để tất cả vào `.env.dev` (backend) hoặc `--dart-define` (Flutter).
- Khi pull về thấy `docker-compose.dev.yml` hoặc `app_env.dart` bị conflict → ai đó vi phạm rule trên, ping luôn.
- Nếu thấy default chưa đủ generic (VD cần thêm port var mới) → PR thêm `${NEW_VAR:-default}` vào tracked file + docs vào file này.
