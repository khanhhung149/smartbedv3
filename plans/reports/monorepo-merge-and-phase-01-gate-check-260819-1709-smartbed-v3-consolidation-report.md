# Báo cáo tiến độ — gộp repo về một + soát cổng Phase 01

- **Người gửi:** Hưng · **Người nhận:** Michael
- **Loại:** báo cáo tiến độ (theo kỳ vọng "chủ động báo cáo hằng ngày" chốt 13/07)
- **Ngày lập:** 2026-08-19
- **Phạm vi:** hợp nhất `esp32-presence-ac` và `sleep_pad_AI` vào `smartbedv3`, rải theo bố cục tier, đối chiếu hiện trạng với cổng nghiệm thu Phase 01
- **Plan gốc:** [`plans/260713-1019-smartbed-v3-mvp/plan.md`](../260713-1019-smartbed-v3-mvp/plan.md)
- **Phase liên quan:** [01 — Cụm cảm biến + data pipeline](../260713-1019-smartbed-v3-mvp/phase-01-cum-cam-bien-va-data-pipeline.md)
- **Repo:** `github.com/khanhhung149/smartbedv3` (private) · mốc quay lui `pre-monorepo-merge`, `pre-tier-layout`
- **Kết luận:** hạ tầng code đã gộp xong và verify. **Phase 01 chưa đạt cổng** — 6/6 tiêu chí chưa tick, 1 tiêu chí không còn khả thi với phần cứng hiện tại.

---

## Hợp nhất repo — CHỐT 19/08

Ba repo rời thành một. Lý do: một thay đổi trước đây phải sửa ở 3 chỗ, và app trỏ sang backend nằm ngoài repo nên không ai đọc code mà biết được đường đi của dữ liệu.

Dùng `git subtree` nên **giữ nguyên lịch sử và quyền tác giả**: 214 commit, 9 tác giả, trong đó Michael Phan 65 commit, patricknguyen 41, MinhLQ 10.

### Bố cục sau khi rải theo tier

| Thư mục | Chạy trên | Nội dung |
|---|---|---|
| `firmware/` | ESP32 | `camera-node` `esp32cam-stream` `radar-node` `voice-node` `sleep-pad-node{,-idf}` `sleeppad-esphome.yaml` |
| `edge/` | Jetson Orin | mới có README + 1 CSV — chưa có `collector/`, `dashboard/` |
| `cloud/` | máy chủ / K8s | `presence-ac` (Go `:8080`) · `sleeppad` (FastAPI `:8000`) · `asr` · `mqtt` · `landing` |
| `app/` | Flutter | `smartbed` · `presence-ac` · `sleep-pad` |
| `mech/` | — | CAD khung 3 mảng + `presence-ac-enclosure` |
| `docs/` `plans/` `scripts/` | — | kèm thư mục con `presence-ac/`, `sleep-pad/` của từng dự án |

### Đường đi của dữ liệu sau hợp nhất

| Tầng | Ai làm | Ghi chú |
|---|---|---|
| Ingest MQTT → Postgres | `cloud/sleeppad` (FastAPI) | **Không phải legacy.** Mọi hàng vào `sec_data`/`min_data` đi qua đây |
| Dựng phiên + API đọc | `cloud/presence-ac` (Go) | Chỉ ghi bảng dẫn xuất `sleep_sessions`, đọc phần còn lại |
| Client | `app/smartbed` | Gọi `:8080` prefix `/api`, cache sqflite cho luồng ngoại tuyến |

Luật dựng phiên port từ `rules.py` sang Go kèm 14 test đối chiếu; số liệu khớp 100% bản FastAPI.

### Đánh đổi đã chấp nhận

| Hạng mục | Trước | Sau hợp nhất |
|---|---|---|
| Số repo phải sửa cho 1 thay đổi | 3 | 1 |
| Lịch sử git | 3 cây rời | 1 cây, 214 commit, đủ 9 tác giả |
| `git subtree push` về `Sleep-Tech-AI` | dùng được | **mất** — không prefix nào chứa trọn cây repo nguồn nữa |
| Đường đồng bộ với team | trực tiếp | chỉ còn clone gốc `/mnt/d/sleep_pad_AI` |

---

## Kiểm chứng — clone sạch từ GitHub, build từ số không

| Hạng mục | Kết quả |
|---|---|
| `git ls-files` cây làm việc vs clone sạch | trùng khớp hoàn toàn |
| Go `vet` + `test -count=1` | 6/6 package ok |
| Flutter `smartbed` — analyze + test | No issues · 25 pass / 2 skip |
| Flutter `presence-ac`, `sleep-pad` — analyze | No issues |
| Python `sleeppad` — pytest + `compileall` | 17 passed · sạch |
| Live E2E `:8080/api` | 480 point, `hr_avg=62.1875` |
| `scripts/check-doc-links.sh` | tất cả link phân giải được |

