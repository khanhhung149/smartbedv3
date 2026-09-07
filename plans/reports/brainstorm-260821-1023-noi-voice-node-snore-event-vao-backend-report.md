---
type: brainstorm
date: 2026-08-21 10:23
slug: noi-voice-node-snore-event-vao-backend
status: thiết kế đã chốt, chờ lập kế hoạch
branch: master
tiếp nối: brainstorm-260821-0943-port-tang-ai-sleep-tech-projection-phut-tu-sec-data-report.md
---

# Nối `home/room/snore_event` của voice-node vào backend

## Vấn đề

Báo cáo giấc ngủ không nói được gì về ngáy. Ô "Ngáy" hiện `—` hoặc `0`, và **không phân biệt được
"không ngáy" với "không đo được"**.

## Đính chính lời khuyên trước

Sáng nay tôi khuyên **không** dùng voice-node cho việc phát hiện ngáy, lập luận rằng pad đã làm được
và micro không phân biệt được ai ngáy. Lời khuyên đó đưa ra **khi chưa đọc `firmware/voice-node/src/`**.

Sai. Đường phát hiện ngáy trên voice-node đã dựng gần xong.

## Hiện trạng thật (scout 21/08)

### Trên board: đã xong

| Thành phần | Bằng chứng |
|---|---|
| Model | `snore_features.cpp` (77) + `snore_model.cpp` (155) + `snore_model_data.h` (7.589) — tflite-micro thật |
| Cửa sổ suy luận | 1 giây @ 16 kHz, buffer PSRAM, task riêng core 0 |
| Luật xác nhận | `score > 0.5` **và** 3 cửa sổ liên tiếp (~3 s), cooldown 5 s |
| Publish | `mqtt.publish("home/room/snore_event", payload, false, 1)` — QoS 1 |
| Payload | `{"ts":<millis>,"confidence":<float>,"duration_ms":<uint>}` |

Đã xử lý cả tranh chấp scratch buffer `esp_nn` giữa wakeword (core 1) và snore (core 0) — crash
~1 lần/14 phút, tìm ra và khoá bằng mutex.

### Trên backend: không có gì

`grep -rn "snore" cloud/presence-ac/ --include=*.go` → **không dòng nào subscribe
`home/room/snore_event`**. Board bắn sự kiện vào hư không.

Đây không phải tính năng mới. Là **nối nốt đoạn dây còn thiếu**.

## Cảnh báo nằm sẵn trong code dự án

`cloud/presence-ac/internal/voice/record.go:18`:

> Model snore hiện train trên dataset **Khan 2019** (ngáy thu gần, phòng thu sạch)

Mic INMP441 cách giường vài mét, phòng ngủ thật, có quạt/điều hoà — khác hẳn điều kiện huấn luyện.
`record.go` tồn tại **chính vì lý do đó**: công cụ thu dữ liệu thật có nhãn
(`?label=snore` / `?label=quiet`). Người viết đã biết rủi ro tổng quát hoá và chưa đóng nó.

## Hai nguồn — bổ sung, không thay thế

| | Pad, mã `0x07` | voice-node |
|---|---|---|
| Tình trạng | chưa xác minh trên máy này | **đã chạy, đang publish** |
| Việc còn lại | đi kèm pha 01 kế hoạch `260821-0943`, chi phí 0 | subscribe + lưu, vài giờ |
| Trả lời câu hỏi | "**người nằm trên pad** có ngáy không" | "**phòng này** có tiếng ngáy không, to cỡ nào" |
| Nhiễu | miễn nhiễm tiếng ồn môi trường | bạn cùng giường, TV, tiếng đường phố |
| Độ tin cậy | firmware hãng, chưa rõ | phòng thu → chưa đánh giá thực địa |
| Cường độ ngáy | không có | **có** — áp điện không cho được |
| Riêng tư | không ghi âm | mic bật cả đêm |

**Hai câu hỏi khác nhau.** Không có nguồn nào "đúng hơn".

## Quyết định

| # | Quyết định | Lý do |
|---|---|---|
| 1 | Backend subscribe `home/room/snore_event`, lưu lại | Dùng lại toàn bộ thứ đã dựng trên board |
| 2 | **Lưu tách theo nguồn, KHÔNG gộp số với `min_data.snore_count`** | Xem "Rủi ro R1" |
| 3 | Làm cả hai nguồn (voice-node **và** pad `0x07`) | Hai câu hỏi khác nhau; khi cả hai có số thì đối chiếu chéo được |
| 4 | Backend tự đóng dấu giờ khi nhận | `ts` từ voice-node là `millis()` uptime, **không phải epoch** — board chưa NTP sync (ghi rõ ở `main.cpp:1037`). `millis()` chỉ dùng xếp thứ tự |
| 5 | Chưa hiện lên app vòng này | Model chưa đánh giá thực địa. Đưa số chưa đáng tin vào báo cáo giấc ngủ là tự tạo nợ |

## Nơi lưu — hai phương án

