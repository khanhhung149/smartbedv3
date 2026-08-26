---
title: Port pose_poc.py (ESP32-CAM + MediaPipe) lên Jetson — demo/test, không phải Phase 05
date: 2026-08-26
type: brainstorm
---

# Port ESP32-CAM MediaPipe pose PoC lên Jetson

## Bối cảnh
Plan `260814-1237-esp32cam-stream-mediapipe-poc` (completed 14/08) để lại câu hỏi mở: port MediaPipe lên Jetson, hay chuyển hẳn sang camera IR gắn Jetson (hướng C, đúng spec Phase 05 Michael chốt 13/07)? Dữ liệu khi đó nghiêng về hướng C vì OV2640 không có IR — không xem được người ngủ trong phòng tối.

## Quyết định phạm vi (đã chốt qua AskUserQuestion)
Port lần này **chỉ để demo/test ban ngày trên Jetson**, KHÔNG phải bước tiến production Phase 05. Không giải quyết vấn đề tối — chấp nhận. Không làm skeleton-distance-matrix, không mảng nâng, không rPPG (đó là scope Phase 05 thật, camera khác, chưa mua).

## Verify rủi ro chặn (đã làm ngay trong phiên, trước khi thiết kế)
Rủi ro ghi nhận 14/08: "MediaPipe trên Jetson aarch64: không wheel chính thức, GPU delegate không chắc nhanh hơn CPU" — **ĐÃ HẾT CHẶN**, verify thật trên Jetson (JetPack R36.4, Orin, Python 3.10.12):
- `pip install mediapipe` → có sẵn wheel `mediapipe-1.0.1-py3-none-manylinux_2_28_aarch64.whl`, không cần build nguồn.
- Cài trực tiếp vào Python hệ thống bị xung đột numpy (opencv-contrib-python cần numpy≥2, matplotlib hệ thống cần numpy<2) → giải quyết bằng venv riêng `~/mediapipe-poc-venv`.
- Import `mediapipe.tasks.python.vision` thành công trong venv.
- CHƯA verify: FPS thật, GPU delegate có nhanh hơn CPU không (cần chạy với stream ảnh thật, để lại cho phase code/test).

## Thiết kế v0
- Copy `scripts/pose-poc/pose_poc.py` (đã có, verify laptop 14/08: 99% detect rate) sang Jetson, chạy trong `~/mediapipe-poc-venv` đã tạo.
- Trỏ `cv2.VideoCapture` vào `http://<ip-esp32cam>:81/stream` — camera board và Jetson phải cùng mạng LAN (không có vấn đề mapping khác, khác hẳn vụ MQTT của sleep-pad/radar).
- Không sửa firmware `esp32cam-stream` (đã ổn định, WiFi retry bug ghi nhận 16/08 là việc khác, không chặn PoC này).
- Success: đọc stream liên tục ≥5 phút không treo, vẽ landmark khi có người trong khung ban ngày — lặp lại đúng kịch bản nghiệm thu 14/08 nhưng chạy trên Jetson thay vì laptop.

## Ngoài phạm vi
- Camera IR, hoạt động ban đêm.
- Skeleton-distance-matrix, mảng nâng, rPPG (Phase 05 thật).
- Sửa bug WiFi-retry-treo-vĩnh-viễn của firmware (đã ghi nhận, việc khác).
- GPU delegate tuning/benchmark sâu — chỉ cần chạy được, đo FPS thô là đủ cho demo.
