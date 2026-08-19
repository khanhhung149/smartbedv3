---
type: brainstorm-report
date: 2026-08-19
slug: smartbed-flutter-sleep-session-app
status: approved
flags: []
next: /ck:plan
repos_touched: [smartbedv3, sleep_pad_AI]
---

# Brainstorm — App Flutter riêng cho SmartBed v3 (vòng 1: báo cáo giấc ngủ)

- **Ngày:** 2026-08-19
- **Yêu cầu gốc:** "dựng 1 app flutter riêng như trong plan của smartbedv3"
- **Yêu cầu tiền nhiệm (cùng phiên):** gộp chỉ số giấc ngủ từ `esp32-presence-ac` + `sleep_pad_AI` + `smartbedv3`
- **Trạng thái:** đã duyệt, chuyển sang `/ck:plan`

---

## 1. Vấn đề

Plan `plans/260713-1019-smartbed-v3-mvp/` đặt app Flutter ở **Phase 06**, phụ thuộc Phase 02/03/04/05. Kiểm tra thực tế: **cả 8 phase đều `chưa bắt đầu`**; README ghi "Nothing is built yet". Repo chỉ có `firmware/esp32cam-stream/` (MJPEG) + `scripts/pose-poc/` (chạy trên laptop, in ra màn hình, không lưu).

→ Dựng app Phase 06 nguyên bản = dựng UI cho hệ thống chưa tồn tại, mọi màn hình chạy dữ liệu giả, không nghiệm thu được gì ngoài "app có mở không".

**Chỗ thoát:** `phase-02` tự mô tả là *"sản phẩm bán được đầu tiên — sleep tracker phi tiếp xúc, dạng tấm đặt dưới nệm"*. Đó chính là `sleep_pad_AI`, đang chạy thật, có dữ liệu thật. Phase 02 về mặt dữ liệu **đã tồn tại ở repo bên cạnh**.

---

## 2. Hiện trạng 3 kho (scout)

| Kho | Có gì | Dùng được cho app? |
|---|---|---|
| `sleep_pad_AI` | FastAPI + TimescaleDB (`sec_data` 1Hz, `min_data` 1phút), MQTT ingest, auth JWT+OTP, alerts+FCM, sharing, watch; Flutter app riêng | ✅ nguồn dữ liệu duy nhất có thật |
| `esp32-presence-ac` | Go + SQLite `events(ts,kind,value,source)`, MQTT `home/room/presence` + `home/door/motion` + `tele/+/SENSOR`, REST/WS | ⏸ hoãn vòng này (presence phòng, không phải giường) |
| `smartbedv3` | `app/` `cloud/` `edge/` chỉ có README rỗng. ESP32-CAM stream + pose PoC | ❌ không sinh dữ liệu nào được lưu |

---

## 3. Phát hiện từ PDF giao thức (quyết định lại luật phiên)

Nguồn: `/mnt/d/sleep_pad_AI/Legact Pro_V2 data transfer protocol en20230130_1.pdf` (8 trang, bản 1.01 06/12/2022). Trích bằng `pypdf` (máy không có poppler).

| # | Phát hiện | Vị trí |
|---|---|---|
| F1 | `status` **không phải** trạng thái trên/rời giường mà là **mã sự kiện** của giây/phút đó: `01` rời giường · `02` cử động · `03` ngồi dậy · `04` ngủ · `05` tỉnh · `06` vật nặng · `07` ngáy · `08` thở yếu. Không tồn tại mã "đang nằm trên giường" | tr.4 §2.4.1, §2.4.2 |
| F2 | Thiết bị đã có luật phiên: vào giường **30 giây** liên tục → bắt đầu ghi; rời giường **30 phút** → dừng; trần **1440 phút** | tr.2 `<How the device works>` |
| F3 | Frame `0x13`/`0x14` — thiết bị **tự sinh báo cáo giấc ngủ hằng ngày 9:00**: tổng thời gian ngủ, hiệu suất %, điểm 0–100, số lần trở mình, sleep latency, số lần rời giường, **AHI**, tổng ngáy; `0x14` trả **hypnogram từng phút** `0x11 Deep / 0x12 Light / 0x13 REM / 0x14 Wake / 0x15 Out`. **Chưa ai đọc** — firmware chỉ gửi `0x04` và `0x08` | tr.7 §2.17, tr.8 §2.18 |
| F4 | Đồng hồ pad = local-time đóng giả UTC, có drift, "nên hiệu chỉnh mỗi ngày" bằng `0x0B`. Firmware `mqtt-client.cpp:296` forward nguyên `ts`; `main.cpp` **chưa từng gửi `0x0B`**; backend `mqtt/parser.py` hiểu là epoch UTC → **trục thời gian sleep_pad hiện không tin được** | tr.2 + tr.6 §2.9 (đối chiếu code) |
| F5 | `hr`/`rr` = 0 khi rời giường **hoặc khi không tính được** → trung bình phiên phải loại 0 | tr.4 §2.4.1 |

