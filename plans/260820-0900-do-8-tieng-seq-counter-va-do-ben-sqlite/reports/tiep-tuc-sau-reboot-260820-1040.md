# Tiếp tục sau khi reboot Windows — 2026-08-20 10:40

Reboot để dọn proxy cổng hỏng của Docker Desktop. Ghi lại để không phải dò lại.

## Trạng thái trước reboot

| Hạng mục | Trạng thái |
|---|---|
| Firmware `radar-node` | Đã flash, verify hash OK. Chạy tốt, không boot loop |
| Node trên LAN | IP **192.168.1.93**, mDNS `radar-node.local`, HTTP 200 ở endpoint OTA |
| WiFi | SSID `mp`, mật khẩu đúng (Windows xác nhận) |
| Node → Windows:1883 | TCP ESTABLISHED |
| Windows → broker | **HỎNG** — `SYN_SENT` tới `172.29.132.234` (VM `docker-desktop`) |
| Backend Go | Chạy, nối broker OK qua network chung |
| DB `samples` | 8 dòng, toàn bộ là mẫu test bơm tay |

## Đã sửa sẵn, tự có hiệu lực sau reboot

- `cloud/mqtt/docker-compose.yml` — network đổi tên cố định `smartbed-mqtt`
- `cloud/presence-ac/docker-compose.yml` — backend nối thêm network `smartbed-mqtt` (external)
- `cloud/presence-ac/.env` — `MQTT_HOST=home-mqtt` (bản cũ ở `.env.bak-260820`)

Hết phụ thuộc `docker network connect` bằng tay và hết phụ thuộc `host.docker.internal`.

## Việc sau khi máy lên

1. Chờ Docker Desktop khởi động xong.
2. Bật stack, **broker trước** (nó tạo network mà backend khai external):
   ```bash
   cd /mnt/d/smartbedv3/cloud/mqtt     && docker compose up -d
   cd /mnt/d/smartbedv3/cloud/presence-ac && docker compose up -d
   docker logs home-backend | grep mqtt      # phải thấy: INFO mqtt connected
   ```
3. Node tự nối lại, không cần đụng gì. Kiểm bằng **log broker**, không dùng `nc`/`netstat`:
   ```bash
   docker logs home-mqtt 2>&1 | grep radar-node
   ```
4. Nếu thấy `radar-node` → chạy Phase 06 (bench 10 phút, 4 tình huống).
5. Nếu vẫn không thấy → đường B: WSL mirrored networking.

## Lưu ý

- IP của WSL distro (`172.29.141.58`) có thể đổi sau reboot. Không sao — cách sửa hiện tại không dùng IP đó.
- IP LAN của máy có thể đổi nếu chưa đặt DHCP reservation. `MQTT_HOST` trong `firmware/radar-node/include/config.h` đang là **192.168.1.120**; IP đổi là phải flash lại node. **Nên đặt reservation trước khi đo thật.**
- Board cần `usbipd.exe attach --wsl --busid 2-4` lại nếu muốn đọc serial. Không cần cho việc đo.
- **Đừng mở COM9 bằng `System.IO.Ports.SerialPort`** — DTR/RTS reset board, và triệu chứng hiện ra là WiFi rớt `reason=8`. Đã mất thời gian vì chuyện này một lần.

## Việc còn treo

1. Phase 06 chưa chạy — cần đường MQTT thông trước.
2. DHCP reservation cho máy host chưa đặt.
3. Chưa commit gì. `git status` sạch phần bí mật: `config.h`, `.env*`, `passwd` đều gitignore.
