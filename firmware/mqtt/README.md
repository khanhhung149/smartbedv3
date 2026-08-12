# MQTT Broker & Topic Contract

Nền tảng giao tiếp cho 2 node ESP32 (door node + room node) và Golang backend (làm sau).
Broker: **Mosquitto 2** chạy qua Docker. LAN nội bộ, chưa dùng TLS.

## Cài đặt lần đầu

```bash
cd firmware/mqtt

# 1. Tạo user + password (tạo file ./passwd). Đổi <user> theo ý bạn.
#    Cần mosquitto-clients trên host, HOẶC chạy qua image:
docker run --rm -it -v "$PWD":/mosquitto/config eclipse-mosquitto:2 \
  mosquitto_passwd -c /mosquitto/config/passwd <user>
#    -> nhập password 2 lần. Bỏ cờ -c nếu thêm user thứ 2 (giữ user cũ).

# 2. Start broker
docker compose up -d

# 3. Xem log
docker logs -f home-mqtt
```

`passwd` **KHÔNG commit** (đã nằm trong `.gitignore`). Xem `passwd.example` để biết định dạng.

## Kiểm tra broker (Phase 1 success criteria)

Thay `<host>` bằng IP máy chạy broker (ví dụ `192.168.1.50`), `<user>`/`<pass>` vừa tạo:

```bash
# Terminal A — subscribe toàn bộ, in cả topic (-v)
mosquitto_sub -h <host> -t 'home/#' -u <user> -P <pass> -v

# Terminal B — publish thử từng topic
mosquitto_pub -h <host> -t home/door/motion    -u <user> -P <pass> -m '{"ts":1700000000000,"motion":true}'
mosquitto_pub -h <host> -t home/room/presence  -u <user> -P <pass> -m '{"ts":1700000000000,"present":true}' -r
mosquitto_pub -h <host> -t home/room/ac_cmd    -u <user> -P <pass> -m '{"cmd":"on"}'
mosquitto_pub -h <host> -t home/room/ac_learn  -u <user> -P <pass> -m '{"button":"on"}'

# Xác nhận auth bắt buộc: KHÔNG có -u/-P -> phải bị từ chối
mosquitto_sub -h <host> -t 'home/#'   # kỳ vọng: Connection refused, not authorised
```

## Topic Contract

Tất cả topic dùng **QoS 1** (đảm bảo delivery khi WiFi chập chờn).

| Topic | Publisher | Subscriber | Payload | Retain |
|-------|-----------|------------|---------|--------|
| `home/door/motion` | Door node | Backend | `{"ts": <unix_ms>, "motion": true}` | false |
| `home/room/presence` | Room node | Backend | `{"ts": <unix_ms>, "present": true\|false}` | **true** |
| `home/room/ac_cmd` | Backend (test: `mosquitto_pub` tay) | Room node | `{"cmd": "on"\|"off"}` | false |
| `home/room/ac_learn` | Backend (test: `mosquitto_pub` tay) | Room node | `{"button": "on"\|"off"}` | false |
| `home/room/snore_event` | Voice node | Backend | `{"ts": <unix_ms>, "confidence": <0-1>, "duration_ms": <int>}` | false |

### Ghi chú schema
- `ts`: Unix epoch **mili-giây**. Firmware đồng bộ giờ qua NTP (`pool.ntp.org`) lúc boot; nếu chưa sync xong thì `ts` = 0 (backend bỏ qua giá trị 0 được).
- `home/room/snore_event`: **PLACEHOLDER** (scaffold kiến trúc, xem
  `docs/voice-node-snore-wakeword-architecture.md`) — `confidence` hiện là RMS chuẩn hoá, KHÔNG phải
  điểm số từ model snore thật (chưa có model). `voice-node` KHÔNG đồng bộ NTP — `ts` hiện là `millis()`
  (uptime tương đối từ lúc boot), KHÔNG PHẢI unix epoch thật. Đủ để phân biệt thứ tự/khoảng cách giữa
  các event, nhưng backend KHÔNG được suy ra ngày giờ thật từ giá trị này.
  Event Manager debounce N=3 cửa sổ liên tiếp (~3s) + cooldown 5s trước khi gửi event kế tiếp.
- `home/room/presence` **retain=true**: client mới connect nhận ngay trạng thái hiện diện cuối cùng, không phải đợi lần đổi tiếp theo.
- `home/door/motion` retain=false: đây là event tức thời, không có "trạng thái cuối".
- Mã IR học được lưu **local trên NVS của room node** (quyết định MVP) — KHÔNG có topic MQTT cho mã IR trong contract này. Backup/restore qua backend là việc sau.

### Cấu hình cho firmware
Điền các giá trị này vào `firmware/door-node/include/config.h` và `firmware/room-node/include/config.h`
(copy từ `config.h.example`):

- `MQTT_HOST` = IP `<host>` broker trên LAN
- `MQTT_PORT` = `1883`
- `MQTT_USER` / `MQTT_PASS` = user/pass vừa tạo bằng `mosquitto_passwd`

## Vận hành

- Broker restart tự động (`restart: unless-stopped`) khi crash hoặc máy reboot.
- Nếu broker khác máy với 2 node ESP32: mở port `1883` trên firewall/router của máy chạy broker.
- Message retain nằm trong volume `mosquitto-data`, sống qua `docker compose restart`.
