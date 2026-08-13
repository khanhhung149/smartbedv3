# Phase 05 — Camera + Edge-AI → **PROTOTYPE (release được từ đây)**

- **Ưu tiên:** P2
- **Trạng thái:** chưa bắt đầu
- **Ước lượng:** 5-6 tuần
- **Rủi ro:** trung bình (kỹ thuật khó, nhưng không gây thương tích)
- **Phụ thuộc:** Phase 01 (dữ liệu), Phase 04 (để có cái mà điều khiển)

> **Michael chốt 13/07: xong Phase 05 là có PROTOTYPE — release được.** Phase 06-07 là nâng cấp, không chặn việc ra mắt.

## Mục tiêu

Camera nhìn được cơ thể trong bóng tối, từ đó:
1. **Skeleton pose (MediaPipe Pose)** → tự khớp **3 mảng nâng** vào đúng vị trí cơ thể (thay vì người dùng phải tự chỉnh).
2. **rPPG sleep staging** → biết đang ở giai đoạn ngủ nào (Wake / Light / Deep / REM).

Đây là phần "thông minh" thật sự của giường, nhưng nó chỉ có giá trị khi Phase 01-04 đã đứng vững.

## Model: MediaPipe Pose (chốt 13/07)

Michael chốt **MediaPipe Pose**, chạy trên **GPU của Jetson Orin**.

Lý do: bài toán này "trên mạng 20 năm rồi, không phải mới". Không sáng tạo lại. Nạp source camera vào module, nó ra skeleton. Việc thật sự phải làm nằm ở **bước sau**: từ skeleton tính **ma trận khoảng cách giữa các điểm khớp** → từ ma trận đó suy ra tư thế ngủ.

Đây là chỗ Hưng phải tự làm — phần model là đồ có sẵn, phần suy luận tư thế mới là giá trị.

## Cơ sở khoa học (từ literature review trong spec, đều khả thi)

- **Sleep staging bằng camera rPPG:** nghiên cứu HealthBed đạt accuracy 81% cho phân loại 3 lớp và 68% cho 4 lớp, trong điều kiện gần như tối. Ngang với thiết bị đeo. Đây là bằng chứng đủ mạnh để làm.
- **Depth camera cho tư thế ngủ:** nghiên cứu multiparameter sleep monitoring bằng camera độ sâu phát hiện được đầu và thân, nhịp thở, tư thế, không tiếp xúc.

## Chọn camera

| Loại | Ưu | Nhược | Quyết định |
|---|---|---|---|
| RGB + IR illuminator | Rẻ, làm được cả pose lẫn rPPG | rPPG trong tối khó | **Chọn cho v3.** IR 850nm chiếu sáng, cảm biến bỏ filter IR |
| Depth (ToF, RealSense) | Pose rất chuẩn, không cần ánh sáng | Đắt, không làm được rPPG | Cân nhắc thêm nếu pose từ RGB không đủ |
| Thermal | Thấy người trong tối tuyệt đối, không xâm phạm | Đắt, độ phân giải thấp, không rPPG | Bỏ ở v3 |

## Quyền riêng tư (không được xem nhẹ)

Spec nói đúng hướng nhưng chưa đủ cụ thể. Nguyên tắc cứng cho v3:

1. **Không bao giờ lưu ảnh hay video ra đĩa.** Frame xử lý xong trong RAM rồi vứt.
2. Chỉ lưu **vector đặc trưng** (toạ độ 17 điểm skeleton, chuỗi tín hiệu rPPG). Từ vector không dựng lại được mặt người.
3. Toàn bộ inference chạy **trên thiết bị**. Không stream ảnh lên cloud, kể cả khi người dùng đồng ý.
4. Nắp che camera vật lý, trượt tay được. Người dùng nhìn thấy nó đóng thì tin là nó đóng.
5. Đèn LED phần cứng nối trực tiếp nguồn camera, sáng khi camera có điện. Không điều khiển được bằng phần mềm.

## Chức năng

