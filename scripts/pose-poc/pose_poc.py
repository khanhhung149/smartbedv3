#!/usr/bin/env python3
"""PoC: đọc MJPEG stream từ node esp32cam-stream, vẽ 33 pose landmark lên cửa sổ live.

Công cụ nghiệm thu, KHÔNG phải code production. Nó trả lời đúng một câu hỏi: camera
RGB đặt trên giường có cho pose landmark dùng được không.

Đây KHÔNG phải `edge/vision/` của Phase 05. Phase 05 là MediaPipe Pose chạy trên
Jetson Orin, thuộc kiến trúc thật; script này chạy trên laptop x86_64 và sống trong
`scripts/` có chủ đích. Xem plans/260814-1237-esp32cam-stream-mediapipe-poc/.

Chạy:
    pip install -r requirements.txt
    ./download_model.sh
    python pose_poc.py --url http://<ip>:81/stream

Stream ở cổng 81; cổng 80 chỉ có trang HTML để xem bằng mắt. Board chỉ phục vụ MỘT
client stream tại một thời điểm — đóng tab trình duyệt trước khi chạy script này.
"""

import argparse
import sys
import time

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

# 35 cặp nối xương, Tasks-native. KHÔNG dùng mp.solutions — từ mediapipe 1.0.0 toàn bộ
# `mp.solutions` (gồm drawing_utils, POSE_CONNECTIONS, landmark_pb2) đã bị gỡ khỏi
# package; top-level chỉ còn Image, ImageFormat, tasks. Script này viết cho API mới.
_POSE_CONNECTIONS = vision.PoseLandmarksConnections.POSE_LANDMARKS

# Không vẽ landmark mà model không thật sự nhìn thấy. Người nằm nghiêng thì nửa thân
# bên kia bị che — vẽ nó ra là bịa vị trí, đúng thứ mà edge/README.md cấm.
_MIN_VISIBILITY = 0.5

_LANDMARK_COLOR = (0, 255, 0)  # BGR
_CONNECTION_COLOR = (255, 255, 255)


def draw_pose(frame, landmarks) -> None:
    """Vẽ 33 landmark + các đường nối lên frame (tại chỗ).

    Tự vẽ vì mediapipe 1.0.0 không còn drawing_utils. Toạ độ landmark là tỉ lệ
    0..1 so với khung hình, phải nhân với kích thước thật.
    """
    height, width = frame.shape[:2]
    points = [
        (int(lm.x * width), int(lm.y * height), lm.visibility) for lm in landmarks
    ]

    for connection in _POSE_CONNECTIONS:
        start_x, start_y, start_vis = points[connection.start]
        end_x, end_y, end_vis = points[connection.end]
        if start_vis < _MIN_VISIBILITY or end_vis < _MIN_VISIBILITY:
            continue
        cv2.line(frame, (start_x, start_y), (end_x, end_y), _CONNECTION_COLOR, 2)

    for x, y, visibility in points:
        if visibility < _MIN_VISIBILITY:
            continue
        cv2.circle(frame, (x, y), 4, _LANDMARK_COLOR, -1)

# Backoff khi mất stream: 1s, 2s, 4s, rồi giữ ở 5s. Node có thể đang khởi động lại
# hoặc WiFi chập chờn — thử lại dồn dập không giúp gì mà chỉ làm log khó đọc.
_BACKOFF_START_S = 1.0
_BACKOFF_MAX_S = 5.0

# Sau ngần này lần đọc hỏng liên tiếp thì coi như stream đã chết, mở lại kết nối.
_READ_FAILURES_BEFORE_RECONNECT = 30

# Sau ngần này lần mở lại thất bại liên tiếp thì hét lên. Không thoát — node có thể
# đang được cắm lại nguồn, và người dùng muốn script tự hồi phục.
_RECONNECTS_BEFORE_LOUD_WARNING = 3

_FPS_REPORT_INTERVAL_S = 5.0

# Bao lâu không nhận được byte nào thì coi là stream chết. Ở 20 fps, một frame về mỗi
# ~50ms, nên 3 giây là dư sức cho một nhịp WiFi chập chờn mà vẫn báo dropout kịp thời.
_STREAM_TIMEOUT_MS = 3000


def log(message: str) -> None:
    """Ghi ra stderr để stdout trống, tiện pipe nếu sau này cần."""
    print(message, file=sys.stderr, flush=True)


def open_stream(url: str) -> cv2.VideoCapture:
    """Mở stream MJPEG. Trả về capture kể cả khi chưa mở được — caller tự kiểm tra."""
    # Timeout PHẢI truyền qua constructor. Gọi cap.set(...) sau khi mở thì FFMPEG làm
    # ngơ — đo thật 14/08: đặt bằng .set() vẫn mất đúng 30 giây mặc định mới báo chết.
    #
    # 30 giây mù là quá lâu: cửa sổ đứng im mà script vẫn tưởng mọi thứ bình thường,
    # đúng thứ mà quy tắc dropout muốn tránh.
    cap = cv2.VideoCapture(
        url,
        cv2.CAP_FFMPEG,
        [
            cv2.CAP_PROP_OPEN_TIMEOUT_MSEC,
            _STREAM_TIMEOUT_MS,
            cv2.CAP_PROP_READ_TIMEOUT_MSEC,
            _STREAM_TIMEOUT_MS,
        ],
    )
    # Giữ hàng đợi 1 frame: xem tư thế người đang nằm thì cần hiện tại, không cần đủ.
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    return cap


