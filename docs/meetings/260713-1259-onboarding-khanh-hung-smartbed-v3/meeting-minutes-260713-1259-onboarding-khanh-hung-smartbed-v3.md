# Biên bản — Onboarding Cao Huỳnh Khánh Hưng + Review plan SmartBed v3

- **Ngày:** 2026-07-13, 12:59 → 13:51 (SGT), 52 phút
- **Meet code:** `xvk-oxqt-fod`
- **Người tham dự:** Michael (Sơn), Hưng (Cao Huỳnh Khánh Hưng — KS điện tử, ngày đầu đi làm)
- **Nội dung:** Michael review trực tiếp bản master plan SmartBed v3 (viết sáng 13/07) và sửa spec ngay trên buổi họp
- **Nguồn:** meeting-assistant API, transcript đầy đủ tại `transcript-260713-1259-*.md`
- **Ghi chú:** Michael có ghi âm để đưa lại cho "bạn tiếp theo" → sẽ có thêm 1 người nữa vào team

---

## 1. Tầm nhìn sản phẩm — thay đổi lớn nhất

> "Mục tiêu của anh không phải làm một sản phẩm để bán, mà làm một **framework**."

SmartBed = một nền tảng với nhiều thông số đầu vào + nhiều lệnh điều khiển đầu ra, **mở ra cho developer** tự phát triển chức năng gắn vào. Mô hình App Store.

Hệ quả trực tiếp lên kỹ thuật:
- **Thu thập TẤT CẢ data**, kể cả data chưa dùng tới. Vì developer sau này có thể cần.
- Kiến trúc phải là **API/contract mở**, không phải app đóng.
- Về sau: AI học thói quen từ data → chế độ **autopilot** (bấm 1 nút, AI lo hết).
- **Moonshot:** public ~100 template mẫu (khó ngủ, đau đầu, sáng thức dậy, mới vào giấc…). Developer up template lên GitHub, người dùng bấm 1 cái trên tablet là load về. **Template là văn bản, không phải code** — AI convert sang logic hệ thống. Có long-term + short-term memory.
- **Bỏ Home Assistant + Node-RED.** Automation dựa trên AI hiểu intent, không phải người kéo-thả.

Mô hình intent-based đã được Michael chứng minh chạy thật tại nhà (nói "sáng quá", "hơi nóng" → AI hiểu ý định theo ngữ cảnh → tự chỉnh đèn + máy lạnh). Sẽ truyền lại cho Hưng.

---

## 2. Quyết định kỹ thuật (chốt trong buổi)

### Tính toán & nền tảng
| Hạng mục | Chốt | Ghi chú |
|---|---|---|
| MCU | **ESP32 duy nhất** — bỏ STM32 | Thống nhất toolchain. Được dùng nhiều biến thể ESP32 |
| AI / bộ não | **Jetson Orin** (đã có sẵn thiết bị) | |
| Coral USB | **BỎ** | |
| Backend deploy | **K8s** (không phải K3s) | |
| App | **Flutter** (Android + iOS) | |
| Màn hình | **iPad nhỏ / tablet Android rẻ** — bỏ LCD 45" | |

### Cảm biến
| Cảm biến | Chốt |
|---|---|
| Radar hiện diện | **Nâng LD2410B → LD2510B** — track được nhiều người cùng lúc + vị trí thật (2410 chỉ cho khoảng cách gần đúng). Gắn trên đầu chiếu xuống |
| Load cell | **BỎ → thay bằng Piezoelectric pad** |
| Nhiệt độ / độ ẩm môi trường | Giữ |
| Camera nhiệt | Giữ |
| Mic | **Mic đa hướng** (cái Quân vừa đưa), gắn đầu giường — KHÔNG phải mic định hướng |
| MAX30102 (SpO2) | **Để sau** — phải chạm vào người |
| Huyết áp | **Để sau** |
| Nồng độ cồn (MQ303B) | **Để sau** |

### Vision
- **MediaPipe Pose** (không phải YOLO). Xử lý trên GPU.
- Ra ma trận khoảng cách giữa các điểm khớp → phân loại tư thế: nằm ngửa, nghiêng trái, nghiêng phải, nằm sấp, co chân, dang tay, nghiêng nửa…
- "Cái này trên mạng 20 năm rồi, không phải mới" — không cần sáng tạo lại.

### Cơ khí — thay đổi lớn
- **10 điểm nâng → 3 mảng:** 1 mảng trên (nâng đầu), 1 mảng giữa rộng, 1 mảnh nhỏ dưới (nâng chân).
- Cung độ **nhỏ**, tốc độ **chậm**, độ ồn **thấp**.
- 10 điểm → để sau (không nằm trong MVP).
- **✅ Người phụ trách cơ khí: anh Khanh.** Đây là blocker số 1 của plan cũ — đã gỡ.
- **Handler module bắt buộc:** cơ khí phải có một module quản trị riêng. Mọi thứ khác chỉ giao tiếp qua handler đó. **Cơ chế safety nằm trong handler** (tự chặn khi data dồn quá, chạy quá giới hạn…).
- **Position feedback bắt buộc:** phải biết đang ở vị trí nào (%), không chỉ biết "đang chạy".
- Michael chia sẻ pattern auto-calibrate từ hệ cửa nhà anh: nếu motor **tự dừng** (không phải người ra lệnh) ở vùng <15% gần đầu mút → coi đó là điểm giới hạn, tự sync vị trí. Không cần công tắc hành trình, không cần calibrate thủ công.

