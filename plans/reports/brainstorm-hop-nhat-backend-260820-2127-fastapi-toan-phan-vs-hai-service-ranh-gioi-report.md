---
type: brainstorm
date: 2026-08-20 21:27
slug: hop-nhat-backend-fastapi-toan-phan-vs-hai-service-ranh-gioi
status: chưa chốt — user chạy thử một đêm rồi quyết
branch: master
liên quan: plans/260820-0900-do-8-tieng-seq-counter-va-do-ben-sqlite/plan.md
---

# Có nên đưa toàn bộ backend về hướng repo `Sleep-Tech-AI/sleep-pad-ai` (FastAPI)?

## Câu hỏi

Hai câu, hỏi liền nhau:

1. Xử trùng lặp luật dựng phiên ngủ theo hướng nào? → **chốt: dùng tech của backend gốc, tức FastAPI/Python.**
2. Nếu sửa *tất cả* backend theo hướng repo đó thì sao? Hai backend với hai ranh giới có xung đột không?

## Hiện trạng (đã kiểm bằng code, không suy đoán)

| Thành phần | Ngôn ngữ | Quy mô | Phạm vi |
|---|---|---|---|
| `cloud/presence-ac` | Go | 4.183 dòng (1.344 là test) | MQTT radar 10Hz → SQLite, state machine AC, voice WS 16kHz → ASR, WS realtime, dashboard nhúng, **+ đọc/ghi sleep_sessions** |
| `cloud/sleeppad` | Python FastAPI | 4.068 dòng | auth, devices, data, alerts, sharing, watch, contact, mqtt, **sessions** |
| `cloud/asr` | Python | — | dịch vụ ASR riêng |

Repo upstream `Sleep-Tech-AI/sleep-pad-ai` = nguồn của `cloud/sleeppad`. Phạm vi upstream **chỉ có đệm ngủ**:
không radar, không điều hòa, không voice. Bản local đã lệch upstream: thêm `sessions/`, thiếu `ai/`.

App Flutter dùng **một** base URL, trỏ vào Go. `/api/sessions*` bên Go chỉ là lớp đọc TimescaleDB —
Go đang làm proxy cho dữ liệu mà FastAPI mới là chủ.

## Xung đột: cái nào thật, cái nào không

### Thật, đang chạy

**Hai bộ dựng phiên cùng ghi `sleep_sessions`.** Go `cmd/server/main.go:210` tick 60s gọi
`pg.RebuildDevice`; Python `sessions/builder.py` tick 60s gọi `rebuild_all`. Cùng upsert khóa
`(device_id, started_at)`.

Hai bên **không cho cùng kết quả**:

- `service.py:94` truyền `now=now` → phiên treo (pad rút điện, im lặng > 30 phút) được đóng, ghi `ended_at`.
- `main.go:223` dựng `BuildOptions{OpenSeconds, CloseSeconds, MaxMinutes}` — **thiếu `Now`** → phiên cuối để mở, ghi `ended_at = NULL`.

Hệ quả quan sát được: `ended_at` của phiên đang mở lật qua lật lại mỗi 60 giây, tùy bên nào tick sau.
App lúc thấy giờ kết thúc lúc không.

Khác biệt thứ hai, nhẹ hơn: cửa sổ quét lại (Go cứng 30 ngày; Python theo `LOOKBACK`).

**Không ảnh hưởng tiêu chí 1.** Đường radar → SQLite hoàn toàn tách biệt; `sec_data`/`min_data` là dữ
liệu thô do MQTT ingest ghi, không phải do builder ghi.

### Tiềm ẩn nếu giữ hai service lâu dài

- Hai cơ chế auth: Go dev token vs FastAPI JWT + device sharing → app phải giữ hai loại credential.
- Registry thiết bị chỉ có bên FastAPI; Go coi `device_id` là chuỗi tự do.
- Hai bản SQL đọc cùng bảng (`pgstore.go` vs `service.py`) cùng phải giữ một contract JSON — đã lệch
  một lần (Go trả `null` thay `[]` khi chưa có phiên, làm app Flutter nổ).

### Không phải xung đột

