# Brainstorm — sẵn sàng cho đêm đo 8 tiếng (tiêu chí 1) + tính di động sang Jetson

- **Ngày:** 2026-08-20 · **Branch:** master · **Loại:** brainstorm, chưa implement
- **Bối cảnh:** [báo cáo tiến độ 19/08](./monorepo-merge-and-phase-01-gate-check-260819-1709-smartbed-v3-consolidation-report.md)
- **Phase:** 01 — cụm cảm biến + data pipeline
- **Quyết định của user:** chạy **đủ hết node**; **sửa luôn** phần bền vững SQLite

---

## Đính chính báo cáo 19/08

Báo cáo trước ghi đường 10Hz đi qua FastAPI → TimescaleDB. **Sai.** Đọc code cho ra hai đường ống tách biệt:

| Đường | Node | Topic | Consumer | Đích | Nhịp |
|---|---|---|---|---|---|
| A | `radar-node` | `home/room/sample` | backend Go `internal/mqttclient/client.go:18` | SQLite `samples` (`store.go:72`) | 10Hz |
| B | `sleep-pad-node` | `sleeppad/<id>/sec\|min\|temp` | FastAPI `mqtt/subscriber.py:54` | TimescaleDB | 1Hz |

Hệ quả:

- **Tiêu chí 1** (8h, mất <0.1%) nằm trên đường A. Chỉ cần mosquitto + backend Go.
- **Tiêu chí 5** (3 đêm trong DB + dashboard) nằm trên đường B. Chạy radar bao nhiêu đêm cũng không tick được.
- Con số **288.000 mẫu** chỉ đúng cho đường A. Đường B là 1Hz → 28.800 khung/đêm.

Chạy đủ hết node nghĩa là dựng **cả hai** stack cùng lúc, hai broker, phải tránh va cổng 1883/1884.

---

## Vấn đề 1 — không truy được nguyên nhân mất mẫu

Payload `home/room/sample` (`main.c:199`) không có số thứ tự. Tỷ lệ mất tính được nhưng không phân biệt được MCU trượt nhịp / mất trên đường / MCU reset.

### Phương án

| # | Nội dung | Đánh giá |
|---|---|---|
| A | Chỉ thêm `seq` (uint32, +1 mỗi mẫu) | **Không đủ.** MCU reboot làm `seq` về 0 → giá trị trùng, không phân biệt reboot với lỗi |
| B | `seq` + `boot` (uint32 trong NVS, +1 mỗi lần khởi động) | **Chọn.** Tách bạch cả ba nguyên nhân, chi phí thêm ~1 dòng NVS |
| C | Bỏ QoS0 sang QoS1 cho sample | Bác. QoS1 ở 10Hz chặn vòng chính chờ ack; đây là dữ liệu xu hướng. Và làm vậy là *giấu* mất mẫu chứ không đo được nó |

### Bảng đọc kết quả (phương án B)

| Hiện tượng trong DB | Kết luận | Hướng sửa |
|---|---|---|
| `seq` thủng lỗ, `ts` liền mạch | mất trên đường | WiFi/MQTT/broker |
| `seq` liền, `ts` nhảy quãng | MCU trượt nhịp | vòng lặp, sensor UART |
| `boot` tăng giữa đêm | MCU reset | nguồn, brownout, watchdog |

Ring buffer (`main.c:170`) giữ nguyên payload nên `seq` của mẫu phát lại vẫn đúng — không cần đụng.

### Chạm vào

`firmware/radar-node/src/main.c` · `cloud/presence-ac/internal/events/events.go` · `cloud/presence-ac/internal/store/store.go` (2 cột + `ALTER TABLE` có bảo vệ, vì `CREATE TABLE IF NOT EXISTS` không thêm cột vào DB cũ) · test đối chiếu.

---

## Vấn đề 2 — bền vững ghi SQLite ở 10Hz

`store.go:49` mở DB trần: không `journal_mode=WAL`, không set `synchronous` → mặc định rollback journal + `synchronous=FULL`, mỗi transaction có fsync.

`AppendSample` (`store.go:196`) chạy **thêm** một `DELETE ... WHERE id <= (SELECT MAX(id)) - 11000000` sau **mỗi** insert → 20 transaction fsync/giây, ~576.000 transaction qua 8 tiếng.

