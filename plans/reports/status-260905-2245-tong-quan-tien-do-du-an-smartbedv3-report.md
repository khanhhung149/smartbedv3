# [Report] Tổng quan tiến độ dự án SmartBed v3

**Ngày báo cáo:** 2026-09-05
**Người nhận:** Michael
**Loại báo cáo:** Project Status Overview
**Context:** Chưa có doc tổng quan trạng thái nào tồn tại sẵn (`docs/` không có `project-roadmap.md`/`project-changelog.md`) — báo cáo này tổng hợp trực tiếp từ 18+ plan, git log, và các doc rải rác.

---

## 1. Executive Summary

Dự án đang hoạt động trên nhiều mặt trận song song: cơ khí (vừa xong, xem báo cáo riêng), backend/AI giấc ngủ, firmware, và app. **Firmware (cả 3 node) đã hoàn thành; app cũng đã fix hết bug đã biết** — xác nhận trực tiếp từ user (05/09). 2 tuần gần nhất công sức chuyển trọng tâm sang **planning + cơ khí** (29 lượt sửa plan, 12 lượt sửa mech), khoảng lặng 0-commit ở app/firmware phản ánh đúng việc 2 mảng đó đã ổn định, không phải bị nghẽn. Vẫn còn 1 khối lượng việc **chưa commit** (100 file, rải khắp firmware/cloud/plans/app) — nên commit lại để chốt sổ, tránh thất lạc.

Chưa có ai quay lại đóng/tái cấu trúc **plan gốc MVP** (`260713-1019-smartbed-v3-mvp`, phiên onboarding Michael 13/07) dù 15+ plan con đã sinh ra từ đó — 1 số câu hỏi mở gốc từ phiên đó (vd. "anh Khanh in-house hay thuê ngoài?") giờ đã có câu trả lời thực tế (đang liên hệ Khanh dựng khung) nhưng chưa được ghi ngược lại vào doc gốc.

## 2. Cơ khí (Mechanical) — Hoàn thành, đã bàn giao

Xem chi tiết: `plans/reports/milestone-260905-1706-vo-hop-co-khi-san-sang-ban-giao-khanh-report.md`. Tóm tắt: 2 vỏ hộp (voice-node+radar-node, sleep-pad-node) đã thiết kế, in thật, xác nhận vừa hardware — sẵn sàng liên hệ anh Khanh dựng khung.

## 3. Backend/Cloud

- **`cloud/sleeppad`** (FastAPI + TimescaleDB + Mosquitto + Redis + FCM): có README đầy đủ, đây là backend chính đang active nhất theo git log (apnea signal, sleep score/features, morning-report gần đây).
- **`cloud/presence-ac`** (Go): **không có README** — khó đánh giá trạng thái từ tài liệu, chỉ thấy qua git log là có sửa (events, mqttclient, store) nhưng không rõ mức độ hoàn thiện.
- **`cloud/mqtt`**: có doc contract topic, nhưng **nội dung README nhắc "2 ESP32 node (door node + room node)"** — thuật ngữ này lỗi thời, kiến trúc hiện tại là radar-node/voice-node. Chưa ai cập nhật lại.

## 4. Firmware — Hoàn thành

3 node: `radar-node`, `sleep-pad-node`, `voice-node` — **đã xong** (xác nhận từ user 05/09). Ghi chú tài liệu: cả 3 node vẫn **không có README** — nên bổ sung sau để người khác/tương lai không phải hỏi lại trạng thái này.

## 5. App (Flutter) — Bug đã biết đã fix hết

3 app: `smartbed`, `sleep-pad`, `presence-ac` — **các bug đã biết (kể cả bộ AC auto-on/hiện sai trạng thái ghi trong handoff doc 20/08) đã fix hết**, xác nhận từ user (05/09); đã xoá `docs/handoff-ac-auto-on-fixes-260820.md` vì không còn giá trị tham chiếu. Ghi chú tài liệu còn lại: `presence-ac` README vẫn là mặc định Flutter mới tạo — nên cập nhật nếu app này đã có tính năng thật.

## 6. AI / Sleep Analysis

- `260826-1241-phase2-v0-sleep-state-machine`, `260826-1434-apnea-signal-v0` — cả 2 đang **pending** (chưa bắt đầu).
- `260821-0943-port-tang-so-lieu-ai-sleep-features-score` — đánh dấu **abandoned** trong frontmatter.
- `260821-1023/1541` (nối voice-node snore event vào backend/sleep session) — **in-progress**.

## 7. Việc đã hoàn thành gần đây

- ESP32-CAM stream + MediaPipe PoC.
- Đồng bộ sleep-pad-node sang ESP-IDF.
- Chuyển stack (dev) sang Jetson.
- Vỏ hộp cơ khí (mục 2).
- **Cả 3 firmware node (radar/sleep-pad/voice) — hoàn thành.**
- **App: fix hết bug đã biết**, bao gồm bộ bug AC auto-on/hiện sai trạng thái (doc handoff liên quan đã dọn).

## 8. Rủi ro/khoảng trống tài liệu (không phải lỗi kỹ thuật, nhưng đáng lưu ý)

- Plan gốc MVP chưa được cập nhật/đóng dù 15+ plan con đã tách ra từ đó.
- 10 plan cũ ở `plans/sleep-pad/` (từ trước khi gộp repo) hầu hết ghi "pending" — **không rõ còn là cam kết thật hay chỉ là chưa ai dọn status sau khi gộp repo** (chưa hỏi lại, xem Câu hỏi mở).
- 100 file chưa commit rải khắp firmware/cloud/plans/app — nên commit lại dù các mảng đã xong, để lịch sử git phản ánh đúng trạng thái thật.
- `cloud/presence-ac` (Go) và cả 3 firmware node không có README — khó đánh giá "sẵn sàng" tới đâu chỉ bằng đọc repo cho người ngoài/tương lai, dù bản thân việc đã xong.

## Câu hỏi mở
1. 10 plan "pending" ở `plans/sleep-pad/` (trước khi gộp repo) — còn là việc thật cần làm, hay có thể đóng/xoá vì đã lỗi thời? (Chưa được xác nhận trong đợt cập nhật này — giữ nguyên, không tự ý xoá.)
