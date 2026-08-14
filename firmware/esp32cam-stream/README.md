# esp32cam-stream/ — ESP32-CAM (AI-Thinker, OV2640)

Board chụp ảnh và phục vụ **MJPEG stream qua HTTP trong LAN**. Hết. Không SD, không I2C, không NTP, không MQTT.

Nó tồn tại để laptop chạy MediaPipe Pose nhìn thấy hình **trực tiếp**, thay vì phải rút thẻ nhớ ra xem như node `esp32cam-node` trước đây. Quyết định đầy đủ: [`plans/260814-1237-esp32cam-stream-mediapipe-poc/`](../../plans/260814-1237-esp32cam-stream-mediapipe-poc/plan.md).

## ⚠️ Chỉ dùng cho bench-test

**Không bao giờ chạy node này khi có người thật nằm trên giường.** Đây là ranh giới của hazard **H-25** trong [`docs/safety/hazard-analysis.md`](../../docs/safety/hazard-analysis.md).

Hai điều cần biết:

- **Stream không có xác thực.** Bất kỳ thiết bị nào cùng LAN mở được `http://<ip>/` đều xem được. Dùng mạng bench cách ly. Tắt nguồn board khi không chạy thử.
- **Không có gì được lưu lại.** Firmware không có tầng lưu trữ — không SD, không filesystem, không `fopen`. Frame chỉ tồn tại trong lúc truyền và mất khi tắt nguồn. Đó là lý do H-25 không cần cờ build nào cả: không có đường ghi đĩa để tắt.

Nếu ai đó thêm SD hay bất kỳ đường ghi file nào vào node này, H-25 phải được viết lại trước.

## Phần cứng

Chỉ có camera. Không cắm gì thêm.

| | |
|---|---|
| Board | AI-Thinker ESP32-CAM (có 4MB PSRAM — **bắt buộc**) |
| Camera | OV2640, bus SCCB nội bộ GPIO26/27 (không ra header) |
| Nguồn | **5V/2A riêng.** Không lấy từ cổng USB laptop hay Jetson |

**Đừng cắm thiết bị I2C vào GPIO4.** Trên AI-Thinker, GPIO4 nối thẳng đèn flash trắng — mọi giao dịch I2C ở đó làm đèn nhấp nháy suốt đêm, không tắt được bằng firmware. Đó là hazard H-26 cũ, đã nghỉ hưu cùng lúc VL53L0X bị bỏ khỏi thiết kế (xem mục "Retired hazards" trong hazard-analysis). Cắm lại là hazard sống lại.

Về nguồn: đây không phải lời khuyên chung chung mà là quy tắc phần cứng của dự án (**H-20**). Camera cộng WiFi TX kéo dòng đỉnh cao; thiếu dòng gây brownout trông y hệt bug phần mềm và tốn nhiều ngày để truy sai hướng.

## Chạy

```bash
cp include/config.h.example include/config.h   # rồi điền SSID + mật khẩu thật
pio run -t upload -e esp32cam
pio device monitor
```

`config.h` bị `.gitignore` chặn (`firmware/**/config.h`) — mật khẩu không bao giờ vào git. Kiểm tra bằng `git check-ignore -v include/config.h`.

AP phải là **2.4GHz** — ESP32 không bắt được 5GHz. Sai băng tần thì log báo hết 10 lần thử rồi dừng, không reboot loop.

Serial in ra IP lúc boot:

```
======================================
  Đã có IP: 192.168.1.42
  Trình duyệt : http://192.168.1.42/
  PoC Python  : http://192.168.1.42:81/stream
======================================
```

## Hai cổng, không phải hai route

| | Route | Trả về |
|---|---|---|
| **:80** | `GET /` | Trang HTML tối giản để kiểm tra bằng mắt |
| **:81** | `GET /stream` | `multipart/x-mixed-replace` MJPEG, chạy tới khi client ngắt |

Đây là **hai HTTP server riêng, hai task riêng** — không phải hai route trên cùng một server. Lý do: `esp_http_server` xử lý request trong *một* task, mà handler stream chạy vô hạn nên nó chiếm trọn task đó và mọi request khác chờ vô thời hạn.

