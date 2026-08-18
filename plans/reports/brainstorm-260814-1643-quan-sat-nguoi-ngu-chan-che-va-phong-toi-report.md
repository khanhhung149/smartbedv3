# Brainstorm — Quan sát người ngủ: chăn che và phòng tối

- **Ngày:** 2026-08-14
- **Bối cảnh vào:** PoC `260814-1237-esp32cam-stream-mediapipe-poc` vừa đóng, 99% phát hiện landmark ban ngày
- **Câu hỏi mang vào:** chọn A (đèn IR cho ESP32-CAM) / B (camera IR gắn Jetson) / C (bỏ vision ban đêm, dùng radar+piezo)
- **Kết quả:** câu hỏi được đặt lại. Không chọn 1 trong 3.

---

## 1. Chẩn đoán nhảy-thẳng-tới-giải-pháp

Tín hiệu làm ba lựa chọn kia thành hiển nhiên: PoC chạy tốt ban ngày, và ai cũng thấy ngay OV2640 không có IR. Nên vấn đề **có vẻ** là "thiếu ánh sáng".

Nhưng ba lựa chọn A/B/C đều là câu trả lời cho *"nhìn trong tối bằng gì"*. Không cái nào trả lời câu hỏi lớn hơn nằm bên dưới.

## 2. Vấn đề thật

**Không phải bóng tối. Là cái chăn.**

`phase-05-camera-edge-ai.md` đã tự viết, từ 13/07:

> "Người đắp chăn là **ca khó nhất**, phải test sớm."
> "Chăn che hết cơ thể, pose vô dụng — **ca thường gặp nhất**."

IR giải quyết bóng tối. IR **không** giải quyết cái chăn. Chiếu sáng hoàn hảo tới đâu, người trùm chăn vẫn không có landmark cơ thể để nhìn.

Bóng tối là rào cản có lời giải đã biết và đã chốt. Cái chăn là rào cản **chưa có lời giải**, và nó chặn đúng DoD của mốc PROTOTYPE.

## 3. Ba giả định bị thách thức

| Giả định | Rủi ro nếu sai | Kiểm chứng |
|---|---|---|
| "Giải xong bóng tối là vision dùng được ban đêm" | Sai hoàn toàn. Mua camera IR xong vẫn trượt DoD *"nhận đúng skeleton khi người đắp chăn"* | Test chăn bằng PoC hiện có, **ban ngày**, chi phí ~0 |
| "Hướng B là lựa chọn mới cần quyết" | Không phải lựa chọn — là quyết định đã chốt 13/07 (`phase-05`: RGB + IR 850nm, bỏ filter IR). Mở lại là tốn thời gian vào việc đã xong | Đọc lại bảng chọn camera phase-05 |
| "Phase 05 có phương án dự phòng nếu pose thất bại" | **Phương án đó không tồn tại** — xem mục 4 | Đã kiểm chứng, xác nhận sai |

## 4. Lỗ hổng nghiêm trọng phát hiện khi scout

Bảng rủi ro `phase-05` ghi cho ca chăn che:

> "Nếu thất bại thì chuyển hướng: dùng **loadcell 4 góc** để suy ra phân bố trọng lượng và vị trí cơ thể, kết hợp radar. **Đây là phương án dự phòng thật sự khả thi**."

Nhưng **loadcell đã bị cắt khỏi spec** — `phase-00:39`, chốt 13/07, thay bằng piezo pad. Piezo cho BCG, **không** cho phân bố trọng lượng 4 góc.

Nên phương án được ghi là "thật sự khả thi" **không còn tồn tại trong BOM**. Phase 05 là mốc PROTOTYPE release được, và rủi ro lớn nhất của nó đang trỏ vào một thứ đã bị xoá. Hai quyết định cùng ngày 13/07, mâu thuẫn nhau, không ai bắt được.

**Quyết định (Hưng, 14/08):** radar LD2510B + piezo pad thay vào vị trí đó. Cả hai **đã có trong BOM Phase 01**, không phát sinh mua sắm. Không khôi phục loadcell — không đảo quyết định 13/07.

## 5. Ba chức năng vision có yêu cầu khác nhau, đang bị gộp làm một

Đây là cái làm đổi hẳn kết luận.

| Chức năng | Khi nào chạy | Có chăn? | Cần tối? | Công cụ đúng |
|---|---|---|---|---|
| **1. Khớp 3 mảng nâng** | *"khi người mới nằm xuống, không cần chạy liên tục cả đêm"* (nguyên văn phase-05) | Thường **chưa** đắp | Đèn thường **còn sáng** | RGB — **PoC hôm nay có thể đã đủ** |
| **2. Phân loại tư thế cả đêm** (cho Phase 06 chống ngáy) | Suốt đêm | **Có** | Có | Radar + piezo. Vision là công cụ sai |
| **3. rPPG sleep staging** | Suốt đêm | Mặt thường **không** bị che | Có | IR camera. Rủi ro cao |

Chức năng 1 — thứ trực tiếp tạo giá trị *"giường tự khớp theo vóc dáng"* — có thể **không cần IR, không cần xử lý chăn**. Nếu đúng, phần lớn giá trị Phase 05 mở khoá sớm hơn nhiều, không phải chờ giải bài toán khó nhất.

