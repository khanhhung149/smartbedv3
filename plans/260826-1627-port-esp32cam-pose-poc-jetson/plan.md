---
status: pending
priority: P3
scope: project
blockedBy: []
blocks: []
---

# Port pose_poc.py (ESP32-CAM + MediaPipe) lên Jetson — demo/test

## Bối cảnh
Xem đầy đủ: `plans/reports/brainstorm-260826-1627-port-esp32cam-pose-poc-len-jetson-report.md`.

Đây là **demo/test ban ngày trên Jetson**, KHÔNG phải bước tiến Phase 05 (production, cần camera IR riêng, chưa mua). Không giải quyết vấn đề nhìn trong tối — chấp nhận.

Rủi ro chặn ghi nhận 14/08 ("MediaPipe không có wheel aarch64") **đã verify hết** trong phiên này trên Jetson thật (JetPack R36.4, Orin, Python 3.10.12): `pip install mediapipe` có sẵn wheel `manylinux_2_28_aarch64`, import `mediapipe.tasks.python.vision` OK trong venv riêng.

## Mục tiêu (Definition of Done)
- [ ] `scripts/pose-poc/pose_poc.py` chạy được trên Jetson, đọc stream từ `esp32cam-stream` (cùng LAN), vẽ landmark lên cửa sổ (Jetson đã có display).
- [ ] Đọc stream liên tục ≥5 phút không treo (lặp lại tiêu chí nghiệm thu 14/08, đổi target máy).
- [ ] `requirements.txt`/comment cũ nói "không có wheel aarch64" được sửa lại đúng thực tế đã verify.

## Ngoài phạm vi
- Camera IR, hoạt động ban đêm, Phase 05 production (skeleton-distance-matrix, mảng nâng, rPPG).
- Sửa bug firmware "mất WiFi 10 lần → treo vĩnh viễn" (ghi nhận 16/08, việc khác).
- Benchmark GPU delegate sâu — chỉ cần chạy được + đo FPS thô.

## Kiến trúc
```
esp32cam-stream (cùng LAN Jetson) --MJPEG http://<ip>:81/stream--> Jetson
  ~/mediapipe-poc-venv (đã tạo, cần làm lại đúng cách — xem Phase 1)
    scripts/pose-poc/pose_poc.py --url http://<ip>:81/stream
```
Không có vấn đề mapping/network như MQTT (sleep-pad, radar-node) — đây là HTTP pull trực tiếp, chỉ cần esp32cam-stream và Jetson cùng LAN.

## Phases
1. `phase-01-chay-pose-poc-tren-jetson.md` — làm lại venv đúng cách, chạy thử, verify.

## Rủi ro
- Venv hiện tại (`~/mediapipe-poc-venv`) đã lỡ cài `opencv-python` thêm — vi phạm cảnh báo trong `requirements.txt` (mediapipe tự kéo `opencv-contrib-python`, cài thêm gói khác gây đè `cv2/` lẫn nhau, `imshow` có thể lỗi). Phải xoá venv cũ, tạo lại chỉ cài từ `requirements.txt`.
- Jetson cần bật GUI/X11 để `cv2.imshow` hiển thị cửa sổ — đã xác nhận màn hình Jetson hoạt động trong session trước, nhưng cần verify chạy qua SSH có `DISPLAY` đúng không (khác chạy trực tiếp trên máy).
- ESP32-CAM cần cùng LAN với Jetson lúc test — nếu đang ở tình huống mạng khác nhau (như vụ sleep-pad/radar-node), hoãn tới khi cùng mạng.
