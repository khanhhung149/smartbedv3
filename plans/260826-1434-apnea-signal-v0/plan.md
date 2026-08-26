---
status: pending
priority: P2
scope: project
blockedBy: []
blocks: []
---

# Apnea signal v0 (tham khảo, không chẩn đoán)

## Bối cảnh
Xem đầy đủ: `plans/reports/brainstorm-260826-1434-port-apnea-tu-chest-disp-sang-resp-rate-report.md`.

Tóm tắt quyết định: thuật toán apnea tham chiếu (`edge/reference/hiring-take-home-cpp/`) dùng `chest_disp`+`spo2` — phần cứng thật không có. Thay bằng OR-fusion 2 tín hiệu có sẵn trong `sec_data`:
- **A (native)**: `status==8` (WEAK_BREATHING) liên tục ≥10s.
- **B (suy luận)**: `heart_rate>0 AND resp_rate==0` liên tục ≥10s.
- **Corroboration** (thay SpO2): `sdata` hiện tại so với baseline trung vị 60s trước — giảm rõ → `confidence:"supported"`, không → `"weak"`.

Tích hợp vào endpoint đã có `GET /api/sessions/morning-report` (không tạo endpoint mới — endpoint này vừa code xong ở plan `260826-1241-phase2-v0-sleep-state-machine`, đã deploy + verify trên Jetson).

## Mục tiêu (Definition of Done)
- [ ] `MorningReport` (Go, `pgstore.go`) có thêm `apnea_events: [{start_s, end_s, duration_s, confidence}]`.
- [ ] `disclaimer` cập nhật nói rõ tín hiệu dựa trên resp_rate/status, không phải AHI y tế.
- [ ] Chạy thử trên dữ liệu đêm 25/08 đã có trong Postgres (dù ngắn) — không báo giả tràn lan do resp_rate=0 bình thường lúc mới nằm (~25s đầu mỗi lần settle).
- [ ] Verify thật: status có bao giờ = 7/8 trên hardware này không (ghi lại kết quả dù có hay không, không chặn tiến độ).

## Ngoài phạm vi
- Không tính AHI hay bất kỳ chỉ số chẩn đoán y tế.
- Không tự trích xuất nhịp thở từ waveform (resp_rate đã có sẵn từ pad).
- Không mua/tích hợp SpO2.
- Không cảnh báo real-time — chỉ tổng hợp trong morning-report (giữ đúng tinh thần "không báo động lúc đang ngủ" của plan Phase 2 gốc).

## Kiến trúc
```
MorningReport(ctx, deviceID, from, to) — mở rộng hàm đã có (pgstore.go)
  Cùng vòng loop đang đọc sec_data (time, heart_rate, resp_rate) — THÊM đọc status, sdata
  → track runs: (a) status==8 liên tục, (b) heart_rate>0 && resp_rate==0 liên tục
  → mỗi run ≥10s VÀ không nằm trong 25s ngay sau 1 lần MOVEMENT/SIT_UP (status 2/3) → apnea_events
  → confidence: so sdata tại thời điểm event với median(sdata) 60s trước event.start
```
Không thêm query DB mới — cùng 1 lượt SELECT đã có trong `MorningReport`, chỉ SELECT thêm 2 cột (`status`, `sdata`).

## Phases
1. `phase-01-apnea-events-trong-morning-report.md` — code + build + verify trên dữ liệu cũ.
2. `phase-02-verify-status-7-8-va-test-that.md` — verify status 7/8 trên hardware thật, test qua đêm (gộp chung với plan `260826-1241-phase2-v0-sleep-state-machine`'s Phase 2 nếu cùng đêm test).

## Rủi ro
- `resp_rate==0` bình thường trong ~25s đầu mỗi lần nằm yên (theo protocol hãng) — PHẢI loại trừ, nếu không sẽ báo giả mỗi lần trở mình.
- Ngưỡng 10s lấy nguyên từ thuật toán tham chiếu (thiết kế cho chest_disp liên tục) — chưa chắc đúng cho resp_rate rời rạc theo giây, cần tinh chỉnh bằng dữ liệu thật.
- status=7/8 có thể không bao giờ xuất hiện trên hardware này (tương tự vụ min_data/0x20 monitor mode hỏng đã gặp) — thiết kế OR-fusion đã tính tới việc này, không chặn.

## Validation Log

### Quyết định (2026-08-26)
1. **Dedupe A/B**: overlap bất kỳ (không cần ngưỡng %) → gộp 1 event, lấy min(start)/max(end). KISS.
2. **Tinh chỉnh ngưỡng 25s sau MOVEMENT/SIT_UP**: nếu test thật vẫn báo giả nhiều, ghi nhận và để sau — không dừng Phase 1 để tinh chỉnh ngay, đúng tinh thần "tham khảo v0".

### Verification Results
- Tier: Light (2 phase)
- Verified: cột `status`, `sdata` tồn tại thật trong `sec_data`, đã dùng ở `GetLatestSec` (pgstore.go) — khớp giả định plan. Failed: 0.

### Whole-Plan Consistency Sweep
- Đã đọc lại plan.md + 2 phase file sau khi cập nhật dedupe — nhất quán, không còn thuật ngữ "ưu tiên A" cũ. Không mâu thuẫn còn lại.