def build_landmarker(model_path: str) -> vision.PoseLandmarker:
    options = vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=model_path),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    return vision.PoseLandmarker.create_from_options(options)


def main() -> int:
    # RawDescription: mặc định argparse dồn hết docstring thành một khối chữ liền,
    # nuốt sạch xuống dòng và làm phần "Chạy:" không đọc được.
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--url",
        required=True,
        help="URL stream — cổng 81, ví dụ http://192.168.1.42:81/stream",
    )
    parser.add_argument(
        "--model",
        default="pose_landmarker_full.task",
        help="Đường dẫn file .task (mặc định: pose_landmarker_full.task)",
    )
    args = parser.parse_args()

    try:
        landmarker = build_landmarker(args.model)
    except Exception as exc:  # noqa: BLE001 — muốn thông báo dễ đọc, không traceback
        log(f"Không tạo được PoseLandmarker từ '{args.model}': {exc}")
        log("Đã chạy ./download_model.sh chưa?")
        return 1

    log(f"Đang mở {args.url} — nhấn 'q' trong cửa sổ để thoát.")
    cap = open_stream(args.url)

    frames_ok = 0
    frames_dropped = 0
    read_failures = 0
    reconnects = 0
    backoff_s = _BACKOFF_START_S

    # detect_for_video đòi timestamp tăng đơn điệu. Dùng đồng hồ tường chứ KHÔNG dùng
    # số đếm frame: frame rơi làm số đếm lệch khỏi thời gian thật, và bộ theo vết sẽ
    # hiểu sai tốc độ chuyển động.
    start_s = time.monotonic()
    last_timestamp_ms = -1
    last_fps_report_s = start_s
    frames_since_report = 0

    try:
        while True:
            ok, frame = cap.read()

            if not ok:
                # KHÔNG vẽ lại frame cũ. Quy tắc của edge/README.md: dropout phải được
                # đánh dấu rõ ràng, không bao giờ bịa. Cửa sổ đứng im là thông tin
                # đúng — nó nói rằng không có dữ liệu mới.
                frames_dropped += 1
                read_failures += 1

                if read_failures < _READ_FAILURES_BEFORE_RECONNECT:
                    continue

                reconnects += 1
                if reconnects >= _RECONNECTS_BEFORE_LOUD_WARNING:
                    log(
                        f"CẢNH BÁO: mất stream, đã thử mở lại {reconnects} lần liên "
                        f"tiếp. Kiểm tra nguồn của node và {args.url}"
                    )
                else:
                    log(f"Mất stream — mở lại sau {backoff_s:.0f}s")

                cap.release()
                time.sleep(backoff_s)
                backoff_s = min(backoff_s * 2, _BACKOFF_MAX_S)
                cap = open_stream(args.url)
                read_failures = 0
                continue

            # Đọc được frame thật: coi như đã hồi phục.
            read_failures = 0
            reconnects = 0
            backoff_s = _BACKOFF_START_S

            now_s = time.monotonic()
            timestamp_ms = int((now_s - start_s) * 1000)
            # Hai frame trong cùng một mili-giây sẽ làm detect_for_video ném lỗi. Ép
            # tăng ít nhất 1ms thay vì để nó gãy giữa buổi nghiệm thu.
            if timestamp_ms <= last_timestamp_ms:
                timestamp_ms = last_timestamp_ms + 1
            last_timestamp_ms = timestamp_ms

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            result = landmarker.detect_for_video(mp_image, timestamp_ms)

            if result.pose_landmarks:
                draw_pose(frame, result.pose_landmarks[0])
            else:
                # Không tìm thấy người là kết quả hợp lệ, không phải lỗi — nói thẳng
                # trên hình thay vì để người xem đoán là script treo.
                cv2.putText(
                    frame,
                    "khong thay nguoi",
                    (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.8,
                    (0, 0, 255),
                    2,
                )

            frames_ok += 1
            frames_since_report += 1

            elapsed_since_report = now_s - last_fps_report_s
            if elapsed_since_report >= _FPS_REPORT_INTERVAL_S:
                fps = frames_since_report / elapsed_since_report
                log(
                    f"{fps:.1f} fps  |  {frames_ok} frame đọc được, "
                    f"{frames_dropped} lần đọc hỏng"
                )
                last_fps_report_s = now_s
                frames_since_report = 0

            cv2.imshow("pose-poc", frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
    except KeyboardInterrupt:
        log("Ctrl-C — đang thoát.")
    finally:
        cap.release()
        landmarker.close()
        cv2.destroyAllWindows()

    total_s = time.monotonic() - start_s
    log(
        f"Tổng: {frames_ok} frame trong {total_s:.0f}s "
        f"({frames_ok / total_s if total_s > 0 else 0:.1f} fps trung bình), "
        f"{frames_dropped} lần đọc hỏng"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
