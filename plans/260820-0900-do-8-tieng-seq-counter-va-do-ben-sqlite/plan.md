---
type: plan
date: 2026-08-20 09:00
slug: do-8-tieng-seq-counter-va-do-ben-sqlite
status: in-progress
priority: P1
branch: master
mode: tdd
brainstorm: plans/reports/brainstorm-phase01-8h-run-readiness-260820-0900-seq-counter-sqlite-durability-jetson-portability-report.md
blockedBy: []
blocks: [260713-1019-smartbed-v3-mvp]
---

# Sẵn sàng đêm đo 8 tiếng — sequence counter + độ bền ghi SQLite

- **Mục tiêu:** đưa tiêu chí 1 của Phase 01 (ghi liên tục 8 tiếng, mất dưới 0,1% mẫu) từ "chạy được" sang "chạy ra con số truy được nguyên nhân".
- **Nguồn:** [brainstorm 20/08](../reports/brainstorm-phase01-8h-run-readiness-260820-0900-seq-counter-sqlite-durability-jetson-portability-report.md)
- **Plan cha:** [`260713-1019-smartbed-v3-mvp`](../260713-1019-smartbed-v3-mvp/plan.md) — Phase 01
- **Quyết định user 20/08:** chạy **đủ hết node** trong đêm đo; **sửa luôn** phần bền vững SQLite.

## Vấn đề

Đường dữ liệu đã thông nhưng đêm đo hiện tại sẽ cho ra một con số **không truy được nguyên nhân**:

1. Payload `home/room/sample` không có số thứ tự → không phân biệt được MCU trượt nhịp / mất trên đường / MCU reset.
2. `store.go` mở SQLite trần (rollback journal + `synchronous=FULL`) và chạy câu `DELETE` cắt trần sau **mỗi** insert → ~20 transaction có fsync mỗi giây, ~576.000 transaction qua 8 tiếng. Backend chậm hơn nguồn mẫu thì mất mẫu **do chính backend**, lẫn vào đúng con số cần đo.
3. `MQTT_HOST` compile cứng trong `config.h` → đổi máy host là phải flash lại node.

## Hai đường ống (đính chính báo cáo 19/08)

| Đường | Node | Topic | Consumer | Đích | Nhịp |
|---|---|---|---|---|---|
| A | `radar-node` | `home/room/sample` | Go `internal/mqttclient/client.go:71` | SQLite `samples` | 10Hz |
| B | `sleep-pad-node` | `sleeppad/<id>/sec\|min\|temp` | FastAPI `mqtt/subscriber.py:54` | TimescaleDB | 1Hz |

Tiêu chí 1 nằm trên đường A. Tiêu chí 5 nằm trên đường B. Chạy đủ hết node = dựng cả hai stack, hai broker cùng máy.

## Quyết định thiết kế

| # | Quyết định | Lý do |
|---|---|---|
| 1 | `seq` (RAM, +1 mỗi mẫu) **và** `boot` (NVS, +1 mỗi lần khởi động) | Chỉ `seq` là không đủ: MCU reboot làm nó về 0, sinh giá trị trùng không phân biệt được với lỗi |
| 2 | Hai cột SQLite **nullable** (`NULL` = firmware cũ) | `NULL` phân biệt được với `seq=0` của mẫu đầu tiên sau boot |
| 3 | Giữ QoS0 cho sample | QoS1 ở 10Hz chặn vòng chính chờ ack, và làm vậy là *giấu* mất mẫu chứ không đo được nó |
| 4 | `SAMPLE_RB_LEN` 256 → 288 | Payload xấu nhất hiện tại 224B; thêm `seq`+`boot` là 259B (+NUL = 260) → `snprintf` cắt cụt im lặng, JSON hỏng, backend drop mẫu |
| 5 | WAL + `synchronous=NORMAL` qua DSN `_pragma=` | modernc.org/sqlite nhận tham số này; không phải viết thêm code exec pragma |
| 6 | Giãn câu cắt trần: chạy mỗi `trimInterval` mẫu | Bỏ hẳn thì DB phình khi retention lỗi — trần là quyết định cũ, không đảo |
| 7 | `maxSamples`/`trimInterval` thành field của `Store` | Test không thể chèn 11 triệu dòng; cần hạ ngưỡng trong test |
| 8 | Không thêm `seq` cho đường B đợt này | Khung 0x85 do module pad sinh, không do ESP32 — thêm counter ở ESP32 chỉ đo được từ chỗ trung chuyển trở đi |

