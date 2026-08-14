# scripts/pose-poc/ — PoC MediaPipe Pose Landmarker

Đọc MJPEG stream từ node [`firmware/esp32cam-stream/`](../../firmware/esp32cam-stream/README.md), chạy MediaPipe Pose Landmarker trên laptop, vẽ 33 landmark lên cửa sổ live.

Nó trả lời **đúng một câu hỏi**: camera RGB đặt trên giường có cho pose landmark dùng được không. Trả lời xong là hết việc.

## Đây không phải `edge/vision/`

`edge/vision/` là module **Phase 05** — MediaPipe Pose chạy trên Jetson Orin, thuộc kiến trúc sản phẩm thật. Thư mục đó **chưa tồn tại** và PoC này cố ý không tạo ra nó: tạo `edge/vision/` là âm thầm khởi động Phase 05, trong khi đây chỉ là công cụ nghiệm thu.

Vị trí `scripts/` là có chủ đích, không phải tạm bợ. Đừng "dọn dẹp" bằng cách chuyển nó sang `edge/`.

## Chạy

```bash
pip install -r requirements.txt
./download_model.sh
python pose_poc.py --url http://<ip>:81/stream
```

`<ip>` là IP mà node in ra serial lúc boot. Nhấn `q` trong cửa sổ để thoát.

**Stream ở cổng 81, không phải 80.** Cổng 80 chỉ có trang HTML để xem bằng mắt.

⚠️ **Đóng tab trình duyệt trước khi chạy PoC.** Board chỉ phục vụ **một client stream tại một thời điểm** — tách cổng giải quyết được trang-vs-stream, không giải quyết stream-vs-stream. Quên đóng thì PoC báo timeout sau 3 giây (đã gặp thật 14/08).

| Tham số | Mặc định | |
|---|---|---|
| `--url` | *bắt buộc* | URL stream — **cổng 81**, ví dụ `http://192.168.1.42:81/stream` |
| `--model` | `pose_landmarker_full.task` | Đường dẫn file `.task` |

Model là binary ~9MB, bị gitignore (`*.task`) — không commit, chạy `download_model.sh` khi cần.

## Giới hạn đã biết: ánh sáng yếu

**OV2640 không có IR. Phòng ngủ tối thì PoC này không dùng được.** Đây là giới hạn vật lý của cảm biến, **không sửa được bằng cách chỉnh tham số** — đừng tốn thời gian tune `min_pose_detection_confidence`.