Chức năng 3: `phase-05` đã tự ghi rPPG dưới IR khó hơn paper nhiều (paper dùng ánh sáng môi trường), và đã có sẵn phương án lùi — dùng nhịp tim từ radar.

## 6. Đánh giá ba hướng ban đầu

**A — đèn IR cho node ESP32-CAM.** Rẻ nhất, sai chỗ. Node này là công cụ bench-test theo H-25, không phải đường tới production; Phase 05 đã chốt camera gắn Jetson. Đầu tư vào đây là làm đẹp nhánh sẽ vứt. Ngoại lệ: dùng để **đo thử** ảnh IR trước khi mua camera Jetson.

**B — camera IR gắn Jetson.** Là quyết định sẵn có, và đúng. Nhưng **không** giải bài toán chăn, lại đang gánh thêm rủi ro MediaPipe aarch64 (`system-architecture.md` §6.1.1) chưa giải.

**C — bỏ vision ban đêm, dựa radar+piezo.** Đúng **cho chức năng 2**, không phải cho cả ba. LD2510B xuyên chăn tốt (bản chất radar 24GHz), cho vị trí thật và track nhiều người. Nhưng radar không cho skeleton → không thay được chức năng 1, và không cho rPPG.

## 7. Quyết định

**Tách Phase 05 theo chức năng** (Hưng chốt 14/08), vì ba chức năng không cùng bài toán:

| Nhánh | Hướng | Trạng thái rủi ro |
|---|---|---|
| Khớp 3 mảng nâng | Giữ vision RGB, xác nhận bằng PoC đã có | Thấp — gần như xong |
| Phân loại tư thế cả đêm | Radar + piezo, **bỏ kỳ vọng vision xuyên chăn** | Trung bình — cảm biến đã có, thuật toán chưa |
| rPPG sleep staging | Giữ IR camera, coi là **nghiên cứu rủi ro cao** | Cao — **không chặn release** |

Lợi ích kép: vá luôn lỗ hổng mục 4. Thay vì trông vào loadcell đã bị cắt, chức năng 2 dựa vào cảm biến đã có trong BOM.

## 8. Việc kiểm chứng tiếp theo — rẻ nhất, làm trước

**Test chăn bằng PoC hiện có. Ban ngày. Chi phí gần bằng 0.**

Cách làm:

1. Board `esp32cam-stream` đã nạp, để nguyên
2. Đặt camera nhìn từ trên xuống vùng ngủ (không phải ngang mặt như lần test hôm nay)
3. Nằm lên giường, **đắp chăn như ngủ thật**, phòng đủ sáng
4. Đóng tab trình duyệt, chạy `python pose_poc.py --url http://<ip>:81/stream`
5. Ghi lại: còn ra landmark không, những điểm nào còn nhìn thấy, tỉ lệ phát hiện

Thử 3 mức: không chăn / chăn tới ngực / trùm kín tới cổ.

**Vì sao đây là việc đúng để làm trước:** nó trả lời câu hỏi đắt nhất của Phase 05 bằng đồ đã chạy, ngay hôm nay, trước khi tiêu tiền vào camera IR hay tốn tuần gỡ rối MediaPipe trên Jetson. Nếu chăn làm pose vô dụng ngay cả khi đủ sáng, thì mua camera IR không cứu được gì — và biết điều đó **trước** khi mua đáng giá hơn nhiều.

Ghi số đo vào `docs/sensor-characterization.md`, mục "Not measured yet" đã chừa sẵn chỗ.

## 9. Trạng thái bằng chứng

| Khẳng định | Mức |
|---|---|
| RGB + MediaPipe dùng được ban ngày, người không đắp chăn | **Mạnh** — đo thật 14/08, 343/347 frame |
| OV2640 không dùng được trong tối | **Mạnh** — giới hạn vật lý cảm biến + 2 nguồn công bố |
| Chăn làm pose vô dụng | **Yếu** — mới là dự đoán của phase-05, chưa ai đo. Đây chính là lý do phải test |
| Radar LD2510B xuyên chăn cho vị trí thật | **Trung bình** — bản chất radar 24GHz, datasheet. Chưa đo trên giường thật |
| MediaPipe chạy được trên Orin | **Không có** — xem §6.1.1 |

## 10. Ngoài scope vòng này

Mua camera IR, verify MediaPipe trên Jetson, thuật toán phân loại tư thế từ radar, rPPG. Tất cả chờ kết quả test chăn.

## Câu hỏi tồn đọng

- Ai cập nhật bảng rủi ro `phase-05` và mục "Chọn camera" cho khớp quyết định mục 4 và 7 — làm ngay, hay gộp vào lúc Phase 05 khởi động?
- Chức năng 1 chạy "khi người mới nằm xuống": phát hiện thời điểm đó bằng gì — radar presence, piezo, hay người dùng bấm nút? Chưa ai chốt.
- Nếu test chăn cho kết quả **tốt bất ngờ** (vẫn ra skeleton qua chăn mỏng), có kéo chức năng 2 quay lại vision không, hay vẫn giữ radar cho đơn giản?
