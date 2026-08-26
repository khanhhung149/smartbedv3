---
phase: 1
title: "Chạy pose_poc.py trên Jetson"
status: completed
priority: P3
dependencies: []
---

# Phase 1: Chạy pose_poc.py trên Jetson

## Overview
Làm lại venv MediaPipe đúng cách trên Jetson (không cài thêm opencv-python), copy `scripts/pose-poc/` sang, chạy thử với stream thật từ `esp32cam-stream`.

## Requirements
- Functional: `python3 pose_poc.py --url http://<ip-esp32cam>:81/stream` chạy trên Jetson, hiển thị cửa sổ vẽ landmark khi có người trong khung ban ngày.
- Non-functional: đọc stream liên tục ≥5 phút không treo, không crash do xung đột package.

## Architecture
Xem `plan.md`. Không tạo module mới — chạy thẳng script đã có trong `scripts/pose-poc/`.

## Related Code Files
- Modify: `scripts/pose-poc/requirements.txt` (sửa comment "mediapipe không có wheel aarch64" — đã sai, cập nhật theo verify thật 26/08)
- Không tạo file mới trong repo — venv là môi trường runtime trên Jetson, không phải artifact commit.

## Implementation Steps
1. Trên Jetson: xoá venv cũ `~/mediapipe-poc-venv` (đã lỡ cài `opencv-python` thêm, vi phạm cảnh báo trong requirements.txt).
2. Tạo lại: `python3 -m venv ~/mediapipe-poc-venv && source ~/mediapipe-poc-venv/bin/activate && pip install -r requirements.txt` (copy `scripts/pose-poc/requirements.txt` sang Jetson trước, hoặc chạy trực tiếp từ checkout nếu Jetson có sẵn repo).
3. Copy toàn bộ `scripts/pose-poc/` (gồm `pose_poc.py`, `posture.py`, `protocol.py`, `pose_landmarker_full.task` — model file, không phải chỉ code) sang Jetson.
4. Xác nhận `esp32cam-stream` đang cùng LAN với Jetson (IP thật, ping thử).
5. Chạy `python pose_poc.py --url http://<ip>:81/stream`, xác nhận cửa sổ hiển thị (cần `DISPLAY` đúng nếu chạy qua SSH — dùng `ssh -X` hoặc chạy trực tiếp trên Jetson có màn hình cắm sẵn).
6. Đứng trước camera, quan sát landmark vẽ đúng, chạy liên tục ≥5 phút.
7. Sửa comment trong `requirements.txt` (dòng đầu file, hiện nói "KHÔNG dùng cho Jetson aarch64: mediapipe không có wheel aarch64 chính thức") — thay bằng ghi nhận đã verify chạy được 26/08, kèm lưu ý venv riêng để tránh xung đột numpy với package hệ thống.

## Success Criteria
- [x] Venv mới không có `opencv-python`/`opencv-python-headless` cài thêm — verify `pip list`: chỉ `opencv-contrib-python 5.0.0.93`.
- [x] `pose_poc.py` chạy ≥5 phút liên tục (320s) trên Jetson: 3474 frame đọc được, 0 lỗi đọc, không treo/crash.
- [x] Landmark vẽ được lên người thật trong khung hình — quan sát thật: giai đoạn frame 3125-3313 phát hiện 100%, 12/33 landmark nhìn rõ.
- [x] `requirements.txt` cập nhật đúng thực tế đã verify 26/08 (xoá câu sai "không có wheel aarch64").

FPS thực đo: ~7-17 (trung bình ~13-16 ổn định), thấp hơn baseline laptop 22.8fps — chấp nhận cho demo, không phải benchmark chính thức.

## Risk Assessment
- Risk: `cv2.imshow` không mở được cửa sổ nếu chạy qua SSH không forward display — nếu gặp, chạy trực tiếp trên Jetson (có bàn phím/màn hình cắm sẵn, đã xác nhận hoạt động ở phiên trước) thay vì qua SSH.
- Risk: FPS có thể thấp hơn laptop (Jetson Orin vs x86 laptop, tuỳ cấu hình) — chấp nhận cho demo, không phải benchmark chính thức.
