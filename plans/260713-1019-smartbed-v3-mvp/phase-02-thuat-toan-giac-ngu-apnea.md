        # Phase 02 — Thuật toán giấc ngủ + phát hiện ngưng thở

- **Ưu tiên:** P0
- **Trạng thái:** chưa bắt đầu
- **Ước lượng:** 3-4 tuần
- **Rủi ro:** thấp (phần mềm thuần)
- **Phụ thuộc:** Phase 01

## Mục tiêu

**Đây là sản phẩm bán được đầu tiên.** Một thiết bị theo dõi giấc ngủ phi tiếp xúc: nằm lên, sáng dậy có báo cáo. Không có bộ phận chuyển động, không có khí, không có rủi ro. Có thể đóng gói thành một sản phẩm riêng (dạng tấm đặt dưới nệm) bán trước, trong khi phần giường cơ khí còn đang làm.

Giá trị lâm sàng cao nhất trong toàn bộ spec nằm ở đây: **phát hiện ngưng thở khi ngủ**. Rất nhiều người bị mà không biết.

## Vì sao làm ngay sau Phase 01

Đã có sẵn ground-truth harness VÀ thuật toán tham chiếu đã chạy pass: `edge/reference/hiring-take-home-cpp/` (copy nguyên vẹn ngày 2026-08-26 từ bài take-home tuyển dụng cũ) — dataset giả lập 600s@10Hz + code C++ (`src/smartbed_stream_processor.cpp`, 995 dòng) đã verify:
- Apnea: bắt được 304.6s→325.2s (ground-truth 300-325s).
- LEAVING vs EMPTY: phân biệt đúng tại 435.0s→437.6s (ground-truth 420-435s).
- RR ổn định 13.6-14.6 bpm (yêu cầu 12-16 bpm).

**Không cần viết thuật toán mới cho dataset giả lập — đã xong.** Nhưng thuật toán này KHÔNG cắm được vào phần cứng thật ngay: input chính là `chest_disp` (waveform dịch chuyển ngực liên tục, lọc Butterworth + đếm đỉnh) và `spo2` (bằng chứng phụ giảm báo động giả) — LD2410C không xuất waveform này qua firmware hiện tại, sleep-pad Legact V2 không có SpO2. Việc thật của phase này là quyết định port sang input thật nào (ứng viên duy nhất: `resp_rate`/`heart_rate` mà sleep-pad tính sẵn theo giây, không phải waveform thô — phải viết lại phần ước lượng biên độ, không tái dùng được đoạn lọc Butterworth).

## Chức năng

### 1. State machine trạng thái giường
`EMPTY` → `MOVING` → `LYING_STILL` → `LEAVING` → `EMPTY`

Fusion nhiều kênh, không dựa vào một cảm biến:
- `LEAVING` (tín hiệu piezo pad giảm dần nhưng presence từ radar vẫn 1) khác `EMPTY` (presence = 0). Phân biệt được cặp này là chỉ dấu fusion tốt, đây chính là tiêu chí chấm bài take-home.

### 2. Nhịp thở
- Lọc Butterworth band-pass (0.1-0.5Hz, tức 6-30 brpm) trên tín hiệu radar.
- Đếm đỉnh trên tín hiệu đã lọc, không bao giờ trên tín hiệu thô.
- Cửa sổ trượt 30s, overlap 15s (theo literature trong spec).

### 3. Phát hiện ngưng thở (tính năng lõi)
- Biên độ thở về gần 0 liên tục trên 10s → sự kiện apnea.
- Fusion 3 nguồn để giảm báo động giả: radar (biên độ thở) + mic (mất tiếng thở) + xu hướng SpO2 nếu có.
- Đếm số sự kiện mỗi đêm, quy ra chỉ số kiểu AHI, **nhưng gắn nhãn "tham khảo, không phải chẩn đoán y tế"**.

### 4. Xử lý dữ liệu bẩn (không được bỏ qua)
- `hr_bpm = 0` là dropout cảm biến, phải bỏ hoặc nội suy, tuyệt đối không đưa vào trung bình.
- Mọi kênh có nhiễu Gauss, phải lọc trước khi đếm đỉnh.

### 5. Báo cáo buổi sáng
- Tổng thời gian ngủ, số lần trở mình, số lần rời giường, số sự kiện ngưng thở, nhịp thở/nhịp tim trung bình.
- Xuất ra dashboard local (Phase 01) và sau này lên app (Phase 06).

## Việc phải làm

1. Port bộ thuật toán từ dataset giả lập sang chạy trên dữ liệu thật của Phase 01. Dữ liệu thật bẩn hơn nhiều so với giả lập, chuẩn bị tinh thần chỉnh ngưỡng lại.
2. Xây test suite: dataset giả lập (đã có ground truth) + các đêm thật đã gán nhãn tay.
3. Gán nhãn tay tối thiểu 5 đêm thật (nghe lại tiếng mic, xem biểu đồ, đánh dấu apnea/trở mình). Việc này chán nhưng bắt buộc, không có nhãn thì không biết thuật toán đúng hay sai.
4. Đo hiệu năng trên Jetson: phải chạy real-time, không được đọng.
5. Viết `docs/algorithm-sleep-analysis.md` giải thích từng bước và các ngưỡng, kèm lý do chọn ngưỡng.

## Định nghĩa hoàn thành

- [x] Chạy đúng 100% trên dataset ground-truth của take-home (apnea 300-325s, LEAVING 420-435s, nhịp thở 12-16 brpm) — verify 2026-08-26, xem `edge/reference/hiring-take-home-cpp/output/`.
- [ ] Trên 5 đêm thật đã gán nhãn: bắt được ít nhất 80% sự kiện apnea, dưới 1 báo động giả mỗi đêm
- [ ] Xử lý dropout đàng hoàng, verify bằng cách cố tình chèn dropout
- [ ] Báo cáo buổi sáng hiện trên dashboard
- [ ] Chạy real-time trên Jetson, CPU dưới 30%

## Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Dữ liệu thật bẩn hơn giả lập rất nhiều, ngưỡng phải chỉnh lại | Dự trù. Đừng tin ngưỡng của dataset giả lập, coi nó là điểm khởi đầu |
| Không có ground truth y tế thật (không có máy PSG để đối chiếu) | Chấp nhận. Gán nhãn tay + wellness positioning. Nếu sau muốn nghiêm túc thì thuê một buổi PSG ở bệnh viện đối chiếu một đêm |
| Báo động giả ngưng thở làm người dùng hoảng | Không báo động lúc đang ngủ. Chỉ tổng hợp trong báo cáo sáng. Cảnh báo real-time là chuyện của thiết bị y tế, không phải wellness |
