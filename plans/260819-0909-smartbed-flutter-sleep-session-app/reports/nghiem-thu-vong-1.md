---
type: report
date: 2026-08-19
plan: 260819-0909-smartbed-flutter-sleep-session-app
phase: 07
status: 4/5 đạt · 1 treo
---

# Nghiệm thu bổ sung — UI redesign (sau nghiệm thu vòng 1)

User yêu cầu nâng cấp UI cho chuyên nghiệp, dễ nhìn, có biểu đồ phân tích. Đã viết lại 11 file
giao diện + theme (xem `plan.md` Validation Log Session 4). Kiểm chứng sau redesign:

- `flutter analyze` — sạch, **No issues found**
- `flutter test` — **22/22 pass** (gồm các ràng buộc: không overflow ở 360/800dp, trang không bao
  giờ cuộn ngang ở 360dp, đúng 1 em-dash và 1 số 0 khi chỉ số null)
- Chromium (đã cài `libnss3` + `libnspr4`) chụp web release build tại `localhost:9100`:

| Màn hình | Mốc | `scrollWidth == clientWidth` | Sọc overflow vàng |
|---|---|---|---|
| Danh sách | 360dp | ✓ | không |
| Danh sách | 800dp | ✓ | không |
| Chi tiết | 360dp | ✓ | không |
| Chi tiết | 800dp | ✓ | không |

- 17 pixel "vàng" bắt được khi rà ảnh là màu **icon chỉ số cử động** (`#E8B34B`), không phải sọc
  overflow của Flutter.
- Phân tích pixel xác nhận màn chi tiết render đủ: dải HR màu hồng, đường thở teal, cử động
  amber, ngáy cam, trục/header tim chart — ở cả 360 và 800.

> **Vẫn chờ mắt người xác nhận** — xem mục *Còn treo* của nghiệm thu vòng 1. Hình chụp mới tại
> `reports/evidence/ui-list-360.png`, `ui-list-800.png`, `ui-detail-360.png`, `ui-detail-800.png`.

---

# Nghiệm thu vòng 1 — báo cáo giấc ngủ