Rủi ro: backend chậm hơn nguồn mẫu thì mất mẫu **do chính backend**, và nó lẫn vào con số cần đo. Trên Jetson chạy microSD gần như chắc gãy.

**Chọn:** bật WAL + `synchronous=NORMAL`; giãn câu cắt trần xuống định kỳ thay vì mỗi mẫu. Trần `maxSamples` giữ nguyên (quyết định cũ, không đảo).

---

## Vấn đề 3 — chuyển host laptop → Jetson sau này

### Kiểm chứng arm64 (manifest thật trên Docker Hub, 20/08)

| Image | arm64 |
|---|---|
| `timescale/timescaledb:latest-pg16` | ✅ |
| `redis:7-alpine` | ✅ |
| `eclipse-mosquitto:2` | ✅ |
| `python:3.12-slim-bookworm` | ✅ |
| `golang:1.25` | ✅ |

Ba image tự build (fastapi, backend Go, asr) build lại trên Jetson là ra arm64. `cloud/asr` (faster-whisper) là chỗ rủi ro wheel aarch64 duy nhất — không nằm trên đường đo.

### Ràng buộc thật không nằm ở Docker

`firmware/radar-node/include/config.h` **compile cứng** `MQTT_HOST`. Đổi máy host mà IP đổi ⇒ **flash lại node**, không phải sửa config.

**Khử ngay:** DHCP reservation cho máy host, `MQTT_HOST` trỏ IP đó. Sau này gán đúng IP ấy cho Jetson ⇒ firmware không đụng.

### Hai điều kiện cho lần chuyển thật (sau này)

1. Postgres/SQLite **không** để trên microSD. Cần NVMe + `data-root` Docker trỏ sang đó.
2. Không copy thư mục volume Postgres x86 → arm64. Dùng `pg_dump`/`pg_restore`.

---

## Bẫy vận hành phát hiện được khi soi code

- `subscriber.py:107` — thiết bị **chưa pair** thì mọi frame bị drop im lặng. Không pair sleep-pad node trước đêm đo ⇒ sáng ra 0 dòng, trông y hệt mất 100%.
- `subscriber.py:_insert_sec` — `time` (ts thiết bị) **không đáng tin**: pad trôi đồng hồ, firmware không gửi frame sync 0x0B. Đếm mất trên đường B phải theo `received_at`, không theo `time`.
- Cổng 1883/1884: chạy đủ hết node ⇒ hai broker cùng máy. `MQTT_HOST_PORT`/`MQTT_WS_HOST_PORT` đã có, phải set đúng và `MQTT_HOST` trong `config.h` từng node phải khớp broker của nó.

---

## Giải pháp chốt

1. `seq` + `boot` cho `radar-node`, xuyên suốt tới cột SQLite.
2. WAL + `synchronous=NORMAL` + giãn câu cắt trần trong `store.go`.
3. DHCP reservation + `config.h.example` cập nhật + ghi vào runbook (user tự đặt trên router và sửa `config.h` thật — file bị gitignore).
4. Runbook đêm đo trong `docs/`, phủ **cả hai** đường ống.

---

## Tiêu chí nghiệm thu

- Node chạy 10 phút: `seq` liên tục không thủng, `boot` không đổi.
- Backend theo kịp 10Hz, không dựng backlog.
- Đếm mẫu ra đúng ±0,1% so với thời lượng × 10Hz.
- Sleep-pad node đã pair, có dòng vào `sec_data` trước khi đi ngủ.

## Việc KHÔNG làm đợt này

Chuyển stack sang Jetson · dựng `edge/collector` · node piezo · tiêu chí 3 (LD2510B) · đường ASR.

## Câu hỏi tồn đọng

1. `seq`/`boot` có cần cho đường B (sleep-pad) không? Khung do module pad sinh, không do ESP32 — thêm counter ở đó là vá ở tầng trung chuyển, đo được mất từ ESP32 trở đi chứ không đo được từ pad. Cần chốt phạm vi.
2. Chạy đủ hết node thì tiêu chí 5 cần 3 đêm — có chạy 3 đêm liên tiếp luôn hay đêm đầu chỉ để soát thiết bị?
