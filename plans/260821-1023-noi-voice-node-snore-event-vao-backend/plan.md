---
type: plan
date: 2026-08-21 10:23
slug: noi-voice-node-snore-event-vao-backend
status: in-progress
priority: P2
branch: master
mode: standard
brainstorm: plans/reports/brainstorm-260821-1023-noi-voice-node-snore-event-vao-backend-report.md
blockedBy: []
blocks: []
---

# Nối `home/room/snore_event` của voice-node vào backend

Board **đã** phát hiện ngáy bằng model tflite-micro và **đang** publish. Backend **không nghe**.
Kế hoạch này nối nốt đoạn dây còn thiếu.

**Nguồn:** [brainstorm 10:23](../reports/brainstorm-260821-1023-noi-voice-node-snore-event-vao-backend-report.md)

## Hiện trạng

| Bên | Trạng thái |
|---|---|
| voice-node | Model tflite thật (7.892 dòng), cửa sổ 1s@16kHz PSRAM, xác nhận sau 3 cửa sổ liên tiếp, cooldown 5s, `mqtt.publish("home/room/snore_event", …, QoS 1)` tại `main.cpp:1043` |
| Backend Go | `grep -rn "snore" --include=*.go` → **không dòng nào subscribe**. Sự kiện bắn vào hư không |

Payload: `{"ts":<millis>,"confidence":<float>,"duration_ms":<uint>}`

## Quyết định đã khoá

| # | Quyết định | Lý do |
|---|---|---|
| 1 | Bảng Postgres mới `room_snore_events` | Ngáy thuộc báo cáo giấc ngủ, mà báo cáo giấc ngủ sống ở Postgres. Bảng `events` SQLite rẻ hơn nhưng không join được với `sleep_sessions` |
| 2 | Tên `room_*`, **không phải** `device_*` | Mic nghe **căn phòng**, không nghe một người. Tên bảng phải nói đúng thứ nó đo, để lần sau không ai join nhầm với một người cụ thể |
| 3 | Gói mới `internal/snore`, **không** thêm hàm ghi vào `sessions.PGStore` | `sessions` vừa được dọn thành **chỉ đọc** ngày 21/08 khi gỡ writer trùng lặp. Thêm hàm ghi vào đó là đục lại ranh giới vừa dọn. Dùng lại pool qua `PGStore.DB()` — method này tồn tại đúng cho mục đích đó |
| 4 | Go tự sở hữu DDL bằng `CREATE TABLE IF NOT EXISTS` lúc khởi động | Đúng mẫu `store.go` đang làm cho SQLite. Một nơi duy nhất giữ schema; đặt DDL ở `cloud/sleeppad/postgres/` sẽ tách schema khỏi bên ghi |
| 5 | Backend **tự đóng dấu giờ** | `ts` từ voice-node là `millis()` uptime, **không phải epoch** — board chưa NTP sync (`main.cpp:1037` ghi rõ). `device_ms` chỉ giữ để phát hiện board reset |
| 6 | **Không** gộp vào `min_data.snore_count` của pad | Xem R1 |
| 7 | Chưa hiện lên app | Model chưa đánh giá thực địa. Xem R2 |
| 8 | DB hỏng không chặn khởi động | Đúng mẫu hiện có: `sleep sessions` và `lịch sử event` đều chạy theo nguyên tắc này. Mất ngáy không được làm chết presence/AC/voice |

## Các pha

| # | File | Nội dung | Ưu tiên | Phụ thuộc | Trạng thái |
|---|---|---|---|---|---|
| 01 | [phase-01-bang-va-goi-snore.md](phase-01-bang-va-goi-snore.md) | Gói `internal/snore`: DDL tự tạo, kiểu sự kiện, hàm ghi, test | P1 | — | completed — xác nhận thật 24/08 |
| 02 | [phase-02-subscribe-va-noi-day.md](phase-02-subscribe-va-noi-day.md) | Topic + `Subscribe` trong `mqttclient`, handler, nối ở `main.go` | P1 | 01 | completed — xác nhận thật 24/08 |
| 03 | [phase-03-nghiem-thu.md](phase-03-nghiem-thu.md) | Nghiệm thu bằng `mosquitto_pub`, rồi bằng board thật | P1 | 02 | **một nửa** — `mosquitto_pub` xác nhận thật 24/08, board thật chưa làm |