Chạy trên dev/local. **Không** đụng prod `api.sleeptech.me` (đúng quyết định #8).

**Môi trường đo**
- Backend: `sleep_pad_AI` branch `feat/sleep-sessions` (tách từ `dev/khanhhung`), Docker Compose dev, `localhost:8000`
- DB: TimescaleDB `latest-pg16`, đã có sẵn 17 584 dòng `sec_data` cũ trước khi bắt đầu
- App: Flutter 3.44.6 / Dart 3.12.2, `smartbedv3/app/`
- Dữ liệu: seed 3 đêm giả, `--start 2026-08-18T15:00:00 --hours 8`, `--seed 42`

> **Cảnh báo bắt buộc đọc:** nghiệm thu này chạy trên **dữ liệu seed**, không phải đêm ngủ thật.
> Luật `on_bed := hr > 0 OR rr > 0` (Rủi ro R1) **vẫn chưa được kiểm chứng**. Giao thức Legact
> nói `0` cũng có nghĩa "không tính được", nên cảm biến nhiễu trông giống hệt giường trống.
> Đừng đọc báo cáo này là "luật phiên đã đúng" — nó chỉ nói "luật phiên chạy đúng như đã định nghĩa".

---

## Tiêu chí 1 — seed một đêm → `GET /sessions` trả đúng 1 phiên · **ĐẠT**

```bash
$DC exec fastapi python /app/scripts/seed-night.py --device-id TEST000001 \
   --owner-email sessions-dev@example.com --start 2026-08-18T15:00:00 --hours 8
curl -s -H "Authorization: Bearer $TOKEN" 'localhost:8000/sessions?device_id=TEST000001'
```

```
số phiên   = 1
started_at = 2026-08-18T15:00:00Z
ended_at   = 2026-08-18T22:59:59Z
duration_s = 28799 (8.00 giờ)
```

`started_at` = mẫu đầu tiên, không phải mẫu thứ 30 — luật 30 giây tính khoảng bao gồm
(giây thứ 30 nằm ở +29s), nên phiên bắt đầu từ lúc lên giường chứ không phải lúc xác nhận.

**Phụ — gap 40 phút cắt đúng chỗ** (`--gap-minutes 40`):

```
số phiên = 2
2026-08-18T15:00:00Z -> 2026-08-18T18:40:00Z  (13200s)
2026-08-18T19:20:00Z -> 2026-08-18T22:59:59Z  (13199s)
```

`ended_at` = **18:40:00** = đúng thời điểm bắt đầu rời giường (15:00 + 3h40m), **không** phải
19:10 là lúc đủ 30 phút. Nếu sai chỗ này thì mỗi đêm bị cộng thêm nửa tiếng nằm giường không có thật.

---

## Tiêu chí 2 — `hr_avg` không tụt vì `hr = 0` · **ĐẠT**

Seed `TEST000002` giống hệt `TEST000001` nhưng nửa sau `hr = 0` (`--zero-hr-half`, cùng `--seed 42`).

```
TEST000001 toàn đêm       : 62.19
TEST000001 chỉ nửa đầu    : 63.74
TEST000002 (nửa sau hr=0) : 63.74
```

`hr_avg` của TEST000002 **trùng khít** trung bình nửa đầu của TEST000001. Đó là bằng chứng chặt:
`FILTER (WHERE heart_rate > 0)` loại đúng nửa bị zero rồi tính trung bình phần còn lại.
Nếu `FILTER` hỏng, con số sẽ rơi về khoảng **31**.

So `62.19` với `63.74` là so nhầm tập dữ liệu — chênh 1.55 bpm đó là do trôi circadian của
hàm sinh seed, không phải do lọc.

**Unit test luật phiên:** `python -m pytest tests/ -q` → **17 passed**, gồm 29s không sinh phiên,
30s sinh 1 phiên, off 25 phút không cắt, off 31 phút cắt đúng chỗ, trần 1440 phút, gap 40 phút,
và ngưỡng là tham số chứ không phải hằng số.

---

## Tiêu chí 3 — ngoại tuyến vẫn mở được phiên đã tải · **ĐẠT (ở tầng dữ liệu)**

`test/live_offline_test.dart` chạy đúng code path thật — `SessionRepository` + `SessionCache`
sqflite thật + backend thật, không mock:

```
offline: 1 phiên + 480 điểm timeline đọc lại từ cache, cachedAt=2026-08-19 10:42:54.075
```

Quy trình: tải thật từ `localhost:8000` → đổi `baseUrl` sang `http://127.0.0.1:1` (cổng chết,
tức là mất mạng nhìn từ phía app) → đọc lại. Cả danh sách phiên lẫn 480 điểm timeline trở về
nguyên vẹn, `isStale = true`, `cachedAt` có giá trị.

Widget test xác nhận `StaleDataBanner` hiện khi `isStale` và mang theo thời điểm cache.

**Chưa làm:** bật chế độ máy bay trên thiết bị thật/emulator. Xem mục *Còn treo*.

---

## Tiêu chí 4 — layout không vỡ ở 360dp và 800dp · **TREO**

Widget test đã kiểm cả hai mốc và **bắt được 2 lỗi tràn layout thật**:

| Lỗi | Chỗ | Nguyên nhân |
|---|---|---|
| Tràn **33px ngang** | `session_card.dart` hàng giờ + thời lượng | `Row` + `spaceBetween` không có `Expanded`; ở 360dp hai chuỗi cộng lại vượt bề rộng thẻ |
| Tràn **118px dọc** | thẻ trong lưới 2 cột ở 800dp | `GridView` cần chiều cao ô cố định, nhưng chiều cao thẻ phụ thuộc số dòng `Wrap` reflow — mọi hằng số chọn ở đây đều clip ở một bề rộng nào đó |

Cả hai đã sửa (`Expanded` + `TextOverflow.ellipsis`; `GridView` → `Wrap` tự tính bề rộng cột).
Test dùng `tester.takeException()` để bắt `RenderFlex overflow` — nếu không, Flutter chỉ vẽ
sọc vàng đen chứ không làm test đỏ.

**Vì sao vẫn treo:** tiêu chí yêu cầu nhìn bằng mắt (`flutter run -d chrome`, kéo cửa sổ, chụp
màn hình). Máy đo chỉ có device `linux`; Chromium của công cụ tự động thiếu `libnss3` + `libnspr4`,
cài cần quyền root. **Kiểm tự động không thay thế được mắt người** cho tiêu chí này — nó bắt được
tràn khung, nhưng không bắt được chữ khó đọc, khoảng cách xấu, hay thứ tự thông tin sai.

---

## Tiêu chí 5 — nhãn "tham khảo, không dùng chẩn đoán" · **ĐẠT**

```
app/lib/features/sessions/widgets/disclaimer_footer.dart:8:
  const String kWellnessDisclaimer = 'Số liệu chỉ mang tính tham khảo, không dùng chẩn đoán';

số nơi định nghĩa chuỗi : 1
số màn hình dùng        : 2  (sessions_screen.dart:117, session_detail_screen.dart:74)
```

Grep một mình không đủ — chuỗi có thể nằm trong code chết. Widget test
`the wellness disclaimer is on screen` xác nhận nó **được render thật** trên màn hình danh sách;
`data — draws the chart, the occupancy band and the disclaimer` xác nhận trên màn hình chi tiết.

---

## Còn treo

| # | Việc | Vì sao chưa làm | Cần gì |
|---|---|---|---|
| 1 | Nhìn layout ở 360dp và 800dp bằng mắt | Chromium đã chạy được (`libnss3` + `libnspr4` đã cài), đã chụp 4 ảnh mới ở `reports/evidence/ui-*.png`. Kiểm tự động bắt tràn khung nhưng không thay được mắt cho thẩm mỹ | User mở ảnh trong Explorer và xác nhận |
| 2 | Bật chế độ máy bay trên emulator Android | Không có emulator Android trên máy này (`flutter devices` chỉ thấy `linux`) | Máy có Android SDK + AVD |
| 3 | Xác minh task nền bị huỷ sạch lúc shutdown | Dưới `uvicorn --reload`, reload giết process con nên **không** task nào in dòng "stopped" — kể cả `alerts.engine` có sẵn từ trước | Chạy backend không có `--reload` |

Bằng chứng thay thế cho #3: `sessions_task` nằm trong list truyền cho `_stop_tasks`
(`app/main.py:72`) và không log nào có cảnh báo `Task was destroyed but it is pending`.

---

## Phát hiện ngoài kịch bản nghiệm thu

Bốn thứ plan nói sai hoặc thiếu, phát hiện lúc thực thi. Chi tiết ở Validation Log của `plan.md`
(Session 2 và Session 3).

| # | Vấn đề | Ảnh hưởng nếu bỏ qua |
|---|---|---|
| F-04 | Plan bảo dùng `COALESCE(received_at, time)` vì `time` là giờ thiết bị không tin được. Thực tế `subscriber.py:108` đã ghi `now()` vào `time` từ trước; `to_timestamptz()` ở `parser.py:58` là code chết 0 caller | `EXPLAIN` đo được: `COALESCE` mất index range scan và **phá chunk exclusion** của Timescale — quét mọi chunk thay vì 1. Vô hình ở 17k dòng, chí mạng ở một năm dữ liệu 1 Hz |
| F-05 | SQL mẫu trong plan sai cú pháp: `AVG(x)::real FILTER (...)` | Postgres từ chối thẳng — `syntax error at or near "FILTER"`. Cast phải bọc ngoài cả biểu thức |
| F-06 | Luật phiên không đóng khi dữ liệu **ngừng hẳn** lúc đang trên giường (pad rút điện buổi sáng) | Phiên treo mở vĩnh viễn; app hiện một đêm không có giờ kết thúc. Đã thêm tham số `now`: im lặng quá 30 phút thì đóng tại mẫu cuối — thời điểm cuối cùng có bằng chứng người còn trên giường |
| F-07 | Seed script: nhánh `i % 900` (cử động) đứng trước `i % 7200` (ngồi dậy) và `i % 5400` (tỉnh); cả hai đều chia hết cho 900 | Hai mã hiếm không bao giờ sinh ra → `sit_up_count = wake_count = 0`, và tiêu chí đếm sự kiện sẽ "đạt" bằng số 0 giả |

**Thay đổi ngoài phạm vi plan, đã hỏi và được chốt:**

- **CORS nới cho dev** (`app/main.py`): thêm `allow_origin_regex` cho `localhost` và header
  `Authorization`, **gate bằng `ENV == "dev"`**. Prod giữ nguyên đúng 4 origin cũ và chỉ
  `Content-Type`. Lý do: client web gửi JWT ở header `Authorization` và chạy ở port ngẫu nhiên —
  cả hai đều bị danh sách cũ chặn.
- **`sqflite_common_ffi` + `_web`**: `sqflite` gốc chỉ có Android/iOS/macOS. Không có hai gói này
  thì cache ném lỗi trên web và Linux desktop — tức là đúng hai nơi cần kiểm layout và ngoại tuyến.
- **`seed-night.py --owner-email`**: trước đó script gán device cho "user cũ nhất trong DB" — ngầm,
  và sai trên bất kỳ DB nào không phải mới tinh.
- **Flutter `--platforms=android,web`**: plan chỉ ghi `android`, nhưng tiêu chí 4 yêu cầu
  `flutter run -d chrome`.

---

## Số liệu

| | |
|---|---|
| Backend mới | 1 010 dòng (`app/sessions/` 5 file · `tests/` · `scripts/seed-night.py` · `apply-schema.sh` · `sleep_sessions.sql`) |
| App | 2 389 dòng Dart / 30 file |
| Test | 17 pytest + 19 widget/unit Flutter + 2 live (cần backend) |
| `flutter analyze` | sạch |
| Endpoint mở | `GET /sessions` · `GET /sessions/{id}` · `GET /sessions/{id}/timeline` |
| File hợp đồng | `smartbedv3/docs/sleep-session-api-contract.md` |
