# Gộp repo về smartbedv3 + soát cổng Phase 01 — 19/08/2026

**Trạng thái:** hạ tầng code đã gộp xong và verify. **Phase 01 CHƯA đạt cổng nghiệm thu** — 6/6 tiêu chí chưa tick, một tiêu chí không còn khả thi với phần cứng hiện tại.

---

## 1. Việc đã hoàn thành hôm nay

### Gộp ba repo về một

`esp32-presence-ac` và `sleep_pad_AI` đã nhập vào `smartbedv3` bằng `git subtree` (giữ nguyên lịch sử và quyền tác giả: 214 commit, 9 tác giả, trong đó Michael Phan 65 commit), rồi rải file theo bố cục tier:

```
firmware/  camera-node esp32cam-stream radar-node voice-node
           sleep-pad-node sleep-pad-node-idf sleeppad-esphome.yaml
cloud/     presence-ac(Go :8080) sleeppad(FastAPI :8000) asr mqtt landing
app/       smartbed presence-ac sleep-pad
mech/      + presence-ac-enclosure   docs/ + presence-ac/ sleep-pad/
plans/     + sleep-pad/              scripts/ + presence-ac/
```

Repo đã lên GitHub: `khanhhung149/smartbedv3` (private), có tag quay lui `pre-monorepo-merge` và `pre-tier-layout`.

### Backend gộp còn một

Backend Go (`cloud/presence-ac`, `:8080`, prefix `/api`) là thứ app gọi. Luật dựng phiên port từ `rules.py` sang Go kèm 14 test đối chiếu; số liệu khớp 100% bản FastAPI.

FastAPI (`cloud/sleeppad`, `:8000`) **không phải legacy** — nó sở hữu toàn bộ đường ingest MQTT, mọi hàng vào `sec_data`/`min_data` đi qua nó. Go chỉ ghi bảng dẫn xuất `sleep_sessions`.

### App Flutter

Hai tab qua `StatefulShellRoute`: Giấc ngủ + Radar/AC. Cache sqflite cho luồng ngoại tuyến.

### Kiểm chứng (clone sạch từ GitHub, build từ số không)

| Hạng mục | Kết quả |
|---|---|
| `git ls-files` cây làm việc vs clone sạch | trùng khớp hoàn toàn |
| Go `vet` + `test -count=1` | 6/6 package ok |
| Flutter `smartbed` analyze + test | No issues · 25 pass / 2 skip |
| Flutter `presence-ac`, `sleep-pad` analyze | No issues |
| Python sleep-pad: pytest + `compileall` | 17 passed · sạch |
| Live E2E `:8080/api` | 480 point, `hr_avg=62.1875` |
| `check-doc-links.sh` | tất cả link phân giải được |

---

## 2. Sự cố đã xử lý

### Mất 5 file nguồn của tầng data (đã dựng lại)

`.gitignore` có luật `data/` không neo — nhắm vào bản ghi đêm sinh trắc học nhưng khớp mọi thư mục tên `data` ở mọi độ sâu, nuốt luôn `app/lib/data/`. Hệ quả: tầng data của app **chưa bao giờ được git track**, kể cả trong bản đã push lên remote — clone mới không build được, lỗi tồn tại từ commit đầu.

Lúc dọn thư mục dở trong quá trình dời, 5 file bị xoá và `git reset --hard` không cứu được. Đã dựng lại từ test + hợp đồng API; 25/25 test xanh, live test in ra `events=[Cử động, Ngủ]` khớp từng chữ với output trước khi mất. Luật ignore neo lại thành `/edge/data/`.

**Rủi ro còn lại:** bản dựng lại đúng ở mọi hành vi có test. Chi tiết nào không được test và không lộ ra qua UI thì không kiểm chứng được.

### Va chạm cổng 1883

`.env.dev` đã ghi `MQTT_DOMAIN=tcp://localhost:1884` trong khi compose bind 1883 — hai giá trị lệch nhau từ trước, độc lập với va chạm `home-mqtt`. Nghĩa là ESP32 sleep-pad trên LAN vốn đã không kết nối được. Đã thêm `MQTT_HOST_PORT`/`MQTT_WS_HOST_PORT` và set 1884/9002 cho khớp.

### Che mật khẩu trong log

`cmd/server/main.go` in nguyên DSN. Thêm `Config.RedactedPostgresURL()` dùng `net/url` `Redacted()`, kèm 5 test (đã verify test đỏ khi bỏ fix).

---

## 3. Phase 01 — soát cổng nghiệm thu