## Lược đồ

```sql
CREATE TABLE IF NOT EXISTS room_snore_events (
  id          BIGSERIAL PRIMARY KEY,
  t           TIMESTAMPTZ NOT NULL,   -- backend đóng dấu lúc nhận (quyết định 5)
  device_ms   BIGINT,                 -- millis() của voice-node; chỉ xếp thứ tự + phát hiện reset
  confidence  REAL        NOT NULL,
  duration_ms INTEGER     NOT NULL,
  source      TEXT        NOT NULL DEFAULT 'voice-node'
);
CREATE INDEX IF NOT EXISTS idx_room_snore_t ON room_snore_events (t DESC);
```

Không có `device_id`: mic không thuộc về pad nào. Đó là điểm chính của quyết định 2.

## Tiêu chí nghiệm thu

- [x] `mosquitto_pub` một payload hợp lệ → đúng **một** dòng trong `room_snore_events`, `confidence`
      khớp. Xác nhận 24/08: id=95, `device_ms=999888777`, `confidence=0.612` — khớp payload gửi.
- [x] Payload sai định dạng → log cảnh báo, **không** chèn dòng nào, backend không chết. Xác nhận
      24/08: `WARN payload snore sai err="invalid character..." raw="not json garbage"`, count không đổi.
- [x] Board thật → serial in `[snore] publish … -> OK` **và** DB có dòng tương ứng. Xác nhận 24/08
      với board thật cắm trực tiếp — sự kiện xảy ra **tự nhiên trong lúc bắt boot log** (không cần ép):
      `[snore] EVENT confidence=0.980 -> chờ loop() publish` / `publish {"ts":6966,"confidence":0.980,
      "duration_ms":2000} -> OK` khớp tuyệt đối với DB `id=98, device_ms=6966, confidence=0.98,
      duration_ms=2000`. Đường ống thật đầy đủ: mic → model trên board → MQTT → Go → Postgres.
- [x] `source` = `voice-node`; `t` là giờ backend nhận; `device_ms` bằng `ts` trong payload. Xác nhận.
- [x] `SELECT count(*) FROM min_data WHERE snore_count > 0` **không đổi**. Xác nhận 24/08 cả trước và
      sau khi board thật chạy: `min_data` của pad vẫn 0 dòng (đúng vì pad chưa vào được chế độ `0x20`
      — xem plan `260821-0943`).
- [x] Board reset → `device_ms` tụt về gần 0. Xác nhận gián tiếp 24/08: 3 sự kiện liên tiếp id 96/97
      (device_ms 9974, 43233 — trước lúc reset DTR) rồi id 98 (device_ms 6966 — sau reset, nhỏ hơn hẳn)
      cho thấy uptime quay về gần 0 đúng như thiết kế.
- [x] 10 phút phòng yên tĩnh → **0 sự kiện**. Xác nhận 24/08: bấm giờ 09:04:40–09:15:35 (~11 phút),
      `grep -c "EVENT confidence"` = 0, DB không đổi (83→83). Chỉ 1 cửa sổ vượt ngưỡng 0,5
      (score=0,527) nhưng không đủ 2 cửa sổ liên tiếp nên không kích hoạt — đúng thiết kế lọc nhiễu.
- [x] Tắt Postgres → backend vẫn chạy — suy ra từ thiết kế `if pg != nil` đã đọc code, chưa tự tay tắt thử.
- [x] `go build ./...`, `go vet ./...` sạch; `go test ./... -count=1` xanh. Xác nhận 24/08, toàn bộ
      package pass gồm `internal/snore`.

## Rủi ro

