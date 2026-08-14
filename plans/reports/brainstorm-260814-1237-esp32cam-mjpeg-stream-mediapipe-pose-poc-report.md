# Brainstorm — Thay node ESP32-CAM ghi SD bằng MJPEG stream + MediaPipe Pose Landmarker PoC

- **Ngày:** 2026-08-14
- **Loại:** Amendment — thay thế hoàn toàn `plans/260813-0934-esp32cam-vl53l0x-camera-node/`
- **Trạng thái:** design đã chốt, chờ lập plan
- **Flags:** không

## Vấn đề

Node `esp32cam-node` hiện tại chụp ảnh → ghi microSD cục bộ, không stream. Muốn xem/xử lý phải rút thẻ SD. Hưng muốn đổi sang stream để chạy pose estimation (Google MediaPipe) trên máy tính, tức là **chuyển node từ vai trò "đầu ghi" sang "nguồn video real-time"**.

Vấn đề thật đằng sau: cần một vòng lặp phản hồi nhanh để nghiệm thu ý tưởng *quan sát tư thế ngủ bằng vision* — mục tiêu gốc của cụm camera từ đầu (đã ghi trong plan cũ: thay "Camera nhiệt/MLX90614" vì mục tiêu thật là quan sát hành vi, không phải đo nhiệt). Ghi SD rồi xem lại offline là vòng lặp quá chậm cho việc đó.

## Nghiên cứu — nguồn tài liệu

### MediaPipe Pose Landmarker (tên chính xác, thuộc Google AI Edge)

Nguồn: https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker

| Hạng mục | Giá trị |
|---|---|
| Kiến trúc | BlazePose + GHUM 3D, CNN kiểu MobileNetV2 |
| Input | detector 224×224×3, landmarker 256×256×3 |
| Output | 33 landmark, normalized coords + world coords |
| Biến thể | `pose_landmarker_lite/full/heavy.task`, float16 |
| Running mode | IMAGE / VIDEO / LIVE_STREAM (async callback) |
| Config | `num_poses`=1, `min_pose_detection_confidence`=0.5, `min_pose_presence_confidence`=0.5, `min_tracking_confidence`=0.5, `output_segmentation_masks`=false |

Docs **không công bố** model size (MB) hay latency benchmark per-device. Không tin số từ nguồn thứ cấp.

**API:** `mp.solutions.pose` là **legacy/deprecated**. Bản hiện tại là Tasks API — load file `.task`, dùng `vision.PoseLandmarker.create_from_options()`.

### MediaPipe trên Jetson aarch64 — rủi ro đã xác nhận