Đối chiếu `plans/260713-1019-smartbed-v3-mvp/phase-01-cum-cam-bien-va-data-pipeline.md` mục "Định nghĩa hoàn thành":

| # | Tiêu chí | Trạng thái | Bằng chứng |
|---|---|---|---|
| 1 | Ghi liên tục 8 tiếng, mất dưới 0.1% mẫu | **chưa** | `docs/sensor-characterization.md`: node "chỉ từng chạy vài phút mỗi lần" |
| 2 | Nhịp thở radar khớp đếm mắt (±2 brpm), ngửa và nghiêng | **chưa** | chưa có bài đo nào ghi lại |
| 3 | LD2510B track 2 người, ra vị trí từng người | **không còn khả thi** | phần cứng đổi sang LD2410C (quyết định 19/08). LD2410C không có kênh này |
| 4 | Piezo pad phân biệt trên giường / rời giường / trống | **chưa** | chưa có node piezo; chưa đặc tả |
| 5 | 3 đêm dữ liệu thật trong DB, xem lại trên dashboard | **chưa** | DB có 4 phiên nhưng đều `started_at = 2026-08-18 15:00:00+00` trên 3 device khác nhau → dữ liệu seed, không phải đêm thật |
| 6 | `docs/sensor-characterization.md` ghi giới hạn từng cảm biến | **một phần** | 138 dòng, mới đặc tả ESP32-CAM + hợp đồng thu dữ liệu. Chính file ghi: "Not characterized yet: LD2510B radar, piezoelectric pad, SHT10/31, omnidirectional mic, CO₂ sensor" |

### Tình trạng các node firmware

| Node | File nguồn | Ghi chú |
|---|---|---|
| `esp32cam-stream` | 6 | có code, bench-test |
| `radar-node` | 4 | LD2410C, ESP-IDF |
| `voice-node` | 23 | |
| `sleep-pad-node` / `-idf` | 6 / 8 | từ repo sleep-pad |
| `camera-node` | **0** | README ghi "Not started, confirm scope before implementing" |
| `sensor-node` | **không tồn tại** | có trong bảng `firmware/README.md` nhưng chưa có thư mục |
| `mech-handler` | **không tồn tại** | Phase 04 |

`edge/` vẫn chỉ có `README.md` + 1 file CSV — chưa có `collector/`, `dashboard/`, `sleep/`, `vision/` như README mô tả.

---

## 4. Đề xuất

Không chốt Phase 01 ở thời điểm này. Hai đường đi:

**A. Làm nốt cho đủ cổng.** Việc còn lại tập trung ở phần cứng và đo đạc, không phải phần mềm: dựng cụm piezo, chạy 3 đêm thật, viết bài đo nhịp thở đối chiếu, bổ sung đặc tả 5 cảm biến còn lại.

**B. Thu hẹp phạm vi Phase 01 rồi chốt.** Tiêu chí 3 (track 2 người) không thể đạt với LD2410C — cần hoặc mua LD2510B, hoặc chính thức bỏ tiêu chí này khỏi Phase 01 và ghi rõ hệ quả xuống Phase 02. Không sửa plan mà vẫn chốt là để lại một tiêu chí vĩnh viễn treo.

Phase 02 (thuật toán giấc ngủ + apnea) phụ thuộc dữ liệu thật từ tiêu chí 5. Bắt đầu Phase 02 trên dữ liệu seed sẽ cho ra thuật toán hiệu chỉnh theo số liệu bịa.

---

## Câu hỏi chưa giải quyết

1. Tiêu chí 3 (LD2510B track 2 người): mua LD2510B hay bỏ tiêu chí khỏi Phase 01? Đây là quyết định phần cứng + phạm vi, không phải quyết định kỹ thuật.
2. `sleep_pad_AI` là repo của tổ chức `Sleep-Tech-AI` (7 người đóng góp). Sau khi rải file theo tier, `git subtree push` không dùng được nữa — đường về team chỉ còn clone gốc `/mnt/d/sleep_pad_AI`. Cần thống nhất repo nào là nguồn sự thật.
3. `firmware/sleeppad-esphome.yaml` (commit của Michael 21/04) chứa mật khẩu OTA + AP dự phòng dạng plaintext. Mật khẩu OTA lộ nghĩa là ai trong LAN cũng flash được firmware lên thiết bị. Cần nêu với team.
4. `.claude/skills/.env` chưa có ở repo này (repo `esp32-presence-ac` có). Skill cần API key sẽ không chạy tới khi chép sang.