Đo thật trên board (14/08), bản một-cổng ban đầu:

| | `GET /` khi rảnh | `GET /` khi đang stream |
|---|---|---|
| Một cổng (bản đầu) | 0.06s | **timeout** |
| Hai cổng (bản hiện tại) | 0.05s | **0.03s** |

Chế độ hỏng của bản một cổng rất khó chịu: mở trình duyệt xem thử rồi chạy PoC thì PoC treo vĩnh viễn, không báo lỗi gì. Đây cũng là cách ví dụ `esp32-camera` chính thức của Espressif làm.

**Đừng gộp `/stream` về cổng 80 cho "gọn".**

Giới hạn còn lại: **một client stream tại một thời điểm**. Tách cổng chỉ giải quyết trang-vs-stream; hai chương trình cùng đọc `/stream` thì chương trình thứ hai không nhận được dữ liệu. Đóng tab trình duyệt trước khi chạy PoC.

## Cấu hình ảnh

VGA 640×480, JPEG quality 12, 2 frame buffer trong PSRAM, `grab_mode = CAMERA_GRAB_LATEST`.

VGA chứ không phải SVGA như node cũ: MediaPipe Pose resize ảnh về 256×256 trước khi suy luận, nên độ phân giải cao hơn **không** cho landmark chính xác hơn — chỉ tốn băng thông WiFi và làm fps tụt.

`GRAB_LATEST` nghĩa là khi WiFi nghẽn, firmware bỏ frame cũ thay vì xếp hàng. Người xem stream cần thấy hiện tại, không cần thấy đủ mọi frame.

## fps đo được

Đo thật 14/08 trên board đã nạp, đếm marker JPEG phía client trong 30 giây liên tục.

| Điều kiện | fps | Kích thước frame | Băng thông |
|---|---|---|---|
| Cảnh trống (trần nhà) | 20.3 | 10.0 KB (9.9–10.1) | 204 KB/s = 1.67 Mbit/s |
| **Có người trong khung** | **23.9** | **15.7 KB** (11.6–17.2) | 378 KB/s = 3.10 Mbit/s |
| Đồng thời phục vụ trang ở cổng 80 | 23.2 | — | — |

Có người trong khung làm mỗi JPEG **nặng hơn 57%** (10.0 → 15.7 KB) và dao động nhiều hơn hẳn, vì có chi tiết thật để mã hoá thay vì mảng tường phẳng. Bản thân node không chậm đi.

Số đo đầy đủ, gồm cả chi phí suy luận pose: [`docs/sensor-characterization.md`](../../docs/sensor-characterization.md).

Để so sánh: node `esp32cam-node` cũ đạt ~1.5 fps ở SVGA khi ghi xuống thẻ SD. Nút thắt cổ chai trước đây là thẻ nhớ, không phải camera hay WiFi.

## Định dạng stream — vì sao MJPEG

`multipart/x-mixed-replace` là định dạng **duy nhất** mà `cv2.VideoCapture(url)` đọc thẳng được, không cần client riêng. RTSP và WebRTC trên ESP32 đều cần thư viện nặng hơn nhiều; đã loại ở giai đoạn brainstorm.

Boundary là `frame`, phải khớp ba chỗ: `Content-Type` của response, chuỗi phân cách giữa các frame, và kỳ vọng của client. Lệch một ký tự thì client treo mà không báo lỗi gì.

## Không nhầm với `firmware/camera-node/`

Đó là placeholder cho camera **Phase 05** gắn thẳng Jetson Orin — thiết bị khác, giai đoạn khác. Thư mục này không liên quan và không nên trở thành nó.

## Toolchain

`framework = espidf` thuần, `platform` **ghim** ở `espressif32@55.3.311`. Đừng bỏ ghim version: espidf thuần là trường hợp dễ vỡ nhất khi platform trôi. `upload_speed = 115200` cũng có lý do — 460800 mặc định gây `Serial data stream stopped: possible noise` trên kết nối USB-TTL thật.

`sdkconfig.esp32cam` được sinh lại từ `sdkconfig.defaults` mỗi lần build và bị gitignore. Chỉ sửa `sdkconfig.defaults`.