## Phases

| # | File | Nội dung | Ưu tiên | Phụ thuộc | Trạng thái |
|---|---|---|---|---|---|
| 01 | [phase-01-go-cot-seq-boot.md](phase-01-go-cot-seq-boot.md) | Go: cột `seq`/`boot`, migration, parse, seed-csv | P1 | — | done |
| 02 | [phase-02-go-do-ben-sqlite.md](phase-02-go-do-ben-sqlite.md) | Go: WAL + `synchronous=NORMAL` + giãn cắt trần | P1 | 01 | done |
| 03 | [phase-03-firmware-phat-seq-boot.md](phase-03-firmware-phat-seq-boot.md) | Firmware `radar-node`: phát `seq`+`boot`, nới buffer | P1 | 01 | done |
| 04 | [phase-04-cau-hinh-ip-tinh.md](phase-04-cau-hinh-ip-tinh.md) | `config.h.example` + hướng dẫn DHCP reservation | P2 | — | done |
| 05 | [phase-05-runbook-dem-do.md](phase-05-runbook-dem-do.md) | Runbook đêm đo trong `docs/`, phủ cả hai đường ống | P1 | 02, 03, 04 | done |
| 06 | [phase-06-nghiem-thu-bench-10-phut.md](phase-06-nghiem-thu-bench-10-phut.md) | Chạy bench 10 phút, ghi số đo thật | P1 | 05 | **blocked** — chờ board |

## Trạng thái thực thi — 2026-08-20

Phần phần mềm đã xong và verify. Phần cần phần cứng chưa chạy được trong phiên này.

| Việc | Trạng thái | Ghi chú |
|---|---|---|
| Cột `seq`/`boot` + migration | ✅ | 10 test mới, `go test ./... -count=1` xanh 6/6 package |
| WAL + `synchronous=NORMAL` + giãn cắt trần | ✅ | Đo thật: **142 → 4.823 mẫu/s** (34×) |
| Firmware phát `seq`+`boot`, buffer 288 | ✅ | `pio run` SUCCESS, không cảnh báo. RAM 17,1% Flash 47,2% |
| `config.h.example` + hướng dẫn IP | ✅ | |
| Runbook `docs/runbook-dem-do-8-tieng.md` | ✅ | Lệnh đã chạy thật trên stack thật; phát hiện + sửa lỗi `host.docker.internal` |
| E2E MQTT → SQLite | ✅ | 8 mẫu qua broker thật: `seq`/`boot` đúng, NULL ≠ 0, payload 259B parse được, truy vấn tìm đúng lỗ hổng 5 mẫu |
| Bench 10 phút trên board | ⛔ | **Chỉ còn thiếu phần cứng** — board chưa cắm (`/dev/ttyUSB*` trống) |

### Đính chính từ bài đo thật

Plan viết cấu hình SQLite cũ "gần như chắc gãy" ở 10Hz. Đo ra **142 mẫu/s** — vẫn trên 10Hz,
nên nó sẽ trụ được trên SSD laptop này. Giá trị thật của thay đổi là **biên an toàn**:
14× thay vì 480×. Trên microSD Jetson hoặc khi máy bận thì biên 14× mới là chỗ nguy hiểm.

### Phát hiện lúc dựng stack thật

`MQTT_HOST=host.docker.internal` trong `.env.example` **không dùng được** trên Docker Desktop:
backend không nối được broker, nhưng `nc -z` vẫn báo cổng mở và broker không ghi nhận connection
nào. Backend im lặng retry mãi trong khi HTTP vẫn lên bình thường. Đã sửa `.env` local sang tên
container `home-mqtt` + `docker network connect`, và ghi cảnh báo vào runbook kèm mục kiểm số 0.

### Đính chính trong runbook

Bài kiểm chứng truy vấn (DB thật, 21 mẫu dựng sẵn có 3 loại lỗi) bác lý do tôi viết cho
`PARTITION BY boot`. Reset **không** sinh lỗ hổng giả — `seq` tụt về 0 cho hiệu số âm, bộ lọc
`> 1` bỏ qua im lặng. Hỏng theo chiều khó thấy hơn: dòng ranh giới bị bỏ sót. Runbook đã sửa.

## Định nghĩa hoàn thành