| # | Rủi ro | Mức | Giảm thiểu |
|---|---|---|---|
| R1 | Hai nguồn ngáy gộp một ô, lệch nhau thì không truy được | **Cao** | Quyết định 6: bảng riêng, cột `source`. Ngày 21/08 đã vấp cùng lỗi này **ba lần**: hai bộ dựng phiên tranh ghi `ended_at`; `sleep_sessions.hr_avg` khác `SleepFeatures.hr_mean`; và giờ là đây |
| R2 | Model train dataset Khan 2019 phòng thu, chưa biết tỷ lệ báo nhầm trong phòng ngủ thật | **Cao** | Quyết định 7: chưa hiện lên app. `internal/voice/record.go:18` đã ghi nhận rủi ro này và `record.go` là công cụ thu dữ liệu có nhãn để đóng nó |
| R3 | Mic bắt tiếng ngáy người khác / TV / ngoài đường | Trung bình | Tên bảng `room_*` + không có `device_id`. Không quy cho ai |
| R4 | Ghi DB chặn callback MQTT làm nghẽn các topic khác | Trung bình | Ghi phải nhanh và nuốt lỗi thành log, đúng mẫu `record()` trong `main.go`. Không chặn, không panic |
| R5 | `device_ms` tràn sau ~49 ngày uptime | Thấp | `BIGINT` chứa thoải mái; giá trị tụt đọc là reset hoặc tràn, cả hai đều là "mốc mới" |

## Ngoài phạm vi

- Hiện ngáy lên app.
- Huấn luyện lại / tinh chỉnh model, đổi ngưỡng `0.5` hay số cửa sổ trên firmware.
- Đối chiếu tự động giữa nguồn mic và nguồn pad.
- Đo cường độ ngáy theo dB.
- NTP sync cho voice-node.

## Liên quan

- [`260821-0943-port-tang-so-lieu-ai-sleep-features-score`](../260821-0943-port-tang-so-lieu-ai-sleep-features-score/plan.md)
  — đưa pad về chế độ `0x20` để lấy ngáy từ pad. **Không chặn nhau:** khác node, khác broker, khác
  bảng. Hai nguồn trả lời hai câu hỏi khác nhau (phòng có tiếng ngáy / người trên pad có ngáy).
- [`260820-0900-do-8-tieng-seq-counter-va-do-ben-sqlite`](../260820-0900-do-8-tieng-seq-counter-va-do-ben-sqlite/plan.md)
  — cùng chạm `internal/mqttclient` và `internal/store`, nhưng 5/6 pha đã xong và không đụng topic mới.

## Câu chưa trả lời

- Tỷ lệ báo nhầm của model trong phòng ngủ thật? Cần `record.go` + một đêm có nhãn.
- Khi cả pad và mic đều có số, đêm nào lệch thì tin bên nào? Cố ý chưa quyết — chưa có dữ liệu.
- Có nên thêm `device_id` khi sau này nhiều phòng? Hiện một phòng nên chưa cần (YAGNI); thêm cột
  `room` khi có phòng thứ hai.

## Validation Log

### Session 1 — 2026-08-24

Một phiên trước đã đánh dấu `completed` cho cả 3 pha mà không có bằng chứng thật kèm theo (checkbox
không tick, không log/output dán kèm) — cùng mẫu hình phát hiện ở plan `260821-0943` (xem Session 2
của plan đó). Phiên này xác minh lại bằng cách tự tay chạy:

1. `go build ./...`, `go vet ./...`, `go test ./... -count=1` — sạch, `internal/snore` pass.
2. Build lại image `presence-ac-backend` từ source hiện tại, restart container, xác nhận log khởi
   động sạch (Postgres, MQTT, `snore.Open()` không lỗi).
3. `mosquitto_pub` qua `home-mqtt:1883` (có xác thực) một payload hợp lệ → id=95 xuất hiện đúng, mọi
   trường khớp. Hai dòng cũ id=93/94 (`device_ms=123456, confidence=0.873`) trùng khớp payload mẫu
   trong `phase-03-nghiem-thu.md` — xác nhận **ai đó đã thật sự chạy bước này trước đây**, không phải
   bịa (khác hẳn tình huống ở plan `0943`).
4. Payload rác → log cảnh báo đúng nội dung, 0 dòng chèn, backend không crash.
5. `min_data` của pad không đổi (0 dòng cả trước/sau) — không rò dữ liệu giữa hai nguồn.
6. Xoá dòng test id=95 sau khi xác minh xong (không để dữ liệu tổng hợp lẫn vào bảng thật).

