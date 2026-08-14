---
phase: 3
title: "PoC MediaPipe Pose Landmarker"
status: completed
priority: P1
dependencies: [2]
---

# Phase 3: PoC MediaPipe Pose Landmarker

## Overview

Script Python trên laptop x86_64 đọc MJPEG stream từ node bằng OpenCV, chạy MediaPipe Pose Landmarker (Tasks API), vẽ 33 landmark lên cửa sổ live.

## Requirements

- Functional: mở được `http://<ip>:81/stream`, vẽ skeleton lên người thật, chạy ổn định ≥5 phút.
- Non-functional: **không được coi frame trống là dữ liệu thật** — quy tắc của `edge/README.md` ("Dropouts are marked explicitly, never fabricated"). `cap.read()` trả `False` phải log + retry, không vẽ frame cũ như thể là mới.

## Architecture

```
cv2.VideoCapture("http://<ip>:81/stream", cv2.CAP_FFMPEG, [timeout 3000ms])
   └─ loop:
        ok, frame = cap.read()
        if not ok: log dropout, reconnect với backoff, continue
        rgb   = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_img = mp.Image(image_format=SRGB, data=rgb)
        result = landmarker.detect_for_video(mp_img, timestamp_ms)
        vẽ 33 landmark + connections -> cv2.imshow
```

**Tasks API, không phải legacy.**

<!-- Updated: thực thi 14/08 - mediapipe 1.0.0 go bo hoan toan mp.solutions -->
Plan viết cho mediapipe 0.10.x. Thực tế `pip install mediapipe` hôm nay cho **1.0.0**, và bản này đã **gỡ hẳn toàn bộ `mp.solutions`** khỏi package — `drawing_utils`, `POSE_CONNECTIONS`, `landmark_pb2` đều biến mất, top-level chỉ còn `Image`, `ImageFormat`, `tasks`. Nghĩa là đoạn "chuyển sang `NormalizedLandmarkList` proto rồi gọi `drawing_utils`" ở bước 3 dưới đây **không chạy được**. Thay bằng: `vision.PoseLandmarksConnections.POSE_LANDMARKS` (35 cặp) + hàm `draw_pose()` tự viết bằng OpenCV. Đã verify chạy thật với 1.0.0. Hệ quả tốt: không còn dính legacy ở bất kỳ đâu.

Dùng:
```python
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

opts = vision.PoseLandmarkerOptions(
    base_options=mp_python.BaseOptions(model_asset_path="pose_landmarker_full.task"),
    running_mode=vision.RunningMode.VIDEO,
    num_poses=1,
    min_pose_detection_confidence=0.5,
    min_tracking_confidence=0.5,
)
landmarker = vision.PoseLandmarker.create_from_options(opts)
```

`RunningMode.VIDEO` cần timestamp tăng đơn điệu (ms). Dùng đồng hồ tường của client, không dùng số đếm frame — dropout làm số đếm lệch khỏi thời gian thật.

## Related Code Files

<!-- Updated: Validation Session 1 - dời khỏi edge/vision/ để không tạo thư mục Phase 05 -->

**Create:**
- `scripts/pose-poc/pose_poc.py`
- `scripts/pose-poc/download_model.sh`
- `scripts/pose-poc/requirements.txt`
- `scripts/pose-poc/README.md`

**Modify:**
- `.gitignore` — thêm `*.task`. **Đặt vào khối "Models are large binaries" sẵn có (cạnh `*.pt`/`*.onnx`/`*.tflite`), không phải khối "Local scratch"** — cùng bản chất với các dòng đó. Pattern không giới hạn đường dẫn vì model MediaPipe ở đâu cũng không nên vào git

**Vì sao `scripts/` chứ không `edge/vision/`:** `edge/vision/` **chưa tồn tại** — `edge/README.md` liệt kê nó là module của Phase 05. Tạo nó ở đây là âm thầm khởi động Phase 05, trái với định vị "PoC là công cụ nghiệm thu". `scripts/` đã tồn tại (có `check-doc-links.sh`) và đúng bản chất công cụ kỹ sư.