- [ ] Node chạy 10 phút ở 10Hz: `seq` liên tục không thủng, `boot` không đổi.
- [ ] Truy vấn phân biệt được ba nguyên nhân mất mẫu bằng `seq`/`ts`/`boot`.
- [ ] `PRAGMA journal_mode` trả `wal` sau khi `Open`.
- [ ] Trần `maxSamples` vẫn được giữ sau khi giãn câu cắt.
- [ ] Payload có `seq`+`boot` không bị `snprintf` cắt cụt ở giá trị lớn nhất.
- [ ] Toàn bộ test Go cũ vẫn xanh (`go test ./... -count=1`).
- [ ] Runbook chạy được bởi người không viết code, phủ cả hai đường ống.

## Ngoài phạm vi

Chuyển stack sang Jetson · dựng `edge/collector` · node piezo · tiêu chí 3 (LD2510B) · đường ASR · thêm counter cho đường B · chạy đêm đo thật 8 tiếng (là việc vận hành sau khi plan này xong).

## Rủi ro

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| WAL không dùng được trên filesystem của volume | thấp | `home-data` là named volume Docker (ext4), không phải NFS. Phase 02 kiểm bằng `PRAGMA journal_mode` |
| Nới `SAMPLE_RB_LEN` làm tăng RAM tĩnh | thấp | 64×288 = 18,4KB trên ESP32-S2 (320KB SRAM) |
| Migration `ALTER TABLE` chạy lại trên DB đã có cột | trung bình | Kiểm `PRAGMA table_info(samples)` trước khi ALTER, không nuốt lỗi mù |
| Đổi `Store` sang có field làm hỏng call site | thấp | `Open` giữ nguyên chữ ký, đặt mặc định bên trong |

## Validation Log

### Verification Results — 2026-08-20, tier Full (6 phases)

| Claim | Kết quả | Bằng chứng |
|---|---|---|
| modernc.org/sqlite nhận `_pragma=` trên DSN | VERIFIED | v1.54.0 (`go.mod:9`); `driver.go` tài liệu hoá, `all_test.go` dùng `_pragma=journal_mode(WAL)` |
| `nvs_flash_init()` đã có trong `app_main` | VERIFIED | `firmware/radar-node/src/main.c:339` |
| Payload xấu nhất hiện tại 222B → 257B | **FAILED** | Tính lại: **224B → 259B**, cộng NUL là 260. Kết luận tràn `SAMPLE_RB_LEN` 256 **vẫn đúng**. Đã sửa plan + phase 03, 06 |
| `subscriber.py:107` là chỗ kiểm pair | **FAILED** | Đúng là `:108`. Đã sửa phase 05 |
| `AppendSample` chạy DELETE mỗi insert | VERIFIED | `internal/store/store.go:206-209` |
| Consumer `home/room/sample` là backend Go | VERIFIED | `internal/mqttclient/client.go:71` |
| FastAPI chỉ subscribe `sleeppad/+/...` | VERIFIED | `cloud/sleeppad/app/mqtt/subscriber.py:54-57` |
| `moving_energy`/`still_energy` là `uint8` | VERIFIED | `firmware/radar-node/src/ld2410.h:38-39` (trần 100) — đã dùng khi tính lại payload |

Claims checked: 8 · Verified: 6 · Failed: 2 (đã sửa) · Unverified: 0

### Phiên phỏng vấn 1 — 2026-08-20

| # | Câu hỏi | Quyết định | Hệ quả |
|---|---|---|---|
| 1 | `synchronous` FULL → NORMAL? | **Chấp nhận NORMAL** | Phase 02 giữ nguyên thiết kế. Cúp điện đột ngột mất transaction chưa checkpoint — ghi vào runbook Phase 05 mục "điều làm đêm đo mất giá trị" (đã có) |
| 2 | Đêm đầu có tính vào 3 đêm tiêu chí 5? | **Không — đêm đầu chỉ soát thiết bị** | Tổng **4 đêm**. Phase 05 runbook phải tách rõ "đêm soát" và "đêm tính điểm" |
| 3 | `seed-csv` giả lập `seq`? | **Không, ghi NULL** | Phase 01 giữ nguyên. Truy vấn phân tích lỗ hổng `seq` chỉ nghiệm thu bằng dữ liệu bench thật ở Phase 06 |

Không còn câu hỏi tồn đọng.
