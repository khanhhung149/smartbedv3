#!/usr/bin/env bash
# Tải model Pose Landmarker. File .task bị gitignore — model là binary ~9MB, không
# thuộc về git; ai cần thì chạy lại script này.
set -euo pipefail

cd "$(dirname "$0")"

MODEL_FILE="pose_landmarker_full.task"
MODEL_URL="https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task"

# Bản "full" chứ không phải lite/heavy: đủ chính xác cho người nằm mà vẫn chạy thời
# gian thực trên CPU laptop. So sánh ba bản nằm ngoài scope vòng này (xem plan).
if [ -s "$MODEL_FILE" ]; then
    echo "Đã có $MODEL_FILE ($(du -h "$MODEL_FILE" | cut -f1)) — bỏ qua tải."
    exit 0
fi

echo "Đang tải $MODEL_FILE ..."
# -f để lỗi HTTP thành lỗi thật; thiếu nó thì curl ghi trang 404 vào file và mọi thứ
# hỏng sau đó ở chỗ khó hiểu hơn nhiều.
curl -fL --retry 3 -o "$MODEL_FILE" "$MODEL_URL"

if [ ! -s "$MODEL_FILE" ]; then
    echo "LỖI: $MODEL_FILE trống hoặc không tồn tại sau khi tải." >&2
    rm -f "$MODEL_FILE"
    exit 1
fi

echo "Xong: $MODEL_FILE ($(du -h "$MODEL_FILE" | cut -f1))"