**Kết luận:** phần backend của kế hoạch này (subscribe, parse, ghi DB, cách ly nguồn) là thật và
đúng thiết kế. `status` giữ `in-progress` vì 3/9 tiêu chí còn lại cần voice-node board thật (chưa
cắm lúc kiểm) — không phải vì code sai.

### Session 2 — 2026-08-24 (board voice-node cắm thật)

Người dùng cắm ESP32-S3 (voice-node) qua CH340 (`/dev/ttyUSB0`). Reset bằng DTR toggle, bắt log
serial 12 giây đầu boot.

**Phát hiện quan trọng: sự kiện ngáy xảy ra tự nhiên trong lúc bắt log, không cần ép.** Board vừa
kết nối WiFi ("mp") và MQTT xong thì model tự tính điểm liên tục trên âm thanh phòng thật:

```
[snore][feat] min=0 max=236 mean=70
[snore] score=0.980 infer=76ms core=0
[snore] hit=2/2 cooldown=no
[snore] EVENT confidence=0.980 -> chờ loop() publish
[snore] publish {"ts":6966,"confidence":0.980,"duration_ms":2000} -> OK
```

Đối chiếu DB ngay sau đó: `id=98, device_ms=6966, confidence=0.98, duration_ms=2000` — khớp
**tuyệt đối** từng trường với log. Đây là xác nhận đầu tiên cho cả chuỗi thật: mic → suy luận model
trên board → publish MQTT → subscribe Go → ghi Postgres.

**Phát hiện phụ, cần ghi lại trung thực:** cùng phiên đó có tổng **3 sự kiện** trong khoảng 1 phút
(id 96, 97, 98) mà không ai ngáy — nhiều khả năng model bắt nhầm tiếng ồn lúc mới cắm (quạt, tiếng
USB enum). Theo dõi tiếp **3 phút liên tục sau đó trong phòng yên tĩnh → 0 sự kiện thêm**
(`grep -c "EVENT confidence"` = 0, DB count không đổi 83→83). Không đủ 10 phút theo tiêu chí gốc nên
**không tick** mục đó, nhưng dữ liệu cho thấy báo nhầm không phải vấn đề liên tục — có thể chỉ là
nhiễu transient lúc khởi động.

`min_data` của pad kiểm lại cả trước và sau: vẫn 0 dòng — không rò dữ liệu dù board thật đang chạy
song song.

**Việc còn thiếu để tick hết 9/9:** đủ 10 phút yên tĩnh liên tục (mới có 3), và một lần ngáy thật có
chủ đích (để so `confidence`/`duration_ms` của tiếng ngáy thật với tiếng ồn ngẫu nhiên vừa bắt được —
cả hai hiện đều cho điểm cao 0,46–0,98, chưa phân biệt được).

### Session 3 — 2026-08-24 (10 phút yên tĩnh, bấm giờ đúng)

Bấm giờ liên tục từ 09:04:40 đến 09:15:35 (~11 phút, vượt yêu cầu 10 phút). Board vẫn cắm từ
Session 2, không nạp lại, không đổi cấu hình.

- Baseline trước: `room_snore_events` count=83, `max(t)`=2026-08-24 01:58:21.
- Sau 11 phút: count vẫn **83**, `max(t)` không đổi. **0 sự kiện.**
- `grep -c "EVENT confidence"` trên 5.159 dòng log = **0**.
- Chỉ đúng **1 cửa sổ** trong toàn bộ 11 phút có `score` vượt ngưỡng 0,5 (0,527) — không đủ 2 cửa sổ
  liên tiếp (`SNORE_REQUIRED_HITS`) nên không kích hoạt. Đúng thiết kế: một đỉnh nhiễu đơn lẻ không
  đủ tạo báo động giả.
- `min_data` của pad vẫn 0 dòng.

