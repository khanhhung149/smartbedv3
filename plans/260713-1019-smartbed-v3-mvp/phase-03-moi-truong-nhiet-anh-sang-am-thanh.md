# Phase 03 — Môi trường: nhiệt, ánh sáng, âm thanh

- **Ưu tiên:** P1
- **Trạng thái:** chưa bắt đầu
- **Ước lượng:** 3 tuần
- **Rủi ro:** thấp
- **Phụ thuộc:** Phase 02 (cần biết người đang ngủ hay thức để điều chỉnh)
- **Chạy song song được với:** Phase 04

## Mục tiêu

**Sản phẩm bán được thứ hai:** pod tự điều hoà môi trường ngủ. Giường không chỉ đo, mà bắt đầu tác động lên giấc ngủ. Vẫn không có bộ phận nào đè lên người, rủi ro vẫn thấp.

Ba yếu tố này đều có literature chống lưng ngay trong spec: nhiệt độ ảnh hưởng trực tiếp tới điều nhiệt cơ thể và chu kỳ ngủ; white noise/nhạc dễ chịu làm giảm thời gian vào giấc và tăng spindle; ánh sáng điều chỉnh nhịp sinh học.

## Chức năng

> Cập nhật 13/07: giữ **máy lạnh monoblock** nhưng bắt buộc tìm loại **ít ồn**. LED dùng **WLED**. Âm thanh: **1 cặp loa 2.0**, nhạc từ thầy Nguyên Minh Thiền Sư. Thông gió: **quạt hút 12V + màng che**. Ion âm: **nên có**.

### 1. Nhiệt (giá trị cao nhất trong ba cái)
- **Máy lạnh monoblock** điều khiển qua relay/Modbus. Michael chốt giữ monoblock (search "monoblock air conditioner"), nhưng **phải chọn loại ít ồn** — đây là ràng buộc mua hàng, không phải mong muốn.
- Vòng kín: đọc SHT (nhiệt độ + độ ẩm khoang) và MLX90614 (thân nhiệt) → điều chỉnh.
- **Đường cong nhiệt theo pha ngủ:** hạ nhiệt độ khi bắt đầu vào giấc (giúp thân nhiệt lõi giảm, cơ chế sinh lý của việc buồn ngủ), giữ mát trong đêm, ấm dần lại trước giờ dậy.
- Ràng buộc an toàn: giới hạn cứng 18-30°C, không bao giờ vượt bất kể thuật toán nói gì. Hysteresis chống bật/tắt liên tục (đã có bài học từ project autogate với quạt Proxmox).

### 2. Ánh sáng

**Dùng WLED, không tự viết driver LED.** (Michael chốt 13/07.)

- **1 dải LED RGB** chạy quanh khoang. Flash WLED (có flash online, cắm chip vào bấm 1 cái là xong). Chạy được cả trên ESP8266/ESP-01.
- **Vì sao WLED thay vì tự code:** thuật toán chuyển màu/hiệu ứng của WLED vượt xa những gì tự viết trong thời gian hợp lý. Chuyển mượt từ màu này sang màu kia qua dải trung gian là bài toán khó — WLED giải xong rồi. Điều khiển qua API. Nặng hơn một chút, không đáng kể.
- Mục tiêu thiết kế: **nhìn từ xa phải đẹp** (LED viền), **lại gần phải dịu** (ánh sáng êm, không chói).
- Tối dần theo lịch đi ngủ, tắt hẳn khi phát hiện đã ngủ.
- Đèn báo thức: sáng dần 20-30 phút trước giờ dậy, ưu tiên đánh thức ở giai đoạn ngủ nông (khi có Phase 05 sleep staging thì làm chuẩn hơn; Phase 03 tạm dùng chuyển động/trở mình để đoán).
- Đèn đêm đỏ mờ khi phát hiện `LEAVING` lúc nửa đêm (đi vệ sinh), không bật trắng chói.
- **Chỉ dùng pattern ánh sáng đã được khoa học chứng minh** (light therapy, circadian). Không tự chế bước sóng/hiệu ứng theo cảm tính.

### 3. Âm thanh
- **1 cặp loa 2.0.** Bỏ dàn 5.1 Denon trong spec. Loa có sẵn trong kho (hầm nhà Michael: Bose / Marshall / Ultimate Ears) — dùng trước, không mua mới.
- **Thư viện nhạc ngủ: lấy từ YouTube của thầy Nguyên Minh Thiền Sư** — chuyên gia hàng đầu VN về y học giấc ngủ, sáng tác nhạc chuyên trị giấc ngủ. Dùng background của thầy làm bảo chứng khoa học cho tính năng ("tại sao nhạc này giúp ngủ ngon?" → có câu trả lời, không phải tự nghĩ ra).
  - ⚠️ **Chưa xin phép bản quyền** — phải xử lý trước khi release.
- White noise / pink noise / nhạc dễ chịu, fade out sau khi ngủ.
- Tự giảm âm lượng khi phát hiện đã ngủ sâu.
- Bonus rẻ tiền, giá trị cao: khi phát hiện **ngáy** (từ Phase 02), phát một tiếng động nhẹ (hoặc rung) để người ngủ đổi tư thế. Đây là mẹo đã được dùng trong các sản phẩm anti-snoring, làm được ngay mà chưa cần actuator.