### A. Bảng `events` sẵn có (SQLite, Go) — rẻ nhất

`store.Event` đã có đúng hình dạng: `TS`, `Kind`, `Value`, `Source`. Chú thích còn liệt kê sẵn
`voice-node` làm nguồn hợp lệ. Chỉ cần thêm hằng `KindSnore` và một `Subscribe`.

Đường đọc `/api/events` có sẵn, không cần endpoint mới.

**Nhược:** nằm ở SQLite, còn `sleep_sessions` ở Postgres → **không join được** với phiên ngủ.

### B. Bảng mới trong Postgres — hợp với báo cáo giấc ngủ

`presence-ac` **đã có sẵn kết nối Postgres** (`sessions.PGStore`), nên chi phí thấp hơn tưởng.

Đề xuất tên: **`room_snore_events`** — không phải `device_snore_events`. Tên bảng nên nói đúng thứ
nó đo: mic nghe **căn phòng**, không nghe một người. Đặt tên vậy để lần sau không ai join nhầm nó
với một người cụ thể.

```sql
CREATE TABLE room_snore_events (
  t            TIMESTAMPTZ NOT NULL,   -- backend đóng dấu lúc nhận
  device_ms    BIGINT,                 -- millis() của voice-node, chỉ để xếp thứ tự
  confidence   REAL NOT NULL,
  duration_ms  INTEGER NOT NULL,
  source       TEXT NOT NULL DEFAULT 'voice-node'
);
```

**Khuyến nghị: B.** Ngáy thuộc về báo cáo giấc ngủ, mà báo cáo giấc ngủ sống ở Postgres. Chọn A rồi
sau này phải migrate — đúng thứ quyết định 9 của brainstorm 09:43 đã chốt là sẽ dồn SQLite về Postgres.

## Rủi ro

| # | Rủi ro | Mức | Giảm thiểu |
|---|---|---|---|
| R1 | Hai nguồn ngáy gộp thành một ô, lệch nhau thì không truy được | **Cao** | Quyết định 2: lưu tách, gắn nhãn nguồn. Hôm nay đã vấp cùng lỗi này **ba lần**: hai bộ dựng phiên tranh ghi `ended_at`; `sleep_sessions.hr_avg` khác `SleepFeatures.hr_mean`; và giờ là đây |
| R2 | Model train phòng thu, báo nhầm trong phòng ngủ thật | **Cao** | Quyết định 5: chưa hiện lên app. Dùng `record.go` thu dữ liệu thật có nhãn rồi đo tỷ lệ báo nhầm trước |
| R3 | Mic bắt tiếng ngáy của người khác / TV / ngoài đường | Trung bình | Tên bảng `room_*` nói rõ đây là phòng, không phải người. Không quy cho ai |
| R4 | Riêng tư: mic bật cả đêm | Trung bình | Board **chỉ gửi sự kiện**, không gửi audio (audio chỉ stream khi wakeword kích). Ghi rõ vào docs |
| R5 | `ts` là uptime, mất mốc sau khi board reset | Thấp | Quyết định 4: backend đóng dấu. `device_ms` chỉ để phát hiện board reset (giá trị tụt) |

## Tiêu chí nghiệm thu

- [ ] Backend nhận và lưu được sự kiện từ `home/room/snore_event`.
- [ ] Bơm thử một payload qua `mosquitto_pub` → xuất hiện đúng một dòng, `confidence` đúng.
- [ ] Board thật: giả tiếng ngáy → serial in `[snore] publish … -> OK` **và** DB có dòng tương ứng.
- [ ] `source` = `voice-node`; không dòng nào ghi vào `min_data.snore_count`.
- [ ] Board reset → `device_ms` tụt về gần 0 mà `t` vẫn tăng đều.
- [ ] Không sự kiện nào trong 10 phút phòng yên tĩnh (kiểm báo nhầm cơ bản).

## Ngoài phạm vi

- Hiện ngáy lên app (quyết định 5).
- Huấn luyện lại hoặc tinh chỉnh model.
- Gộp/đối chiếu tự động giữa hai nguồn — chỉ lưu song song, đối chiếu bằng tay trước.
- Đo cường độ ngáy theo dB.
- Thay đổi ngưỡng `0.5` / 3 cửa sổ trên firmware.

## Liên quan

- `plans/260821-0943-port-tang-so-lieu-ai-sleep-features-score/` — đưa pad về chế độ `0x20`. **Không
  chặn nhau:** khác node, khác broker, khác bảng. Làm song song được.

## Câu chưa trả lời

- Tỷ lệ báo nhầm của model trong phòng ngủ thật là bao nhiêu? Cần `record.go` + một đêm có nhãn.
- Khi cả pad và mic đều có số, đêm nào lệch thì tin bên nào? Chưa quyết — cố ý, vì chưa có dữ liệu
  để quyết.
- voice-node có nên NTP sync để `ts` thành epoch thật không? Hiện backend đóng dấu là đủ, nhưng nếu
  sau này cần khớp chính xác với `sec_data` theo giây thì phải sửa.