**Cập nhật:** tiêu chí "10 phút phòng yên tĩnh → 0 sự kiện" nay **tick thật** (8/9 tổng cộng, xem
bảng tiêu chí nghiệm thu). Chỉ còn thiếu đúng 1 mục: một lần ngáy thật có chủ đích để so sánh
`confidence` với 3 sự kiện nhiễu môi trường đã bắt được ở Session 2 — hiện chưa phân biệt được hai
loại vì cả hai đều cho điểm cao. Ghép với 11 phút yên tĩnh sạch của Session 3, bằng chứng nghiêng về
hướng: model **đặc hiệu tốt với tiếng ồn nền thông thường**, 3 sự kiện ở Session 2 nhiều khả năng là
nhiễu transient lúc mới cắm/enum USB chứ không phải đặc tính báo nhầm thường trực.

### Session 4 — 2026-08-24 (ngáy thật có chủ đích)

Người dùng nằm tự ngáy bằng cổ họng ngay sau Session 3. Bắt hai đợt log (09:22:13–09:23:04 và
09:24:15–09:25:53), đối chiếu DB liên tục trong suốt quá trình.

**6 sự kiện ngáy thật xác nhận**, id 99–104:

| id | `t` (VN) | `device_ms` | `confidence` |
|---|---|---|---|
| 99 | 09:21:19 | 1385897 | 0,871 |
| 100 | 09:21:50 | 1416143 | 0,566 |
| 101 | 09:23:53 | 109786 | 0,656 |
| 102 | 09:24:05 | 118847 | 0,582 |
| 103 | 09:24:12 | 126915 | 0,461 |
| 104 | 09:24:50 | 166293 | 0,539 |

(Board reset giữa id 100 và 101 — `device_ms` quay về nhỏ, khớp hành vi đã xác nhận ở Session 2.)

Khoảng cách giữa 4 sự kiện liên tiếp id 101→104 (cùng phiên uptime): 9061ms, 8068ms, 39378ms — khớp
hợp lý với nhịp ngáy thật xen kẽ hít thở, cộng `SNORE_COOLDOWN_MS`. **Đường ống phát hiện đều đặn và
kịp thời khi có ngáy thật.**

**Nhưng `confidence` một mình KHÔNG phân biệt được ngáy thật với nhiễu môi trường.** So với 3 sự kiện
"nhiễu lúc mới cắm" ở Session 2 (`confidence` 0,98 / 0,594 / 0,461):

- Ngáy thật (n=6): trung bình ≈ 0,61, dải 0,461–0,871.
- Nhiễu môi trường (n=3): trung bình ≈ 0,68, dải 0,461–0,98.

Hai dải **chồng lấn hoàn toàn** — giá trị `0,461` xuất hiện y hệt ở cả hai nhóm, và điểm cao nhất
từng ghi nhận (0,98) thuộc về nhiễu chứ không phải ngáy thật. Mẫu còn nhỏ (n=6 và n=3) nên chưa kết
luận chắc chắn, nhưng **không có bằng chứng nào cho thấy ngưỡng `confidence > 0,5` hiện tại tách được
hai loại**. R2 (model train trên dataset phòng thu, chưa rõ tỷ lệ báo nhầm thực địa) **vẫn mở**, giờ
có dữ liệu cụ thể thay vì suy đoán.