---

## Sự cố trong quá trình làm

| Sự cố | Nguyên nhân | Xử lý |
|---|---|---|
| Mất 5 file nguồn tầng data của app | `.gitignore` có luật `data/` **không neo** → khớp mọi thư mục tên `data` ở mọi độ sâu, nuốt `app/lib/data/`. Tầng data **chưa bao giờ được git track**, kể cả bản đã push | Dựng lại từ test + hợp đồng API. 25/25 test xanh. Luật neo lại thành `/edge/data/` |
| `/api/sessions` trả 503 | Stack sleep-pad bị hạ, backend Go ping Postgres 1 lần lúc start rồi tắt hẳn endpoint | Dựng lại stack + restart backend |
| Cổng 1883 va chạm | `.env.dev` ghi `MQTT_DOMAIN=…:1884` trong khi compose bind 1883 — lệch nhau từ trước, ESP32 sleep-pad vốn đã không kết nối được | Thêm `MQTT_HOST_PORT`/`MQTT_WS_HOST_PORT`, set 1884/9002 |
| DSN lộ trong log container | `main.go` in nguyên `POSTGRES_URL` | `Config.RedactedPostgresURL()` dùng `net/url` `Redacted()`, kèm 5 test |
| Thư mục ma trên WSL | `git mv` thư mục đang bị Docker bind-mount làm hỏng entry DrvFs | Dừng container trước khi dời; xoá entry hỏng bằng `cmd.exe /c rd` |

**Rủi ro còn lại của phần dựng lại:** đúng ở mọi hành vi có test (`isStale`, round-trip khoá lạ qua cache, phân biệt `null` với `0`, token hết hạn phải ném). Chi tiết nào không được test và không lộ qua UI thì không kiểm chứng được — bản gốc không còn để đối chiếu.

---

## Soát cổng Phase 01

Đối chiếu mục "Định nghĩa hoàn thành" trong [`phase-01`](../260713-1019-smartbed-v3-mvp/phase-01-cum-cam-bien-va-data-pipeline.md):

| # | Tiêu chí | Trạng thái | Bằng chứng |
|---|---|---|---|
| 1 | Ghi liên tục 8 tiếng, mất dưới 0.1% mẫu | ❌ chưa — **chạy được ngay**, xem mục dưới | `docs/sensor-characterization.md`: node "chỉ từng chạy vài phút mỗi lần" |
| 2 | Nhịp thở radar khớp đếm mắt (±2 brpm), ngửa và nghiêng | ❌ chưa | chưa có bài đo nào được ghi lại |
| 3 | LD2510B track 2 người, ra vị trí từng người | ⛔ **không còn khả thi** | phần cứng đổi sang LD2410C (quyết định 19/08). Chip này không có kênh đó |
| 4 | Piezo pad phân biệt trên giường / rời giường / trống | ❌ chưa | chưa có node piezo, chưa đặc tả |
| 5 | 3 đêm dữ liệu thật trong DB, xem lại trên dashboard | ❌ chưa | 4 phiên trong DB đều `started_at = 2026-08-18 15:00:00+00` trên 3 device khác nhau → dữ liệu seed |
| 6 | `docs/sensor-characterization.md` ghi giới hạn từng cảm biến | ◐ một phần | 138 dòng, mới đặc tả ESP32-CAM + hợp đồng thu dữ liệu. Chính file ghi: *"Not characterized yet: LD2510B radar, piezoelectric pad, SHT10/31, omnidirectional mic, CO₂ sensor"* |

### Tình trạng node firmware, theo phase sở hữu

| Node | Phase sở hữu | File nguồn | Ghi chú |
|---|---|---|---|
| `esp32cam-stream` | 01 (amendment) | 6 | Thay cụm "Camera nhiệt" của Phase 01. Bench-test, không ghi đĩa |
| `radar-node` | 01 (cụm presence) | 4 | LD2410C, ESP-IDF |
| `sensor-node` | **01** | — | **Thư mục chưa tồn tại.** Có trong bảng `firmware/README.md` với Phase 01 |
| `voice-node` | ngoài phạm vi Phase 01 | 23 | Từ dự án presence-ac |
| `sleep-pad-node{,-idf}` | ngoài phạm vi Phase 01 | 6 / 8 | Từ dự án sleep-pad |
| `camera-node` | **05** | 0 | Giữ chỗ cho Phase 05, README ghi rõ "Not started, confirm scope". **Không phải thiếu sót của Phase 01** |
| `mech-handler` | 04 | — | Thư mục chưa tồn tại, đúng tiến độ |

---

## Sẵn sàng chạy bài đo 8 tiếng (tiêu chí 1) — đề nghị làm ngay