**Hệ quả:** không tự viết sleep staging — thiết bị đã có Deep/Light/REM + AHI. Nhưng cần firmware đọc `0x13/0x14`, để pha sau.

---

## 4. API hiện có — thiếu đúng thứ cần

```
GET /data/{id}/history   → hr, rr, resp_disorder, temp        (service.py:214-228)
                           KHÔNG có movement, KHÔNG có snore_count
GET /data/sync?from&to   → status, hr, rr, movement, snore_count,
                           resp_disorder, pthd, temp (dump thô/phút)  (service.py:238-257)
```

---

## 5. Các hướng đã cân nhắc

### 5.1 Nguồn dữ liệu cho app
| | Hướng | Kết luận |
|---|---|---|
| A | Backend `sleep_pad_AI` — dữ liệu thật | ✅ **chọn**. Nghiệm thu bằng đêm ngủ thật |
| B | Mock edge theo capability manifest §5 | ❌ 100% dữ liệu bịa; mock server phải nuôi, sẽ lệch khỏi edge thật |
| C | Adapter 2 nguồn (thật + edge) | ❌ §5 chưa từng được cài đặt lần nào → chắc chắn chọn sai trừu tượng. Vi phạm YAGNI |

### 5.2 Mức chạm backend
| | Hướng | Kết luận |
|---|---|---|
| 1 | App gọi `/data/sync`, tự cắt phiên trong Dart | ❌ luật phiên sai tầng, 2 client cho 2 kết quả, sau phải viết lại |
| 2 | Làm trọn: `persons` + `person_sources` + ingest presence/AC + `/timeline` gộp 4 nguồn | ⏸ đúng mục tiêu ban đầu nhưng chặn app |
| 3 | **Server-side sessions, hoãn presence** | ✅ **chọn**. Luật phiên viết một lần đúng chỗ; thêm presence sau chỉ là thêm cột |

### 5.3 Backend gốc (từ phần đầu phiên)
Mở rộng `sleep_pad_AI` ✅ · BFF mới ❌ (phải làm lại auth, không chỗ lưu session) · hợp nhất backend mới ❌ (đắt, không thêm lợi ích vòng 1)

---

## 6. Giải pháp chốt

### 6.1 Backend `sleep_pad_AI` — module mới theo khuôn `alerts/`
```
backend/app/sessions/   models.py  service.py  builder.py  router.py
```
`builder.py` chạy trong `lifespan`, cùng kiểu `run_alert_engine`.

**Schema thêm** (không sửa bảng cũ):
```sql
sleep_sessions(id, device_id, started_at, ended_at NULL, duration_s,
  hr_avg/hr_min/hr_max, rr_avg, movement_total, snore_total,
  resp_disorder_total, sit_up_count, wake_count, computed_at)
```
Thêm cột `received_at` vào `sec_data`/`min_data` — **trục thời gian thật** (F4).

**Luật phiên** (F1/F2/F5):
```
on_bed     := hr > 0 OR rr > 0
mở phiên   := on_bed liên tục >= 30 giây
đóng phiên := NOT on_bed liên tục >= 30 phút, hoặc chạm trần 1440 phút
tóm tắt    := AVG(hr) FILTER (WHERE hr > 0)     -- bắt buộc
sự kiện    := status 0x03 ngồi dậy · 0x05 tỉnh · 0x07 ngáy · 0x08 thở yếu
```

**API:**
```
GET /sessions?device_id&from&to           → danh sách + tóm tắt
GET /sessions/{id}
GET /sessions/{id}/timeline?bucket=1m     → hr, rr, movement, snore,
                                             resp_disorder, bed_state
```
Gộp làm ở SQL (`time_bucket`), không ở client. Presence/AC/env sau này **thêm cột**, app không sửa.

