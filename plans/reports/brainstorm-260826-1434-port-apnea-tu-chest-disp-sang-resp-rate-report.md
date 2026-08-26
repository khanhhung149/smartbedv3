---
title: Port apnea signal từ chest_disp/SpO2 sang resp_rate/status thật
date: 2026-08-26
type: brainstorm
---

# Port thuật toán apnea sang resp_rate/heart_rate (thay chest_disp/SpO2)

## Vấn đề

Thuật toán apnea tham chiếu (`edge/reference/hiring-take-home-cpp/`, đã pass ground-truth take-home) dùng 2 input phần cứng thật không có:
- `chest_disp`: waveform biên độ ngực liên tục, lọc Butterworth (0.1-0.5Hz) + đếm đỉnh.
- `spo2`: bằng chứng phụ giảm báo động giả (baseline vs recent, drop%).

Phần cứng thật (sleep-pad Legact V2, đường binary 0x85 — đường đang chạy) mỗi giây gửi: `status, heart_rate, resp_rate` (đã tính sẵn on-board, không phải waveform), `sdata`/`pdata` (2 số nguyên, hãng không định nghĩa ý nghĩa vật lý). Không có SpO2, không mua thêm cảm biến (định hướng Michael: ship cái LD2410C+pad hiện có chạy được).

## Scout — dữ liệu thật đã kiểm tra

- `pdata`: gần hằng số (3018-3031) mọi trạng thái → không dùng được, có vẻ baseline áp lực tĩnh.
- `sdata`: biến thiên mạnh (133-3064), khác rõ theo status (on-bed TB 778, off-bed TB 546, heavy-object TB 428) → có tiềm năng làm proxy biên độ dao động, nhưng ý nghĩa vật lý không được hãng định nghĩa (firmware tự ghi chú "đây là DIỄN GIẢI, không phải định nghĩa của hãng" ở 1 đường code khác cho pad model TAOSG).
- Protocol nhà sản xuất (`protocol-en.txt`) định nghĩa byte `status` của khung 0x85 có 8 mã, gồm cả `0x07=SNORE`, `0x08=WEAK_BREATHING` — firmware (`uart-parser.cpp::statusToString`) đã nhận diện sẵn 2 mã này nhưng DB thật (~28 phút dữ liệu đã có) mới chỉ thấy status 0,1,4,5, chưa từng thấy 7/8 — chưa xác nhận được hardware này có bao giờ phát 2 mã đó không.
- `resp_rate`/`heart_rate` đã tính sẵn trên pad theo giây — không cần tự trích xuất nhịp thở từ waveform nữa (phần Butterworth+peak-detect của thuật toán gốc trở thành thừa cho input thật).

## Quyết định (đã chốt qua AskUserQuestion)

1. **Chấp nhận độ tin cậy thấp hơn khi thiếu SpO2**, ghi nhãn rõ "tham khảo" — không chờ mua cảm biến (khớp định hướng Michael).
2. **Proxy chính**: `resp_rate==0` khi đang on-bed liên tục ≥10s (loại off-bed bằng `heart_rate>0`).
3. **Verify status=7/8 trước khi thiết kế** — nhưng thiết kế OR-fusion dưới đây làm cho kết quả verify KHÔNG chặn tiến độ (chạy đúng dù có hay không có status 7/8).

## Thiết kế cuối

OR-fusion 2 tín hiệu độc lập:
- **A (native)**: `status==8` (WEAK_BREATHING) liên tục ≥10s.
- **B (suy luận)**: `heart_rate>0 AND resp_rate==0` liên tục ≥10s.
- **Corroboration** (thay SpO2): khi A hoặc B trigger, so `sdata` hiện tại với baseline trung vị 60s trước — giảm rõ rệt → `confidence:"supported"`, không giảm → `confidence:"weak"`.

Trigger = A OR B (giảm bỏ sót). Confidence dựa vào sdata (giảm hoang mang khi báo giả, không phải giảm số lượng báo).

**Tích hợp**: mở rộng response `GET /api/sessions/morning-report` đã có (không tạo endpoint mới, DRY) — thêm `apnea_events: [{start_s,end_s,duration_s,confidence}]`, cập nhật `disclaimer` nói rõ đây là tín hiệu resp_rate/status, không phải AHI y tế.

## Rủi ro / vấn đề mở

- `resp_rate==0` có thể xảy ra bình thường trong ~25s đầu mỗi lần nằm yên (theo protocol: "chỉ có giá trị sau nằm yên liên tục") → cần loại các đợt resp_rate=0 xảy ra ngay sau 1 sự kiện MOVEMENT/SIT_UP để tránh báo giả — CHƯA thiết kế chi tiết, để lại cho phase code.
- Chưa xác nhận status=7/8 có bao giờ xuất hiện trên hardware này — không chặn thiết kế nhưng nên verify trước khi code để biết trọng số ưu tiên giữa A/B.
- Ngưỡng 10s lấy nguyên từ thuật toán gốc (tham chiếu take-home) — dữ liệu thật có thể cần ngưỡng khác, phải tinh chỉnh bằng dữ liệu thật (đêm 25/08 đã có + đêm test tới).

## Không phải làm (out of scope)

- Không tự trích xuất nhịp thở từ waveform (resp_rate đã có sẵn).
- Không mua/portSpO2.
- Không tính AHI hay bất kỳ chỉ số chẩn đoán y tế nào.