- **Không có wheel aarch64 chính thức trên PyPI.** Phải build from source hoặc wheel cộng đồng: [PINTO0309/mediapipe-bin](https://github.com/PINTO0309/mediapipe-bin), [anion0278/mediapipe-jetson](https://github.com/anion0278/mediapipe-jetson) — cả hai nhắm Jetson Nano/JetPack cũ, **không phải Orin/JetPack 6**.
- Build được trên JetPack 5.1.3 nhưng **chỉ chạy CPU delegate**; JetPack 6.0.2 wheel compile xong nhưng cài lỗi — [issue #5106](https://github.com/google-ai-edge/mediapipe/issues/5106).
- **GPU delegate gần như vô nghĩa:** sau fix memory leak ở 0.10.31, chênh lệch CPU vs GPU "không còn đáng kể" — [issue #6216](https://github.com/google-ai-edge/mediapipe/issues/6216). Bật GPU ở 0.10.32 gây memory swapping — [issue #6223](https://github.com/google-ai-edge/mediapipe/issues/6223).
- Thực tế cộng đồng: Orin ~20fps khi cấu hình đúng, **~5fps khi TFLite âm thầm rơi về CPU** — [NVIDIA forum](https://forums.developer.nvidia.com/t/mediapipe-tensorflow-lite-gpu-delegate-on-jetson-orin-nano/296851).

**Hệ quả:** câu "runs MediaPipe Pose on the GPU" trong `edge/README.md` là **giả định chưa verify, khả năng cao sai**. Không chặn PoC laptop, nhưng phải ghi risk để Phase 05 không đâm vào.

### Giới hạn ánh sáng yếu — có bằng chứng

- MediaPipe kém YOLOv7-pose rõ rệt trong low light — [learnopencv](https://learnopencv.com/yolov7-pose-vs-mediapipe-in-human-pose-estimation/).
- Độ chính xác 3D giảm nhanh khi điều kiện không lý tưởng — [De Gruyter, Accuracy Evaluation of 3D Pose Estimation with MediaPipe Pose](https://www.degruyterbrill.com/document/doi/10.1515/cdbme-2023-1141/html).

**Hệ quả:** ESP32-CAM (OV2640, **không IR**) trong phòng ngủ tối → Pose không dùng được ban đêm. PoC chỉ nghiệm thu ban ngày/đèn sáng. Đây là giới hạn vật lý, không sửa bằng code.

## Phương án đã cân nhắc

| | Mô tả | Ưu | Nhược |
|---|---|---|---|
| **A** | Refactor tại chỗ: giữ `esp32cam-node`, thay tầng SD bằng HTTP MJPEG | Giữ toàn bộ verify phần cứng, 1-2 ngày xong | Không thoả yêu cầu "làm lại từ đầu" |
| **B** ✅ | Xoá sạch, viết `esp32cam-stream/` từ trắng | Sạch, một chức năng duy nhất, không di sản | Mất bản ghi bring-up cũ, lặp lại một số bug đã fix |
| **C** | Bỏ ESP32-CAM khỏi vai trò vision, camera USB/CSI gắn thẳng Jetson | Đúng kiến trúc Phase 05, có IR → dùng được ban đêm | Cần mua phần cứng, không còn "stream từ ESP32" |

**Chọn: B** (quyết định của Hưng, ghi nhận sau khi đã trình bày rõ nhược điểm của B và ưu điểm của A/C).

## Quyết định đã chốt

| # | Câu hỏi | Quyết định |
|---|---|---|
| 1 | Hướng đi | **B — xoá sạch, viết lại từ đầu** |
| 2 | Phạm vi xoá | Toàn bộ `firmware/esp32cam-node/` + plan `260813-0934-...` + docs entries. **Giữ nguyên `firmware/camera-node/`** (Phase 05, thiết bị khác) |
| 3 | MediaPipe chạy đâu | **PoC laptop trước, Jetson sau** — vòng này không đụng Jetson |
| 4 | Ranh giới riêng tư | **Giữ H-25**, viết lại cho ngữ cảnh stream |
| 5 | VL53L0X | **Bỏ hẳn** → GPIO4 tự do → **H-26 (đèn flash nhấp nháy) biến mất** |
| 6 | Stream spec | **VGA 640×480, JPEG quality ~12, fps tối đa** (MediaPipe resize về 256×256 nên VGA đủ) |
| 7 | WiFi config | `include/config.h` gitignored + `config.h.example` commit (giữ pattern repo) |
| 8 | Model variant | **`pose_landmarker_full.task`** |
| 9 | Rủi ro Jetson | **Ghi risk vào docs**, sửa câu "on the GPU" trong `edge/README.md` thành chưa verify. Không verify Jetson vòng này |
| 10 | File `.task` | **gitignore + script download** từ storage.googleapis.com |
| 11 | Định dạng stream | MJPEG `multipart/x-mixed-replace` — cách duy nhất `cv2.VideoCapture(url)` đọc trực tiếp; RTSP/WebRTC trên ESP32 cần lib nặng |
| 12 | API MediaPipe | **Tasks API** (`vision.PoseLandmarker`), không dùng `mp.solutions.pose` legacy |

## Thiết kế chốt

### Xoá

| Đường dẫn | Hành động |
|---|---|
| `firmware/esp32cam-node/` | Xoá toàn bộ (gồm `src/vl53l0x.*` đang dirty chưa commit — chấp nhận mất) |
| `plans/260813-0934-esp32cam-vl53l0x-camera-node/` | Xoá cả 5 file |
| `plans/reports/brainstorm-260813-0923-...report.md` | Xoá |
| `docs/system-architecture.md:199,206` | Gỡ dòng bảng ESP32-CAM + đoạn 206 |
| `firmware/README.md` | Gỡ dòng `esp32cam-node/` khỏi bảng module, thêm `esp32cam-stream/` |
| `docs/safety/hazard-analysis.md` | H-25 giữ, viết lại cho stream. **H-26 xoá** (không còn VL53L0X → GPIO4 không bị toggle) |

### Firmware mới — `firmware/esp32cam-stream/`

Tên mới, không tái dùng `esp32cam-node` để tránh lẫn lịch sử.

```
platformio.ini             espressif32@55.3.311 (ghim version — bài học giữ lại từ node cũ), framework=espidf
sdkconfig.defaults         PSRAM on, HTTPD stack size
include/config.h.example   WIFI_SSID / WIFI_PASS
src/main.c                 init camera -> connect WiFi -> start httpd -> in IP ra serial
src/camera_config.h        pin-map AI-Thinker, VGA, quality 12, fb_count=2, PSRAM
src/stream_handler.c       GET /stream -> multipart/x-mixed-replace; boundary=frame
                           GET /       -> trang HTML 1 thẻ <img> để kiểm tra bằng mắt
```

Vòng lặp: `esp_camera_fb_get()` → ghi part header + JPEG → `esp_camera_fb_return()`. Không SD, không NTP, không I2C, không `storage.*`.

**H-25 phiên bản mới:** node chỉ tồn tại ở bench-test; **không ghi frame ra đĩa ở bất kỳ đâu** (mạnh hơn bản cũ vốn có ghi SD); stream chỉ sống trong LAN, tắt nguồn là mất. Không cần cờ `BENCH_TEST_MODE` vì không còn code path lưu trữ nào để loại bỏ.

### PoC — `edge/vision/poc/`

```
pose_poc.py           Tasks API: PoseLandmarker + VIDEO/LIVE_STREAM mode,
                      cv2.VideoCapture("http://<ip>/stream"), vẽ 33 landmark
download_model.sh     tải pose_landmarker_full.task
requirements.txt      opencv-python, mediapipe
.gitignore            *.task
```

Chạy trên laptop x86_64 (`pip install mediapipe` có wheel chính thức). Chưa đụng Jetson.

## Tiêu chí nghiệm thu

1. `pio run -t upload` thành công, serial in ra IP.
2. Mở `http://<ip>/` trên trình duyệt thấy video mượt.
3. `cv2.VideoCapture` mở được `/stream`, `cap.read()` trả frame VGA liên tục ≥5 phút không treo.
4. `pose_poc.py` vẽ được 33 landmark lên người thật, phòng **đủ sáng**.
5. `grep -ri "esp32cam-node\|vl53l0x\|MLX90614" docs/ firmware/ plans/` không còn kết quả về node cũ.

## Ngoài scope

Jetson / `edge/vision/` production, ghi DB, posture request tới mech-handler, hoạt động ban đêm, auth cho HTTP stream, so sánh lite/full/heavy.

## Rủi ro

| Rủi ro | Mức | Xử lý |
|---|---|---|
| Ban đêm ảnh gần như đen → landmark rác (OV2640 không IR) | Cao, đã có bằng chứng | Chấp nhận. PoC chỉ nghiệm thu ban ngày. Ghi vào docs như giới hạn đã biết |
| MediaPipe trên Jetson aarch64: không wheel chính thức, GPU delegate không nhanh hơn CPU | Cao, chặn Phase 05 | Ghi risk vào docs, sửa `edge/README.md`. Verify ở vòng sau |
| Stream đứt khi WiFi yếu → `cap.read()` trả False | Trung bình | PoC phải retry; **không được coi frame trống là dữ liệu thật** (quy tắc `edge/README.md`) |
| Mất bản ghi bring-up cũ (GPIO reserve, PSRAM CS, epoch time bug) khi xoá plan | Trung bình | Chấp nhận theo quyết định của Hưng |
| Viết lại từ đầu lặp lại bug cũ | Trung bình | Giữ lại 2 bài học đã biết: ghim platform version, PSRAM bắt buộc |

## Câu hỏi tồn đọng

- Sau PoC, có port lên Jetson không, hay chuyển thẳng sang hướng C (camera IR gắn Jetson)? Kết quả PoC ban ngày sẽ quyết định.
- `edge/README.md` ghi `vision/` là Phase 05 — PoC ở `edge/vision/poc/` có bị coi là kéo Phase 05 về sớm không? Đề xuất: coi là công cụ nghiệm thu, không phải phase.
- Landmark có cần lưu lại (JSONL) để phân tích sau không, hay chỉ hiển thị live? Vòng này chỉ live.

## Nguồn

- [Pose landmark detection guide — Google AI Edge](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker)
- [google-ai-edge/mediapipe issue #5106 — build Jetson Orin Nano](https://github.com/google-ai-edge/mediapipe/issues/5106)
- [google-ai-edge/mediapipe issue #6216 — CPU vs GPU không chênh lệch](https://github.com/google-ai-edge/mediapipe/issues/6216)
- [google-ai-edge/mediapipe issue #6223 — GPU memory swapping](https://github.com/google-ai-edge/mediapipe/issues/6223)
- [PINTO0309/mediapipe-bin — wheel aarch64](https://github.com/PINTO0309/mediapipe-bin)
- [NVIDIA Developer Forums — MediaPipe/TFLite GPU delegate trên Jetson Orin Nano](https://forums.developer.nvidia.com/t/mediapipe-tensorflow-lite-gpu-delegate-on-jetson-orin-nano/296851)
- [LearnOpenCV — YOLOv7 Pose vs MediaPipe](https://learnopencv.com/yolov7-pose-vs-mediapipe-in-human-pose-estimation/)
- [De Gruyter — Accuracy Evaluation of 3D Pose Estimation with MediaPipe Pose](https://www.degruyterbrill.com/document/doi/10.1515/cdbme-2023-1141/html)