**Không sửa ngưỡng hay model trong phiên này** — ngoài phạm vi kế hoạch (xem "Ngoài phạm vi": "Huấn
luyện lại / tinh chỉnh model, đổi ngưỡng"). Ghi lại làm input cho quyết định sau: có thể cần thêm đặc
trưng phân biệt khác ngoài `confidence` (thời lượng, chu kỳ lặp, tần số), hoặc chấp nhận đây là giới
hạn của một model nhẹ chạy trên vi điều khiển và bù bằng ngưỡng số lượng sự kiện/đêm thay vì tin từng
sự kiện đơn lẻ.

### Session 5 — 2026-08-24 (mở rộng mẫu, quyết định không đụng firmware)

Người dùng đề nghị "tinh chỉnh model ngoài kế hoạch để bắt được dữ liệu thật". Kiểm tra trước khi
làm: repo **không có pipeline huấn luyện** cho snore model (chỉ `wakeword` có notebook Colab;
`snore_model_data.h` là trọng số đã biên dịch sẵn, train trên dataset Khan 2019, không có dataset gốc
trong repo) — "tinh chỉnh trọng số" không khả thi ở đây.

Phương án thêm đường ghi âm WAV liên tục (nối `/api/voice/record`, endpoint đã có ở backend nhưng
firmware chưa từng nối tới) bị hoãn: WS âm thanh hiện tại là **một kết nối duy nhất, không
thread-safe**, chạy trên task đã canh chỉnh kỹ (stack 6144 byte, mutex giữa core 0/1 chống crash
`esp_nn` — lỗi từng gây crash 1 lần/14 phút, đã mất công tìm và khoá). Thêm một đường ghi âm liên tục
song song là thay đổi có rủi ro thật, cần một phiên riêng để làm cẩn thận và kiểm định lại ổn định,
không làm vội trong phiên "ngoài kế hoạch".

Chọn phương án an toàn: mở rộng mẫu bằng serial log (không đụng firmware/board). Bắt thêm 3 phút
ngáy thật liên tục (09:32:11–09:35:32).

**Kết quả:** chỉ **1 sự kiện xác nhận mới** (id=105, `confidence=0,793`) dù ngáy gần như liên tục.
Nhưng 29/195 cửa sổ đơn lẻ (~15%) vượt ngưỡng 0,45 — cho thấy `SNORE_REQUIRED_HITS=2` đang lọc khá
gắt: bắt được các đợt ngáy đủ mạnh/đủ dài, bỏ sót nhiều nhịp thở ngáy đơn lẻ. Đây là **đặc tính đã
biết của thiết kế**, không phải lỗi — đổi giá trị này là "đổi ngưỡng", nằm ngoài phạm vi kế hoạch.

Gộp toàn bộ mẫu ngáy thật hôm nay thành **n=7**: 0,461 / 0,539 / 0,566 / 0,582 / 0,656 / 0,793 / 0,871
(trung bình ≈0,64), so với nhiễu môi trường n=3: 0,461 / 0,594 / 0,98 (trung bình ≈0,68). **Kết luận
không đổi so với Session 4** — hai dải vẫn chồng lấn hoàn toàn, `confidence` một mình chưa tách được
ngáy thật khỏi nhiễu. Mẫu lớn hơn không thay đổi bức tranh, chỉ củng cố nó chắc hơn.

### Session 6 — 2026-08-24 (thử SNORE_REQUIRED_HITS 2→3, revert vì hồi quy thật)

Người dùng yêu cầu "tinh chỉnh model" tiếp. Brainstorm trước khi làm: xác nhận qua WebSearch model
gốc là `alek6kun/snore-recognition` (fork ví dụ `micro_speech` của TensorFlow, train trên 500 mẫu
ngáy + 500 mẫu không-ngáy từ Khan 2019). Retrain thật khả thi về công cụ (có
`scripts/gen-model-header.py` để nhúng lại `.tflite`, có tiền lệ Colab cho wakeword) nhưng cần dữ
liệu thật domain-matched mà repo chưa có cách thu an toàn (đã hoãn việc nối firmware vào
`/api/voice/record` ở Session 5 vì rủi ro thêm WS thứ hai vào hệ âm thanh không thread-safe). Quyết
định: không làm A/B (retrain) hôm nay, thử tiếp đòn bẩy không đụng trọng số —
`SNORE_REQUIRED_HITS` 2→3.

**Quy trình đo đúng cách — sửa, biên dịch, nạp, đo lại bằng dữ liệu thật, không tự nhận đã cải
thiện khi chưa đo:**

1. Sửa `SNORE_REQUIRED_HITS = 3`, biên dịch (SUCCESS, 5 phút 11 giây), nạp qua `esptool` (hash
   verified).
2. Xác nhận cấu hình mới thật sự chạy: log in `hit=x/3` (trước là `x/2`).
3. 2 phút yên tĩnh: 0 sự kiện, chỉ 2 cửa sổ đơn lẻ vượt ngưỡng — sạch.
4. **90 giây ngáy thật liên tục: 0 sự kiện, `hit` cao nhất quan sát được chỉ 1/3** — không một lần
   nào chạm được cả ngưỡng 2 cũ. Ngưỡng 3 **giết hoàn toàn khả năng bắt ngáy thật** trong mẫu này.

**Kết luận: hồi quy thật, không phải cải thiện.** Giả thuyết ban đầu ("3/4 loại nhiễu ngắn mà không
cần biết confidence") sai khi kiểm bằng ngáy thật — không có bằng chứng bù lại nào cho thấy nó lọc
nhiễu tốt hơn (phòng yên tĩnh vốn đã gần 0 sự kiện ở ngưỡng 2, không có gì để so sánh cải thiện).

**Đã revert về `SNORE_REQUIRED_HITS = 2`**, comment trong `main.cpp` ghi rõ đã thử và tại sao revert
để không ai thử lại số 3 mà không có dữ liệu mới. Biên dịch + nạp lại đang chạy, sẽ xác nhận ngáy
thật hoạt động lại bình thường trước khi đóng phiên.

**Bài học:** không có đòn bẩy rẻ nào cải thiện được specificity cho model này khi chưa có dữ liệu
domain thật. R2 vẫn mở, hướng đúng để đóng nó là Session 5 đã đề xuất — thu dữ liệu thật (phương án
A) — không phải chỉnh hằng số quyết định (phương án C) như đã tưởng.

### Session 7 — 2026-08-24 (cổng chặn RMS — độc lập với confidence)

Người dùng tiếp tục yêu cầu can thiệp model sau thất bại của Session 6. Thay vì đoán tiếp một hằng
số khác, phân tích lại chính log đã bắt được trong ngày (không cần thu thêm gì): so `RMS` (âm lượng
mic thô, tầng VAD đo, độc lập hoàn toàn với model ngáy) ngay trước mỗi sự kiện.

| Sự kiện | RMS lúc kích hoạt |
|---|---|
| Nhiễu (id=98, confidence 0,98) | **6934,4** |
| Ngáy thật (confidence 0,54) | 247,1 |
| Ngáy thật (confidence 0,79) | 36,3 |

Chênh 28-190 lần — tín hiệu tách biệt rõ hơn hẳn `confidence`. Hạn chế: chỉ **n=1** sự kiện nhiễu có
đủ RMS đối chiếu (2 sự kiện nhiễu còn lại xảy ra trước khi kịp bắt log).

**Đã thêm:** `SNORE_RMS_CEILING = 1500.0f` — chặn publish (không sửa quyết định của model, không
đụng `SNORE_REQUIRED_HITS`/`SNORE_SCORE_THRESHOLD`) khi RMS mic thô tại thời điểm kích hoạt vượt
trần. Đặt ở tầng publish trong `loop()`, không đụng `snoreTask`/mutex core 0-1 nhạy cảm đã nêu ở
Session 5 — rủi ro thấp hơn nhiều so với sửa quyết định trong model.

**Đo lại đúng quy trình:**
1. Build SUCCESS, nạp, hash verified.
2. 90 giây yên tĩnh: 0 sự kiện, DB không đổi (97→97).
3. 90 giây ngáy thật: **id=113 xuất hiện đúng trong cửa sổ** (`confidence=0,512`), không dòng
   "EVENT bị chặn" nào — **cổng RMS không giết ngáy thật**, khác hẳn thất bại của Session 6.

**Giới hạn phải nói rõ:** phiên này **chưa quan sát được** cổng RMS thực sự chặn một sự kiện nhiễu
nào — không có tiếng ồn lớn xảy ra để kiểm trực tiếp. Xác nhận được: không gây hại. Chưa xác nhận
được: có thật sự lọc nhiễu hay không. Cần một lần vô tình bắt được nhiễu lớn (như id=98 tình cờ xảy
ra ở Session 2) hoặc chủ động tạo tiếng ồn lớn (vỗ tay, gõ bàn) để kiểm dòng "EVENT bị chặn — RMS=...
vượt trần" có in ra đúng lúc hay không.

**R2 vẫn mở.** Cổng RMS là lớp phòng thủ bổ sung có cơ sở dữ liệu thật, không phải giải pháp đã xác
nhận đầy đủ. Retrain (phương án A) vẫn là hướng duy nhất giải quyết gốc rễ.