Toàn bộ đường dữ liệu đã thông từ đầu tới cuối, nên bài đo 8 tiếng **chạy được ngay đêm nay**, không còn chờ phần mềm.

| Mắt xích | Trạng thái |
|---|---|
| Vòng lấy mẫu 10Hz cố định tại MCU | ✅ `SAMPLE_TICK_MS 100` trong `firmware/radar-node/src/main.c`, timestamp gắn tại MCU |
| Đẩy mẫu qua MQTT | ✅ topic `home/room/sample`, broker chạy |
| Ingest → Postgres/TimescaleDB | ✅ FastAPI, đã chạy thật |
| Dựng phiên tự động | ✅ goroutine Go, chu kỳ 60s |
| Dọn dữ liệu cũ | ✅ `RetainNights` giữ 30 đêm gần nhất, có trần chống phình DB |
| Xem lại | ✅ dashboard local + app Flutter, cả hai đã verify |

**Số mẫu kỳ vọng:** 8 tiếng × 10Hz = **288.000 mẫu**. Ngưỡng đạt là mất dưới 0,1% → không quá **288 mẫu**.

### Một hạn chế cần Michael biết trước khi tin con số

Firmware **chưa có số thứ tự mẫu** (sequence counter). Tỷ lệ mất vẫn tính được bằng *số mẫu thực nhận / 288.000*, nhưng cách này **không phân biệt được** hai nguyên nhân:

- MCU không lấy được mẫu (vòng lặp trượt nhịp, sensor không trả dữ liệu)
- Mẫu có lấy nhưng rơi trên đường (WiFi, MQTT, ingest)

Hai nguyên nhân này cần hai cách sửa khác hẳn nhau. Thêm một biến đếm tăng dần vào payload là việc nhỏ (dưới nửa ngày) và nên làm **trước** đêm đo đầu tiên, nếu không đêm đó cho ra một con số không truy được nguyên nhân.

### Việc còn lại không thuộc phần mềm

- Lắp cụm cảm biến lên bench rig, cấp **nguồn riêng cho mạch** (không lấy từ laptop — quy tắc Michael dặn 13/07)
- Có người nằm thật; tiêu chí 5 cần **3 đêm**, nên chạy 3 đêm liên tiếp thay vì 1

---

## Đề xuất

Không chốt Phase 01 ở thời điểm này. Hai đường:

| Hướng | Nội dung | Đổi lại |
|---|---|---|
| **A. Làm nốt cho đủ cổng** | Dựng cụm piezo và `sensor-node`, chạy 3 đêm thật, viết bài đo nhịp thở đối chiếu, đặc tả 5 cảm biến còn lại | Việc còn lại nằm ở phần cứng và đo đạc, không phải phần mềm |
| **B. Thu hẹp phạm vi rồi chốt** | Bỏ tiêu chí 3 khỏi Phase 01, ghi hệ quả xuống Phase 02 | Phải sửa plan. Không sửa mà vẫn chốt là để lại một tiêu chí treo vĩnh viễn |

Tiêu chí 3 buộc phải xử lý bằng một trong hai cách: mua LD2510B, hoặc chính thức bỏ khỏi Phase 01.

**Phase 02 phụ thuộc tiêu chí 5.** Thuật toán giấc ngủ/apnea hiệu chỉnh trên dữ liệu seed sẽ cho ra ngưỡng khớp với số bịa, và sai lệch chỉ lộ ra khi đo người thật.

---

## Câu hỏi tồn đọng

1. **Tiêu chí 3 (LD2510B track 2 người):** mua LD2510B hay bỏ khỏi Phase 01? Quyết định phần cứng + phạm vi, không phải quyết định kỹ thuật.
2. **Nguồn sự thật của `sleep-pad`:** repo tổ chức `Sleep-Tech-AI` có 7 người đóng góp. Sau khi rải theo tier, `git subtree push` không dùng được — đường về team chỉ còn clone gốc. Cần thống nhất với Michael repo nào là chuẩn.
3. **`firmware/sleeppad-esphome.yaml`** (commit của Michael 21/04) chứa mật khẩu OTA + AP dự phòng dạng plaintext. OTA lộ nghĩa là ai trong LAN cũng flash được firmware lên thiết bị. Cần nêu với team.
4. **`sensor-node/` có còn trong phạm vi Phase 01 không**, hay chức năng của nó đã được `radar-node` + node sleep-pad gánh? `firmware/README.md` vẫn liệt kê nó nhưng thư mục chưa tồn tại.
5. **`.claude/skills/.env`** chưa có ở repo này (repo `esp32-presence-ac` có, chứa `GEMINI_API_KEY`). Skill cần key sẽ không chạy tới khi chép sang.
