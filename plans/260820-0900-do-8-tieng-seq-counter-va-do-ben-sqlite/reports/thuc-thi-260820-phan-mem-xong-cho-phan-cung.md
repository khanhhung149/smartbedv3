# Báo cáo thực thi — 2026-08-20

Phần phần mềm của plan đã xong và verify. Phần cần phần cứng chưa chạy được.

## Đã làm

| Phase | Kết quả |
|---|---|
| 01 — cột `seq`/`boot` | `events.Sample` + `store.Sample` dùng `*uint32`; cột SQLite nullable; migration đọc `PRAGMA table_info` rồi `ALTER` cột thiếu |
| 02 — độ bền SQLite | DSN `_pragma=journal_mode(WAL)&synchronous(NORMAL)&busy_timeout(5000)`; `Open` báo lỗi nếu WAL không bật; cắt trần giãn xuống mỗi 10.000 mẫu |
| 03 — firmware | `sample_seq` + `boot_count` (NVS, bump một lần lúc boot); `SAMPLE_RB_LEN` 256 → 288 |
| 04 — cấu hình | `config.h.example` cảnh báo `MQTT_HOST` compile cứng + hướng dẫn DHCP reservation |
| 05 — runbook | `docs/runbook-dem-do-8-tieng.md`, phủ cả hai đường ống |

## Bằng chứng

| Hạng mục | Kết quả |
|---|---|
| `go vet ./... && go test ./... -count=1` | xanh 6/6 package |
| Test mới | 8 trong `store` + 4 trong `events` |
| `gofmt -l` trên file đã sửa | sạch (`internal/voice/command_test.go` lệch từ trước, không đụng tới) |
| Độ dài payload | biên dịch format string thật bằng gcc: **259 byte**, buffer 288 vừa, 256 tràn |
| Tốc độ ghi (3.600 mẫu) | cũ **142 mẫu/s** → mới **4.823 mẫu/s**, nhanh hơn 34× |
| WAL trên DrvFs (`/mnt/d`) | bật được, ghi OK — `Open` báo lỗi cứng khi không có WAL là an toàn ở đây |
| Truy vấn phân tích runbook | chạy trên DB dựng sẵn 21 mẫu có 3 loại lỗi: tìm đúng lỗ hổng 5 mẫu, đúng quãng trượt nhịp 3000ms, đúng 2 lần boot |
| `scripts/check-doc-links.sh` | sạch |

## Hai đính chính so với lúc lập plan

1. **Cấu hình SQLite cũ không "gần như chắc gãy".** Đo ra 142 mẫu/s — vẫn trên 10Hz, sẽ trụ được trên SSD laptop này. Giá trị thật của thay đổi là biên an toàn: 14× thay vì 480×.
2. **Lý do cần `PARTITION BY boot` trong runbook viết sai.** Reset không sinh lỗ hổng giả — `seq` tụt về 0 cho hiệu số âm, bộ lọc `> 1` bỏ qua im lặng. Hỏng theo chiều khó thấy hơn: dòng ranh giới bị bỏ sót nên mẫu mất quanh lúc reset không bị phát hiện. Runbook đã sửa.

## Chưa làm được — thiếu công cụ trên máy này

| Việc | Thiếu | Hệ quả |
|---|---|---|
| `idf.py build` cho `radar-node` | ESP-IDF | Firmware **chưa từng biên dịch**. Format string đã kiểm riêng bằng gcc nhưng phần NVS và include `nvs.h` chưa qua compiler thật |
| Chạy thử lệnh Docker trong runbook | Docker (chưa bật WSL integration) | Các lệnh compose/`docker run` trong runbook **viết ra chứ chưa chạy** |
| Phase 06 — bench 10 phút | board + ESP-IDF + Docker | Chưa có bằng chứng `seq` phát hiện được mất mẫu trên phần cứng thật |

## Việc tiếp theo

1. Build firmware trên máy có ESP-IDF, sửa lỗi biên dịch nếu có.
2. Flash, chạy Phase 06 — đặc biệt tình huống ngắt WiFi 30 giây, vì đó là ca chứng minh `seq` có tác dụng.
3. Chạy từng lệnh Docker trong runbook, sửa lệnh nào sai.
4. Xong ba bước trên mới tới đêm đo thật.

---

## Cập nhật 10:15 — hai blocker đã gỡ

Docker Desktop đã bật WSL integration, và `radar-node` dùng `framework = espidf` qua PlatformIO
(đã cài sẵn) nên không cần ESP-IDF riêng.

| Việc | Kết quả |
|---|---|
| `pio run -e lolin_s2_mini` | **SUCCESS**, không cảnh báo. RAM 17,1% · Flash 47,2% |
| Stack đường A chạy thật | `home-mqtt` + `home-backend` up, `INFO mqtt connected` |
| `PRAGMA journal_mode` trên volume Docker | **wal** — `Open` mới qua được trên hệ thật |
| E2E MQTT → SQLite | 8 mẫu qua broker thật: `seq`/`boot` đúng cột; NULL (firmware cũ) phân biệt được với 0; payload 259B ở max uint32 parse trọn |
| Truy vấn lỗ hổng `seq` trong runbook | tìm đúng: mất 5 mẫu giữa `seq` 2 và 8 |

### Sự cố phải xử lý: `host.docker.internal` không dùng được

`.env.example` để `MQTT_HOST=host.docker.internal`. Trên Docker Desktop backend **không** nối được
broker qua giá trị này. Đánh lừa ở chỗ: `nc -z host.docker.internal 1883` báo **mở**, nhưng client
MQTT không nối được và broker **không ghi nhận connection nào**. Backend chỉ in một dòng
`mqtt chưa kết nối trong timeout` rồi im lặng retry mãi — HTTP vẫn lên, trông như đang chạy.

Kiểm chứng bằng probe paho cùng options, cùng network: hỏng cả khi dùng tên lẫn IPv4 trực tiếp.
Chạy được khi cho hai container chung network và gọi bằng tên `home-mqtt`, hoặc khi dùng IP LAN.

Đã sửa `.env` local (bản cũ ở `.env.bak-260820`) và ghi cảnh báo + mục kiểm số 0 vào runbook.

### File local đã tạo (đều gitignore, không vào repo)

| File | Mục đích | Cần làm gì |
|---|---|---|
| `firmware/radar-node/include/config.h` | để build được | **Phải điền giá trị thật** — đang là `PLACEHOLDER-SSID` / `PLACEHOLDER-PASS` / `PLACEHOLDER-OTA`. Flash bản này thì node không lên WiFi |
| `cloud/mqtt/passwd` | broker cần, nếu không từ chối mọi connect | Đã tạo khớp `MQTT_USER`/`MQTT_PASS` trong `.env`. Dùng được luôn |
| `cloud/presence-ac/.env.bak-260820` | bản `.env` trước khi sửa `MQTT_HOST` | Xoá khi không cần |

## Còn thiếu duy nhất: phần cứng

`/dev/ttyUSB*` và `/dev/ttyACM*` đều trống — board chưa cắm (WSL cần `usbipd attach` từ Windows).

Phase 06 cần board để chứng minh `seq` **phát hiện được** mất mẫu trên phần cứng thật. Mọi thứ
khác đã chạy end-to-end.