### 6.2 App `smartbedv3/app/`
```
app/lib/
  core/      api_client.dart (dio + dev token)  config.dart  theme.dart  router.dart
  data/      session_repository.dart   local/sqlite_cache.dart   models/
  features/  sessions/   session_detail/   settings/
```
- Riverpod + go_router + dio + fl_chart
- Cache **sqflite thuần, 2 bảng** (`sessions`, `timeline_points`) — drift cần codegen, 2 bảng không đáng
- Offline: đọc cache trước → gọi mạng → ghi đè khi thành công; mất mạng hiện banner "dữ liệu ngoại tuyến"
- Phone-first, layout responsive sẵn cho tablet gắn giường (plan yêu cầu dùng chung code)
- Auth: **dev token** (JWT lấy bằng curl, hạn 30 ngày) trong config dev — không sửa backend, không đục lỗ auth

### 6.3 Seed/replay
`sleep_pad_AI/backend/scripts/` — script bơm một đêm dữ liệu mẫu vào Timescale + MQTT, để phát triển và test không phụ thuộc phần cứng.

---

## 7. Nghiệm thu

- [ ] Seed một đêm → `/sessions` trả **đúng 1 phiên**, `started_at`/`ended_at` khớp luật 30s/30phút
- [ ] Seed nửa đêm `hr=0` → `hr_avg` **không** tụt (chứng minh filter hoạt động)
- [ ] Tắt wifi → app vẫn mở được phiên đã tải, có banner ngoại tuyến
- [ ] Layout không vỡ ở **360dp** và **800dp**
- [ ] Mọi chỉ số gắn nhãn **"tham khảo, không dùng chẩn đoán"**

---

## 8. Ngoài phạm vi vòng này

Điều khiển tư thế · môi trường · template · capability manifest §5 · K8s cloud · pose/camera · gộp presence + AC · UI auth/OTP · chia sẻ gia đình · BLE pairing · FCM · realtime WebSocket · build iOS · firmware `0x0B`/`0x13`/`0x14`.

Lý do bỏ điều khiển: **chưa có giường thật** (quyết định của Hưng) — chưa có actuator, chưa có handler ESP32, chưa có manifest; nút bấm sẽ không nối vào đâu.

---

## 9. Rủi ro

| # | Rủi ro | Giảm thiểu |
|---|---|---|
| 1 | `on_bed := hr>0 OR rr>0` vẫn là **suy luận** — PDF nói `0` cũng nghĩa "không tính được" | Kiểm bằng đêm thật trước khi coi là chân lý; ngưỡng để trong config, không hardcode |
| 2 | Trục thời gian pad không tin được (F4) | Dùng `received_at` làm trục join/vẽ; firmware gửi `0x0B` sau NTP ở pha sau |
| 3 | **Backend FastAPI ≠ K8s mà Michael đã chốt** | Ghi rõ trong `docs/` là **cầu tạm**, không đảo ngược quyết định của Michael |
| 4 | Coupling 2 repo, không CI chung | Bắt buộc file hợp đồng API trong `docs/`, sửa cùng lúc với endpoint |
| 5 | Dev token hết hạn 30 ngày | App phải báo 401 rõ ràng, không im lặng |
| 6 | Wellness device, cấm claim y tế (luật repo) | Nhãn "tham khảo, không dùng chẩn đoán" ở mọi chỉ số |

---

## 10. Bước tiếp theo

1. `/ck:plan` từ báo cáo này
2. Cook theo plan

## 11. Câu hỏi chưa giải quyết

1. Ngưỡng `on_bed` có đúng không — chỉ trả lời được bằng một đêm dữ liệu thật.
2. `sec_data`/`min_data` hiện đang lưu `ts` sai bao nhiêu? Chưa đo trên thiết bị thật; quyết định nên có ghi `received_at` cho dữ liệu cũ hay bỏ.
3. Bao giờ đọc `0x13`/`0x14` — nguồn hypnogram + AHI có sẵn, đang bỏ phí; cần firmware + thiết bị thật.
4. `person`/`person_sources` (gộp nhiều nguồn về một người) hoãn sang vòng sau — khi thêm presence sẽ cần.