### 4. Thông gió + CO₂ (bắt buộc, không phải tuỳ chọn)

Spec hoàn toàn không nhắc tới CO₂. Đây là lỗ hổng nghiêm trọng: một người ngủ 8 tiếng trong khoang kín cách âm sẽ tích tụ CO₂ tới mức gây đau đầu, ngủ không sâu, và ở mức cao hơn là nguy hiểm.

Thiết kế chốt 13/07:
- **Quạt hút nhỏ (12V)** + **màng che**. Mặc định màng đóng, quạt không chạy.
- **Cảm biến CO₂** (NDIR, ví dụ SCD40/SCD41) trong khoang. Michael: "sau này mới thật cần" — nhưng nên có ngay, vì không có nó thì quạt không biết khi nào phải chạy.
- CO₂ vượt ngưỡng → mở màng + hút đẩy. Vượt 1000ppm: tăng quạt. Vượt 2000ppm: quạt tối đa + cảnh báo + mở khoá cửa.
- **Phần mềm chỉ được phép TĂNG tốc quạt, không được phép tắt.** Đây là ràng buộc an toàn, không phải tuỳ chọn thiết kế.
- Đây cũng là hạ tầng bắt buộc nếu sau này muốn mở lại module oxy (xem Phase 07).

### 5. Máy ion âm — NÊN CÓ (chốt 13/07)

Thay cho máy tạo oxy y tế (đã cắt): **máy tạo ion âm rẻ, cục nhỏ xíu, không làm tăng nồng độ oxy nên không gây rủi ro cháy.** Literature trong spec: ion âm rút ngắn thời gian vào giấc và kéo dài giấc ngủ sóng chậm.

Michael: đây chính là cơ chế thật đằng sau mẹo dân gian "để con dao dưới gối cho ngủ ngon" — kim loại lạnh ban đêm phóng thích ion. Không có gì huyền bí.

**Lưu ý:** ion âm ≠ máy tạo oxy. Quyết định **cắt máy tạo oxy** vẫn giữ nguyên (xem Phase 07).

## Việc phải làm

1. **Tìm + mua máy lạnh monoblock loại ít ồn.** Đo dB thật khi nhận hàng, không tin datasheet. Hạn 25/07.
2. Driver điều khiển máy lạnh (relay hoặc Modbus tuỳ model thật mua được).
3. Bộ điều khiển nhiệt có hysteresis + giới hạn cứng. Giới hạn nhiệt phải nằm ở **tầng thấp nhất** (không cho thuật toán tầng trên ghi đè).
4. **Flash WLED lên ESP8266/ESP32**, nối dải LED RGB, điều khiển qua API. Dựng scene ánh sáng.
5. Phát âm thanh + thư viện soundscape + nhạc thầy Nguyên Minh (xin phép bản quyền trước).
6. Quạt hút 12V + màng che + cảm biến CO₂.
7. Máy ion âm (rẻ, lắp sớm).
8. Bộ luật đơn giản (rule engine) nối trạng thái giấc ngủ với các tác động trên. Chưa cần AI, if-then là đủ và dễ debug. **Nhưng viết dưới dạng contract mở** — Phase 06 sẽ thay rule engine này bằng AI intent-based, đừng hard-code.
9. Đo hiệu quả: 5 đêm có bật điều hoà môi trường và 5 đêm không, so thời gian vào giấc và số lần thức giấc từ dữ liệu Phase 02.

## Định nghĩa hoàn thành

- [ ] Nhiệt độ khoang giữ trong khoảng đặt ±1°C, không dao động bật/tắt quá 4 lần/giờ
- [ ] Giới hạn cứng 18-30°C không thể bị ghi đè bằng phần mềm tầng trên (verify bằng cách cố tình gửi lệnh 35°C)
- [ ] Đèn báo thức sáng dần đúng lịch
- [ ] Phát hiện ngáy kích hoạt được phản hồi âm thanh nhẹ
- [ ] CO₂ trong khoang không vượt 1000ppm suốt đêm khi có người ngủ với cửa đóng
- [ ] Quạt thông gió không thể bị phần mềm tắt (verify bằng cách cố gửi lệnh tắt)
- [ ] Có số liệu so sánh 5 đêm có/không, dù kết quả là gì cũng phải ghi lại

## Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Máy lạnh monoblock ồn 55dB (theo spec) trong buồng "soundproof" là mâu thuẫn chết người | **Michael chốt: giữ monoblock nhưng phải tìm loại ít ồn.** Đây là ràng buộc mua hàng. Nếu không mua được loại đủ êm: đặt máy lạnh ngoài khoang, dẫn khí vào qua ống tiêu âm. Nếu vẫn ồn thì đổi sang Peltier hoặc nước làm mát, chấp nhận công suất thấp hơn |
| Bản quyền nhạc thầy Nguyên Minh | Xin phép trước khi release. Michael quen thầy — xử lý ở tầng quan hệ, nhưng phải có văn bản |
| Ngưng tụ nước trong khoang khi làm lạnh | Theo dõi độ ẩm, có đường thoát nước, cảnh báo khi vượt ngưỡng |
| Người dùng thấy lạnh nhưng thuật toán nghĩ là đúng | Luôn có nút ghi đè bằng tay, ưu tiên tuyệt đối so với thuật toán |