- Cổng broker: `cloud/mqtt` giữ 1883, sleeppad cho override qua `MOSQUITTO_HOST_PORT` và đã có ghi chú
  trong `docker-compose.dev.yml`.
- Hai DB (SQLite cho radar, TimescaleDB cho pad): hai nơi chứa, không tranh nhau.

## Ba hướng

### A — Hợp nhất toàn bộ vào FastAPI ngay

Bỏ `cloud/presence-ac`, viết lại radar ingest + AC state machine + voice stream bằng Python.

- **Được:** một ngôn ngữ, một auth, một DB, một compose. Merge được tính năng upstream (`ai/`, watch, FCM).
- **Mất:** 4.183 dòng Go đã verify bằng test và bench thật (SQLite WAL 4.823 mẫu/s); 1.344 dòng test
  phải viết lại từ đầu. Ước ~2–3 tuần.
- **Rủi ro:** voice PCM 16kHz streaming trong asyncio phải đo lại, không được suy đoán. Radar 10Hz thì
  asyncio thừa sức.
- **Chặn:** đêm đo 8 tiếng (phase 06 đang chờ board). Đổi nền tảng ngay trước bài đo làm hỏng ý nghĩa
  con số — mất mẫu sẽ không biết do MCU, do mạng, hay do backend vừa viết lại.
- **Lưu ý:** upstream không có radar/AC/voice, nên phần đó vẫn là code riêng, chỉ đổi ngôn ngữ chứ
  không hưởng lợi gì từ "theo repo gốc".

### B — Hai service, chốt ranh giới quyền ghi

FastAPI làm chủ đệm ngủ + sessions + auth; Go chỉ radar/AC/voice. App trỏ thẳng FastAPI cho
`/sessions*`, gỡ lớp proxy bên Go.

- Rẻ (~1–2 ngày), hết trùng.
- Chấp nhận hai ngôn ngữ và hai cơ chế auth lâu dài.

### C — Bỏ trùng trước, hợp nhất sau đêm đo

Đợt này chỉ gỡ bộ dựng phiên bên Go (`rules.go`, `RebuildDevice`, goroutine tick), giữ đường đọc để app
không đổi. Sau khi có số đo 8 tiếng thì port từng module Go sang FastAPI theo thứ tự rủi ro thấp → cao:
AC → radar → voice.

## Khuyến nghị

**C, đích đến là A.**

Cái gây hại thật là hai bộ ghi cùng một bảng với hai luật lệch nhau — sửa mất nửa giờ. Di trú ngôn ngữ
là việc lớn; làm ngay lúc này thì đánh đổi bằng chính bài đo mà plan `260820-0900` đang phục vụ.

B chỉ nên là điểm dừng nếu quyết định giữ Go lâu dài cho voice.

## Cho đêm chạy thử

Chạy hiện trạng được. Hậu quả duy nhất: `ended_at` của phiên đang mở dao động. Dữ liệu thô và toàn bộ
số đo tiêu chí 1 không bị ảnh hưởng.

Muốn tránh dao động mà không đụng code: bỏ `POSTGRES_URL` trong `.env` của presence-ac → Go tắt cả
writer lẫn `/api/sessions*`; đổi lại app mất màn hình phiên ngủ trong đêm đó.

## Ghi chú thao tác

Trong phiên này đã lỡ xóa `internal/sessions/rules.go`, `rules_test.go` và cắt phần ghi trong
`pgstore.go` trước khi user dừng lại. **Đã khôi phục đầy đủ**: `go build ./...` sạch, `go test ./...`
xanh 8/8 package, 56 dòng `LatestSec`/`GetLatestSec` chưa commit vẫn còn nguyên.

## Câu chưa trả lời

- Voice có bắt buộc phải ở Go không? Nếu đo được asyncio kham nổi PCM 16kHz thì A rẻ hơn hẳn ước tính.
- App Flutter sẽ dùng auth nào sau hợp nhất — JWT của sleeppad thay dev token? Ảnh hưởng tới màn cài đặt.
- Có ý định kéo `ai/` từ upstream về không? Nếu có thì A mạnh thêm; nếu không thì lợi ích "merge upstream" nhỏ hơn.