### 1. Skeleton pose → khớp mảng nâng
- **MediaPipe Pose** chạy trên **GPU Jetson Orin**.
- Từ skeleton suy ra chiều cao, vị trí vai/hông/đầu gối.
- **Tính ma trận khoảng cách giữa các điểm khớp** → đây là đầu vào cho phân loại tư thế.
- Ánh xạ sang **3 mảng nâng**: mảng nào đỡ đầu/thân trên, mảng nào đỡ thân, mảng nào đỡ chân — theo vóc dáng từng người.
- Chạy khi người mới nằm xuống, không cần chạy liên tục cả đêm (tiết kiệm điện, giảm nhiệt).

### 2. Phân loại tư thế ngủ
Michael liệt kê các lớp cần detect: **nằm ngửa, nghiêng trái, nghiêng phải, nằm sấp, nghiêng nửa, co chân, dang tay, cong người**.

> "Cái gì detect được thì cứ để vô." — thu thập tất cả, kể cả tư thế chưa dùng tới. Đúng nguyên tắc framework: developer sau này có thể cần.

Dùng cho Phase 06 (chống ngáy: ngáy thường nặng khi nằm ngửa).

### 3. rPPG sleep staging
- Trích tín hiệu mạch từ thay đổi màu da vùng mặt/cổ.
- Tính biến thiên nhịp tim (HRV) → phân loại giai đoạn ngủ.
- Đối chiếu với nhịp tim từ radar (Phase 01) để kiểm chứng chéo.

## Việc phải làm

1. Lắp camera + đèn IR, test chất lượng ảnh trong tối thật (phòng đóng kín, 0 lux).
2. Chạy **MediaPipe Pose** trên Jetson GPU, đo FPS và độ chính xác trên người nằm đắp chăn. **Người đắp chăn là ca khó nhất**, phải test sớm.
3. Từ skeleton → **ma trận khoảng cách các điểm khớp** → phân loại tư thế (8 lớp liệt kê ở trên).
4. Ánh xạ skeleton sang **3 mảng nâng**, test với nhiều vóc dáng khác nhau (cao, thấp, gầy, mập).
5. Pipeline rPPG, đối chiếu HRV với radar.
6. Thực thi đầy đủ 5 nguyên tắc riêng tư, kiểm tra bằng cách lục ổ đĩa xem có ảnh nào lọt ra không.

## Định nghĩa hoàn thành — ĐÂY LÀ MỐC PROTOTYPE

- [ ] Pose chạy được trong tối (0 lux) với đèn IR
- [ ] Nhận đúng skeleton khi người đắp chăn (ít nhất phần đầu, vai, thân)
- [ ] Phân loại được ít nhất 4 tư thế cơ bản (ngửa / nghiêng trái / nghiêng phải / sấp)
- [ ] Ánh xạ 3 mảng nâng đúng với ít nhất 5 người có vóc dáng khác nhau
- [ ] Sleep staging 3 lớp đạt accuracy trên 70% khi so với nhãn tay (chưa cần bằng con số 81% của paper)
- [ ] Lục toàn bộ ổ đĩa: không tìm thấy một file ảnh/video nào
- [ ] Che camera vật lý hoạt động, LED phần cứng sáng đúng
- [ ] **PROTOTYPE chạy end-to-end: cảm biến → thuật toán → môi trường → cơ khí → camera. Demo được.**

## Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Chăn che hết cơ thể, pose vô dụng | Ca thường gặp nhất, phải test tuần đầu. Nếu thất bại thì chuyển hướng: dùng loadcell 4 góc để suy ra phân bố trọng lượng và vị trí cơ thể, kết hợp radar. Đây là phương án dự phòng thật sự khả thi |
| rPPG trong tối bằng đèn IR khó hơn nhiều so với paper (paper dùng ánh sáng môi trường) | Chấp nhận độ chính xác thấp hơn. Nếu không đạt thì bỏ rPPG, dùng nhịp tim từ radar để suy sleep stage (kém chính xác hơn nhưng vẫn dùng được) |
| Người dùng không tin lời hứa riêng tư | Nắp che vật lý + LED phần cứng + tài liệu công khai giải thích. Niềm tin không mua được bằng lời nói suông |