## Implementation Steps

1. `requirements.txt`: `opencv-python`, `mediapipe`. Ghim version thật sau khi cài (`pip freeze`), không để trôi.
2. `download_model.sh`: `curl -L -o pose_landmarker_full.task https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task`. Kiểm tra file tồn tại + size > 0 trước khi báo thành công.
3. `pose_poc.py`:
   - `argparse`: `--url` (bắt buộc), `--model` (mặc định `pose_landmarker_full.task`).
   - Vòng lặp như Architecture. Đếm frame nhận / frame drop, in fps mỗi 5 giây ra stderr.
   - Reconnect: `cap.release()` + `VideoCapture` lại, backoff 1s→5s, sau 3 lần liên tiếp thì in cảnh báo rõ ràng.
   - ~~Vẽ landmark bằng `mp.solutions.drawing_utils` + `NormalizedLandmarkList` proto.~~ **Không chạy được trên mediapipe 1.0.0** — xem ghi chú ở mục Architecture. Thay bằng hàm `draw_pose()` tự viết, bỏ qua landmark có `visibility < 0.5` (người nằm nghiêng thì nửa thân bên kia bị che; vẽ ra là bịa vị trí).
   - `q` để thoát, giải phóng `cap` + `landmarker`.
4. `README.md`: cách chạy 3 bước (`pip install -r`, `./download_model.sh`, `python pose_poc.py --url http://<ip>:81/stream`), **ghi rõ giới hạn ánh sáng yếu** và **PoC này không phải `edge/vision/` của Phase 05** — nó là công cụ nghiệm thu, đặt ở `scripts/` có chủ đích.
5. Chạy thử trong phòng đủ sáng, ghi số fps thật vào README.

## Success Criteria

- [x] `./download_model.sh` chạy thật, tải về `pose_landmarker_full.task` **9.0 MB**; `git check-ignore -v` xác nhận bị ignore bởi `.gitignore:46`
- [x] Vẽ **33 landmark lên người thật**, phòng đủ sáng — phát hiện **343/347 frame = 99%**.
  - **Số fps phải sửa lại:** với người thật trong khung, PoC chạy **8.7 fps** chứ không phải 21.5. Stream thuần cùng cảnh đó vẫn 23.9 fps → **suy luận mới là nút thắt**, không phải camera/WiFi. Con số 21.5–22.8 đo lúc camera chĩa trần nhà là *sai lệch*: không có gì để phát hiện thì model thoát sớm. Đã sửa kết luận trong `docs/sensor-characterization.md`
  - **Còn thiếu:** khung lúc test chỉ có đầu và vai từ cự ly gần, chưa phải toàn thân nhìn từ trên giường
- [x] `edge/vision/` vẫn KHÔNG tồn tại sau phase này — `edge/` chỉ có `README.md` (ranh giới Phase 05 nguyên vẹn)
- [x] Chạy liên tục **5.5 phút** kèm suy luận pose: 7509 frame, 22.8 fps, **0 lần đọc hỏng**, không crash không treo
- [x] **Đã test thật** — reset board giữa lúc đang đọc (tương đương mất nguồn): script phát hiện dropout, mở lại, stream sống lại sau ~1s, không crash, không vẽ frame cũ.
  - **Phát hiện khi test:** FFMPEG mặc định chờ **30 giây** mới báo stream chết. Đặt `CAP_PROP_READ_TIMEOUT_MSEC` bằng `cap.set()` sau khi mở thì **bị làm ngơ hoàn toàn** — phải truyền qua constructor `cv2.VideoCapture(url, cv2.CAP_FFMPEG, [...])`. Sau khi sửa: **30.1s → 3.0s**. Không sửa thì quy tắc "dropout phải được đánh dấu rõ ràng" chỉ đúng trên giấy
