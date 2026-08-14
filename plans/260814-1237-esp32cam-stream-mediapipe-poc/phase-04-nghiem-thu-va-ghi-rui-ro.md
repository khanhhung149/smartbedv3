---
phase: 4
title: "Nghiệm thu & ghi rủi ro"
status: completed
priority: P2
dependencies: [3]
---

# Phase 4: Nghiệm thu & ghi rủi ro

## Overview

Đóng DoD toàn plan và ghi lại 2 rủi ro đã nghiên cứu nhưng chưa xử lý — MediaPipe trên Jetson aarch64, và giới hạn ánh sáng yếu — để Phase 05 của plan MVP không đâm vào.

## Requirements

- Functional: docs phản ánh đúng trạng thái đã verify vs chưa verify.
- Non-functional: mọi khẳng định trong docs phải truy được về nguồn hoặc về phép đo thật.

## Related Code Files

<!-- Updated: Validation Session 1 - sensor-characterization.md xác nhận CHƯA tồn tại, phase này tạo mới -->

**Create:**
- `docs/sensor-characterization.md` — **file mới**, xác nhận chưa tồn tại trong `docs/` (hiện chỉ có `system-architecture.md`, `safety/`, `meetings/`). Mục đầu tiên là node stream; các cụm cảm biến khác thêm sau.

**Modify:**
- `edge/README.md` — sửa câu "runs MediaPipe Pose on the GPU"
- `docs/system-architecture.md` — thêm mục rủi ro vision pipeline
- `plans/260814-1237-esp32cam-stream-mediapipe-poc/plan.md` — cập nhật status, tick tiêu chí

## Implementation Steps

1. **Sửa `edge/README.md`.** Câu hiện tại *"runs MediaPipe Pose on the GPU"* là giả định chưa verify, khả năng cao sai. Đổi thành: chạy MediaPipe Pose trên Jetson, **delegate chưa xác định** — xem mục rủi ro. Không xoá dòng `vision/ | 05 | MediaPipe Pose`, chỉ bỏ khẳng định về GPU.

2. **Thêm mục rủi ro vào `docs/system-architecture.md`** (hoặc `docs/` nơi phù hợp), nội dung có nguồn:
   - Không có wheel `mediapipe` aarch64 chính thức trên PyPI → phải build from source. Wheel cộng đồng ([PINTO0309/mediapipe-bin](https://github.com/PINTO0309/mediapipe-bin), [anion0278/mediapipe-jetson](https://github.com/anion0278/mediapipe-jetson)) nhắm Jetson Nano/JetPack cũ, **không phải Orin/JetPack 6**.
   - Build được trên JetPack 5.1.3 nhưng chỉ CPU delegate; JetPack 6.0.2 wheel compile xong nhưng cài lỗi — [issue #5106](https://github.com/google-ai-edge/mediapipe/issues/5106).
   - Sau fix memory leak ở 0.10.31, chênh lệch tốc độ CPU vs GPU "không còn đáng kể" — [issue #6216](https://github.com/google-ai-edge/mediapipe/issues/6216). Bật GPU ở 0.10.32 gây memory swapping — [issue #6223](https://github.com/google-ai-edge/mediapipe/issues/6223).
   - Thực tế: Orin ~20fps khi cấu hình đúng, ~5fps khi TFLite âm thầm rơi về CPU — [NVIDIA forum](https://forums.developer.nvidia.com/t/mediapipe-tensorflow-lite-gpu-delegate-on-jetson-orin-nano/296851).
   - **Hệ quả cho Phase 05:** phải verify toolchain MediaPipe trên Jetson **trước** khi chốt kiến trúc vision, hoặc cân nhắc runtime khác (TensorRT, YOLOv7-pose).

3. **Ghi giới hạn ánh sáng yếu.** OV2640 không IR → phòng ngủ tối thì Pose không dùng được. Có bằng chứng công bố: MediaPipe kém YOLOv7-pose trong low light ([LearnOpenCV](https://learnopencv.com/yolov7-pose-vs-mediapipe-in-human-pose-estimation/)); độ chính xác 3D giảm nhanh khi điều kiện không lý tưởng ([De Gruyter](https://www.degruyterbrill.com/document/doi/10.1515/cdbme-2023-1141/html)). Đây là **giới hạn vật lý, không sửa được bằng code** — ghi rõ để không ai tốn thời gian tune tham số.

4. **Tạo `docs/sensor-characterization.md`** với mục đầu tiên cho node stream: model camera (OV2640), độ phân giải, fps đo thật (từ Phase 2 và 3), độ trễ end-to-end đo thật, điều kiện ánh sáng đã test. Để sẵn cấu trúc để các cụm cảm biến còn lại của Phase 01 MVP thêm vào sau — file này từng là tiêu chí treo của plan cũ, lần này đóng thật.

5. **Chốt DoD:** chạy lại toàn bộ tiêu chí chấp nhận ở `plan.md`, tick từng mục, đổi `status: completed`.

6. **Trả lời câu hỏi tồn đọng** dựa trên kết quả thật: có port lên Jetson không, hay chuyển sang camera IR gắn thẳng Jetson (hướng C của brainstorm). Ghi quyết định vào `plan.md`.

## Success Criteria

- [x] `edge/README.md` không còn khẳng định GPU — thay bằng "delegate chưa xác định, và 'GPU' không phải giả định an toàn", trỏ sang §6.1.1
- [x] Mục **§6.1.1 Vision pipeline** trong `docs/system-architecture.md`, 5 link nguồn kiểm chứng được. Thêm phát hiện mới khi thực thi: mediapipe 1.0.0 gỡ hẳn `mp.solutions`, nên mọi công thức Jetson tìm trên mạng (viết cho 0.10.x) sẽ không chạy nguyên xi
- [x] Giới hạn ánh sáng yếu ghi trong §6.1.1 kèm 2 nguồn, nêu rõ là **giới hạn vật lý của cảm biến, không phải bài toán tinh chỉnh**
- [x] `docs/sensor-characterization.md` đã tạo. Mục node stream toàn số đo thật; có mục **"Not measured yet"** liệt kê 4 thứ chưa đo thay vì đoán
- [x] Mọi tiêu chí ở `plan.md` đã tick
- [x] Câu hỏi tồn đọng đã có phân tích kèm dữ liệu thật ở cuối `plan.md`; quyết định cuối là của Hưng

## Risk Assessment

| Rủi ro | Xử lý |
|---|---|
| Ghi risk xong rồi quên, Phase 05 vẫn đâm vào | Đặt risk ở `system-architecture.md` (file Phase 05 bắt buộc đọc), không giấu trong plan dir |
| Ghi số fps ước lượng thay vì đo thật | Success criteria yêu cầu số đo. Node cũ đã từng dùng "~35KB/frame giả định, chưa đo thật" — đừng lặp lại |
| Kết luận "PoC thất bại" chỉ vì test trong phòng tối | Nghiệm thu bắt buộc ở phòng đủ sáng; kết quả phòng tối ghi riêng như dữ liệu về giới hạn, không phải tiêu chí đạt/trượt |