### Môi trường
| Hạng mục | Chốt |
|---|---|
| Nhiệt | **Máy lạnh monoblock** — giữ, nhưng phải tìm loại **ít ồn** |
| Ánh sáng | **1 dải LED RGB**, dùng **WLED** (flash online, chạy được cả trên ESP8266/ESP-01). Lý do dùng WLED thay vì tự code: thuật toán chuyển màu mượt của nó vượt xa tự viết |
| Âm thanh | **1 cặp loa 2.0** (loa có sẵn ở hầm nhà Michael — Bose / Marshall / Ultimate Ears). Bỏ Denon 5.1 |
| Nội dung nhạc | Lấy từ YouTube **thầy Nguyên Minh Thiền Sư** — chuyên gia hàng đầu VN về y học giấc ngủ, sáng tác nhạc ngủ. Dùng uy tín/background của thầy làm bảo chứng khoa học |
| Thông gió | **Quạt hút nhỏ (12V)** + màng che. Mặc định đóng, mở khi CO2 vượt ngưỡng |
| Cảm biến CO2 | Nên có, "sau này mới thật cần" |
| Máy ion âm | **Nên có** — rẻ, có cơ sở giúp ngủ ngon |

**Lưu ý:** máy ion âm ≠ máy tạo oxy. Quyết định **CUT máy tạo oxy** (13/07) vẫn giữ nguyên — không nhắc lại trong buổi họp, coi như đã chốt.

### Ánh sáng — cơ sở lý thuyết Michael đưa ra
Bước sóng ánh sáng khác nhau tác động khác nhau lên sóng não (cộng hưởng). Ánh sáng là phương pháp trị liệu thật (light therapy). Nhưng: **chỉ dùng pattern đã được khoa học chứng minh, không tự chế.**

---

## 3. Phase — cấu trúc mới

Michael chốt: **7 phase, nhưng release được từ phase 5.**

Cấu trúc phase đi theo thứ tự anh trình bày trong buổi:
1. Cảm biến (bỏ những cái gạch chéo, giữ những cái đã chốt ở trên)
2. Thuật toán
3. Môi trường (nhiệt, LED, âm thanh, thông gió)
4. Cơ khí (3 mảng + handler + position feedback) — với anh Khanh
5. Camera / pose / tư thế ngủ → **prototype ở đây**
6. App + profile
7. AI / autopilot / template platform → để sau

---

## 4. Cách làm việc — Michael đặt kỳ vọng với Hưng

> "Anh sẽ hạn chế nhúng tay vô. Anh sẽ hỗ trợ, cung cấp đầy đủ tài nguyên và hướng dẫn em cách làm, **nhưng em phải tự làm hết**."

Lý do Michael đưa ra: xem người khác làm thì tưởng mình biết, thực ra chưa biết gì. Phải tự tay làm mới thành kỹ năng thật.

Bối cảnh dài hạn: Michael muốn trong 4-5 năm truyền hết được cho 4-5 người làm được y như mình, để không mai một kiến thức.

**Ràng buộc duy nhất với Hưng:** token AI (Michael đang dùng 3 gói max, vẫn hit limit — có thiết bị tự track usage).

**Đã bàn giao trong buổi:** bộ đồ nghề hàn mạch + linh kiện. Michael dặn: **luôn cấp nguồn riêng cho mạch, không lấy nguồn từ laptop** (kinh nghiệm: sụt áp gây lỗi random rất khó debug).

---

## 5. Action items

| Việc | Owner | Deadline | Kết quả kỳ vọng |
|---|---|---|---|
| Cập nhật master plan theo các quyết định trên | Michael/Claude | 13/07 | ✅ Đã làm |
| Gửi Hưng list linh kiện + tài nguyên đã hứa trong buổi | Michael | 14/07 | "chút anh sẽ gửi lại cho em" |
| Đặt mua LD2510B (thay LD2410B) | Hưng | 18/07 | |
| Đặt mua Piezoelectric pad (thay load cell) | Hưng | 18/07 | |
| Tìm máy lạnh monoblock **loại ít ồn** | Hưng | 25/07 | Có số đo dB, không tin datasheet |
| Kết nối Hưng ↔ anh Khanh (cơ khí) | Michael | 18/07 | Brief 3 mảng + handler + position feedback |
| Setup ESP32 toolchain + flash WLED thử trên ESP8266 | Hưng | 18/07 | |
| Bàn giao pattern intent-based AI + MQTT stack từ nhà Michael | Michael | Khi tới phase AI | |

---

## 6. Câu hỏi chưa giải quyết

1. **"Bạn tiếp theo" là ai?** Michael ghi âm buổi này để đưa cho người kế tiếp — Khoa Nguyên (85đ) có được offer không?
2. Anh Khanh là ai (in-house / ngoài / đối tác), scope và chi phí phần cơ khí?
3. Site pilot — vẫn chưa nhắc tới trong buổi. Mốc "pod tại site thật sau 3 tháng" còn giữ không, hay tầm nhìn framework đã thay đổi mục tiêu?
4. Ngân sách BOM v3 — vẫn chưa có con số.
5. Nhạc thầy Nguyên Minh Thiền Sư — đã xin phép sử dụng chưa? (bản quyền)