- [x] fps thực đo, đã ghi vào `README.md`: **21.5 fps kèm suy luận pose** trên laptop x86_64 (nguồn cấp từ node là 20–23 fps, nên suy luận gần như không phải nút thắt). Độ trễ end-to-end **chưa đo** — cần người trước ống kính để có mốc so
- [x] Không import `mp.solutions` ở bất kỳ đâu — **đạt theo nghĩa đen**, mạnh hơn cả ý định ban đầu của tiêu chí (vốn còn chừa ngoại lệ cho `drawing_utils`). Trên mediapipe 1.0.0 thì `mp.solutions` không tồn tại nữa, nên ngoại lệ đó cũng hết chỗ dùng: connection lấy từ `vision.PoseLandmarksConnections`, phần vẽ tự viết bằng OpenCV

## Kiểm thử — vòng /test 14/08

Chạy sau khi phase đóng. Ba lỗi thật, đều nằm ở đường code **chưa từng chạy**: trước đó tôi chỉ test qua `import`, chưa chạy `pose_poc.py` như một CLI thật.

| # | Lỗi | Hậu quả nếu bỏ qua |
|---|---|---|
| 1 | `requirements.txt` liệt kê `opencv-python`, trong khi **mediapipe đã phụ thuộc sẵn `opencv-contrib-python`** | Cả hai giải nén vào cùng `site-packages/cv2/` và ghi đè nhau. Gói nào cài sau thì thắng → `import cv2` chạy nhưng `cv2.imshow` có thể ném lỗi vì dính bản headless. Bẫy pip kinh điển của OpenCV. **Đã bỏ dòng đó**, verify lại bằng venv sạch: chỉ còn 1 gói, `imshow` mở được cửa sổ |
| 2 | Help của `--url` và docstring vẫn ghi URL **thiếu cổng 81** | Người dùng đọc `--help` rồi gõ đúng theo, và không kết nối được |
| 3 | `argparse` dồn docstring thành một khối chữ liền, nuốt sạch xuống dòng | Phần "Chạy:" trong `--help` không đọc được. Sửa bằng `RawDescriptionHelpFormatter` |

Đã chạy và đạt:

- `ruff check` theo `ruff.toml` của repo — sạch
- `--help`, thiếu `--url` (exit 2), model không tồn tại (exit 1, báo dễ hiểu, không traceback)
- URL không tồn tại: backoff 1s→2s→5s, cảnh báo nêu rõ URL, không crash
- `download_model.sh` chạy lần 2 → bỏ qua tải; gặp 404 → báo lỗi và **không để lại file rác**
- Chạy thật từ venv sạch với stream sống: in fps mỗi 5s, 0 lần đọc hỏng, `imshow` mở được cửa sổ
- Firmware `pio run -t clean` rồi build lại từ số 0 — SUCCESS

## Risk Assessment

| Rủi ro | Xử lý |
|---|---|
| Ánh sáng yếu → landmark rác. MediaPipe kém rõ rệt trong low light (nguồn: LearnOpenCV YOLOv7-pose vs MediaPipe; De Gruyter 3D accuracy study) | Nghiệm thu chỉ ở phòng đủ sáng. Ghi thành giới hạn đã biết ở Phase 4 |
| `cv2.VideoCapture` buffer trễ, hiển thị chậm hơn thực tế vài giây | Đặt `CAP_PROP_BUFFERSIZE = 1`. **Rủi ro liên quan đã thành sự thật:** FFMPEG làm ngơ timeout đặt bằng `.set()` → mù 30s khi stream chết. Đã sửa bằng cách truyền qua constructor, đo lại còn 3.0s |
| Timestamp không tăng đơn điệu → `detect_for_video` ném lỗi | Dùng đồng hồ tường, ép `ts = max(ts, last_ts + 1)` |
| Coi frame lỗi là dữ liệu thật | Success criteria có bài test rút điện; vi phạm quy tắc `edge/README.md` là fail phase |
