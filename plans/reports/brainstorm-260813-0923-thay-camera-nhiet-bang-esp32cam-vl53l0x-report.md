# Brainstorm: Thay cụm "Camera nhiệt / MLX90614" bằng ESP32-CAM (OV2640) + VL53L0X

- **Ngày:** 2026-08-13
- **Bối cảnh:** Hưng đang làm việc #1 Phase 01 (`plans/260713-1019-smartbed-v3-mvp/phase-01-cum-cam-bien-va-data-pipeline.md`) — lắp 5 cụm cảm biến lên bench rig. Trong lúc lắp, đề xuất đổi phần cứng cho 2 cụm.
- **Phạm vi:** Chỉ brainstorm quyết định phần cứng + đường dữ liệu ở mức kiến trúc. Không code, không sửa docs/plan (chưa được cấp phép).

## Đề xuất ban đầu (từ Hưng)

1. "Camera nhiệt thay bằng ESP32-CAM OV2640"
2. "Cảm biến nhiệt SHT thay bằng VL53LDK (ToF LIDAR)"

## Scout — trạng thái gốc trong repo

- Phase 00 BOM (`phase-00-*.md:37-38`) đã **chốt giữ** cả Camera nhiệt VÀ SHT — không phải "chưa quyết", là quyết định đã đóng, chốt cùng Michael trong họp 13/07.
- `plans/reports/schema-defect-analysis-260731-...md` mục 4: cụm "Camera nhiệt / MLX90614" vốn đã có câu hỏi tồn đọng chưa chốt — MLX90614 (cảm biến 1 điểm, ~$5-8) khác hẳn camera nhiệt mảng (MLX90640/FLIR Lepton, ~$50-250). Chưa từng chốt mua món nào.
- Phase 05 (`phase-05-camera-edge-ai.md:38`) đã chốt **riêng** một camera khác cho mục đích khác: RGB+IR illuminator, nối thẳng Jetson, chạy MediaPipe Pose GPU — thermal bị loại ở v3. Có 5 quy tắc riêng tư cứng, trong đó có **"không bao giờ lưu ảnh/video ra đĩa"**.
- Phase 03 (`phase-03-*.md:22`) tiêu thụ MLX90614 (thân nhiệt) cho vòng kín điều hoà môi trường.
- Nguyên tắc framework toàn dự án: **"Thu thập TẤT CẢ data, không cắt cảm biến chỉ vì chưa dùng tới"**.

## Đánh giá thẳng 2 đề xuất gốc

- **OV2640 không đo được nhiệt độ** — không có điểm chung vật lý với chức năng "thân nhiệt bề mặt" mà cụm gốc đảm nhiệm. Ban đầu nhìn giống nhầm lẫn với camera Phase 05.
- **VL53L0X không đo nhiệt/ẩm** — không có điểm chung với SHT. Hỏi lại mới rõ: không thực sự nhắm thay SHT, mà đi cùng camera.

## Câu hỏi discovery và câu trả lời

1. *Vì sao thay camera nhiệt?* → "Muốn quan sát hành động của người lúc ngủ" — xác nhận mục tiêu thật là quan sát hành vi, trùng phạm vi Phase 05, không phải đo nhiệt.
2. *VL53L0X kết hợp được với ESP32-CAM OV2640 không?* → Được — camera dùng bus DVP song song cho ảnh + bus SCCB (I2C) riêng GPIO26/27 chỉ để cấu hình. VL53L0X gắn chung bus SCCB (địa chỉ `0x29` khác `0x30` của camera), không cần thêm GPIO. Board AI-Thinker ESP32-CAM có rất ít GPIO trống nếu dùng khe SD (chiếm GPIO2,4,12,13,14,15) — dùng chung bus SCCB tránh vấn đề này.
3. *Thay hẳn hay thêm cụm mới?* → **Thay hẳn**, chấp nhận mất kênh thân nhiệt ở Phase 01.
4. *VL53L0X đo gì cụ thể?* → Khoảng cách người–camera, hỗ trợ xử lý ảnh/pose — đi cùng cụm camera, không liên quan SHT.
5. *Video có cần lưu theo DoD Phase 01 (giữ 30 đêm) không?* → **Cần lưu thật** để sau này huấn luyện/debug MediaPipe Pose.

## Quyết định cuối

| Cụm gốc | Cụm mới | Trạng thái |
|---|---|---|
| Camera nhiệt / MLX90614 | **ESP32-CAM (OV2640) + VL53L0X** | Thay hẳn |
| SHT | SHT | Không đổi |
| LD2510B, Piezo pad, Mic | Không đổi | — |

**Kiến trúc:**
- Node camera = MCU riêng (ESP32-CAM tự có ESP32 + camera), không cắm vào sensor-node ESP32 hiện có → **node thứ 6** trong hệ. Vẫn hợp nguyên tắc "1 dòng MCU ESP32, nhiều biến thể".
- VL53L0X dùng chung bus SCCB của camera (GPIO26/27), địa chỉ I2C `0x29`.
- Ghi frame + khoảng cách + timestamp (gắn tại MCU) vào **microSD cục bộ** — không stream WiFi realtime cho luồng ghi chính thức (có thể thêm xem live riêng cho lúc bench-test, không bắt buộc).
- **Ngoại lệ lưu video CHỈ áp dụng giai đoạn kỹ sư tự test (bench rig, chưa có khách hàng)** — không áp dụng khi có người dùng thật, vì ngược quy tắc riêng tư Phase 05. Cần ghi rõ ranh giới này bằng văn bản khi triển khai.
- Nguồn riêng cho ESP32-CAM (đúng quy tắc phần cứng: không lấy nguồn từ laptop).

## Rủi ro / hệ quả chưa giải quyết trong brainstorm này

1. **Phase 03 mất input thân nhiệt** — vòng kín điều hoà môi trường (`phase-03-*.md:22`) dựa vào MLX90614. Cần quyết bù lại bằng cách nào (thêm MLX90614 rời riêng, rẻ, không xung đột — hoặc bỏ hẳn tính năng đó ở Phase 03) — **chưa chốt trong brainstorm này, để hỏi khi làm Phase 03**.
2. **Cần báo lại Michael** — "Camera nhiệt: Giữ" là quyết định chốt chung trong họp 13/07, không phải riêng Hưng. Đảo quyết định này nên thông báo trước khi khoá hẳn vào docs.
3. **Schema DB chưa có chỗ cho video** — schema hiện tại (`t, presence, hr_bpm,...`) là giá trị số theo hàng. Video cần thiết kế riêng (file path + bảng metadata, hoặc thư mục theo đêm) — để `/ck:plan` xử lý chi tiết khi lập plan.
4. **Đảo ngược quyết định BOM đã chốt** — nếu tiếp tục, nên cập nhật `phase-00-*.md:37` (Camera nhiệt: Giữ → Thay) và `phase-01-*.md:28` khi được cấp phép sửa docs.

## Câu hỏi tồn đọng (chưa trả lời trong brainstorm này)

- Có bù lại thân nhiệt cho Phase 03 bằng cách nào không, hay bỏ hẳn tính năng đó?
- Đã báo Michael về việc đảo quyết định "Camera nhiệt: Giữ" chưa?
- Video lưu bao lâu / dung lượng thẻ SD cần bao nhiêu cho 8 tiếng/đêm ở độ phân giải nào (chưa đo, cần chốt khi lập plan)?