Có bằng chứng công bố: MediaPipe kém YOLOv7-pose rõ rệt trong điều kiện thiếu sáng ([LearnOpenCV](https://learnopencv.com/yolov7-pose-vs-mediapipe-in-human-pose-estimation/)), và độ chính xác 3D giảm nhanh khi điều kiện không lý tưởng ([De Gruyter](https://www.degruyterbrill.com/document/doi/10.1515/cdbme-2023-1141/html)).

Nghiệm thu vòng này **chỉ ở phòng đủ sáng**. Kết quả trong phòng tối ghi lại như dữ liệu về giới hạn, không phải tiêu chí đạt/trượt. Hoạt động ban đêm nằm ngoài scope — nếu cần, hướng đi là camera IR gắn thẳng Jetson, không phải tune script này.

## Dropout không được bịa

Khi `cap.read()` trả `False`, script **không vẽ lại frame cũ**. Cửa sổ đứng im là thông tin đúng: nó nói rằng không có dữ liệu mới.

Đây là quy tắc của [`edge/README.md`](../../edge/README.md) — *"Dropouts are marked explicitly, never fabricated"* — và vi phạm nó là fail phase, không phải lỗi nhỏ. Một hệ thống theo dõi giấc ngủ mà vẽ dữ liệu cũ như dữ liệu mới thì tệ hơn là không có gì.

Mất stream thì script tự mở lại với backoff 1s → 2s → 4s → 5s, và hét lên sau 3 lần liên tiếp thất bại. Không tự thoát — node có thể đang được cắm lại nguồn.

### Timeout phải truyền qua constructor

Mặc định backend FFMPEG của OpenCV chờ **30 giây** mới chịu báo stream đã chết. Suốt 30 giây đó script tưởng mọi thứ bình thường — đúng thứ quy tắc trên muốn tránh.

Sửa bằng `CAP_PROP_OPEN_TIMEOUT_MSEC` / `CAP_PROP_READ_TIMEOUT_MSEC` = 3000. **Phải truyền qua constructor `cv2.VideoCapture(url, cv2.CAP_FFMPEG, [...])`** — gọi `cap.set(...)` sau khi mở thì FFMPEG làm ngơ hoàn toàn.

Đo thật 14/08 bằng cách reset board giữa lúc đang đọc:

| | Thời gian phát hiện dropout |
|---|---|
| Mặc định, hoặc đặt bằng `cap.set()` | 30.1s |
| Truyền qua constructor | **3.0s** |

Sau khi phát hiện, script mở lại và stream sống lại sau ~1s. Không crash.

## Tasks API, không phải legacy

Bộ nhận diện là `vision.PoseLandmarker` (Tasks API). Không có một dòng legacy nào.

**Cần `mediapipe >= 1.0`.** Từ 1.0.0, Google đã gỡ **toàn bộ** `mp.solutions` khỏi package — `drawing_utils`, `POSE_CONNECTIONS`, `landmark_pb2` đều biến mất; top-level chỉ còn `Image`, `ImageFormat`, `tasks`. Hầu hết ví dụ MediaPipe trên mạng viết cho 0.10.x và sẽ gãy ngay ở dòng `import`.

Thay thế trong script này:

| 0.10.x (không còn) | 1.0.0 (dùng ở đây) |
|---|---|
| `mp.solutions.pose.POSE_CONNECTIONS` | `vision.PoseLandmarksConnections.POSE_LANDMARKS` (35 cặp, `.start`/`.end`) |
| `mp.solutions.drawing_utils.draw_landmarks` | hàm `draw_pose()` tự viết bằng OpenCV |
| `landmark_pb2.NormalizedLandmarkList` | không cần — vẽ thẳng từ landmark của Tasks API |

`draw_pose()` bỏ qua landmark có `visibility < 0.5`. Người nằm nghiêng thì nửa thân bên kia bị che; vẽ nó ra là bịa vị trí — đúng thứ mà quy tắc dropout ở trên cấm.

`RunningMode.VIDEO` đòi timestamp tăng đơn điệu. Script dùng **đồng hồ tường**, không dùng số đếm frame: frame rơi làm số đếm lệch khỏi thời gian thật và bộ theo vết hiểu sai tốc độ chuyển động.

## fps đo được

Đo thật 14/08. Số đo toàn bộ trong [`docs/sensor-characterization.md`](../../docs/sensor-characterization.md).

| Điều kiện | fps | Độ trễ end-to-end | Ghi chú |
|---|---|---|---|
| Nguồn: node stream, không suy luận | 20.3 | — | đo 14/08, 30s liên tục |
| Cảnh trống (trần nhà), có suy luận | 22.8 | _chưa đo_ | 5.5 phút, 7509 frame, 0 lần đọc hỏng |
| **Có người thật trong khung**, có suy luận | **8.7** | _chưa đo_ | phát hiện 343/347 frame = **99%**, đủ 33 landmark |
| Có người, **stream thuần không suy luận** | 23.9 | — | để so sánh |

**Suy luận là nút thắt, không phải camera hay WiFi.** Hai dòng cuối nói rõ: cùng cảnh có người, stream thuần chạy 23.9 fps nhưng gắn suy luận vào còn 8.7 fps.

Rất dễ hiểu ngược chỗ này. Con số 22.8 fps đo với trần nhà trống trông như bằng chứng "suy luận rẻ" — **không phải**. Không có gì để phát hiện thì model thoát sớm; có người thật thì phải chạy đủ hồi quy 33 landmark. **Số đo trên cảnh trống không nói gì về chi phí suy luận** và không được dùng làm ngân sách hiệu năng.

8.7 fps vẫn thừa cho quan sát tư thế ngủ — người đổi tư thế theo đơn vị giây, không phải mili-giây.

Về độ trễ: script đặt `CAP_PROP_BUFFERSIZE = 1`, nhưng backend FFMPEG của OpenCV có thể làm ngơ tuỳ chọn này. Nếu thấy hình trễ vài giây so với thực tế thì đó là lý do — **đo và ghi con số vào bảng trên**, đừng im lặng bỏ qua.

## Không chạy trên Jetson

`mediapipe` **không có wheel aarch64 chính thức** trên PyPI. Đừng `pip install` script này trên Orin rồi kết luận là hỏng. Chi tiết rủi ro và nguồn: mục vision pipeline trong [`docs/system-architecture.md`](../../docs/system-architecture.md).
