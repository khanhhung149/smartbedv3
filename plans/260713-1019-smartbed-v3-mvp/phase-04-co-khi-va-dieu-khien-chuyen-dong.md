# Phase 04 — Cơ khí 3 mảng + handler + điều khiển chuyển động

- **Ưu tiên:** P1
- **Trạng thái:** chưa bắt đầu
- **Ước lượng:** 5-6 tuần (giảm từ 6-8 vì 3 mảng thay vì 10 điểm)
- **Rủi ro:** **CAO NHẤT TOÀN DỰ ÁN**. Đây là phase duy nhất có thể làm người dùng bị thương.
- **Phụ thuộc:** Phase 02 (cần state machine biết người đang nằm/ngủ/rời giường)
- **Nhân sự:** **anh Khanh (cơ khí)** + Hưng (điện, firmware ESP32)

> **Cập nhật 13/07 — hai thay đổi lớn:**
> 1. **10 điểm nâng → 3 mảng.** 10 điểm đẩy sang Phase 07.
> 2. **Đã có người làm cơ khí: anh Khanh.** Đây từng là blocker số 1 của cả dự án — nay đã gỡ.

## Mục tiêu

**3 mảng nâng** chỉnh được tư thế ngủ, điều khiển bằng app hoặc tablet. **Chưa tự động.** Tự động khớp theo skeleton là việc của Phase 05, closed-loop chống ngáy là Phase 06. Phase này chỉ làm cho cơ cấu chuyển động một cách an toàn và tin cậy.

### Cấu hình 3 mảng (chốt 13/07)

| Mảng | Vị trí | Chức năng |
|---|---|---|
| Trên | Đầu giường | Nâng đầu / thân trên |
| Giữa | Rộng, phần thân | Nâng/hạ thân |
| Dưới | Nhỏ | Nâng chân |

**Ràng buộc:** cung độ **nhỏ**, tốc độ **chậm**, độ ồn **thấp**. Chậm và nhỏ là *tính năng an toàn*, không phải hạn chế kỹ thuật.

## Vì sao để tới đây mới làm

1. Rủi ro cao nhất: cơ cấu nâng đè lên người đang ngủ, người ngủ không tự bảo vệ được.
2. Tốn tiền nhất: actuator + khung chịu lực.
3. Không cần thiết để có sản phẩm: Phase 02 và 03 đã ra được hai sản phẩm bán được rồi. Nếu tiền hoặc thời gian cạn, cắt phase này vẫn còn hàng để bán.

## Kiến trúc điều khiển — Handler module (bắt buộc, chốt 13/07)

Cơ khí phải có **một module quản trị riêng (handler)**. Mọi thành phần khác trong hệ **chỉ được giao tiếp qua handler đó**, không ai được đụng thẳng vào actuator.

**Cơ chế safety nằm bên trong handler**, không nằm rải rác ở tầng trên: handler tự chặn khi lệnh dồn quá nhiều, khi chạy vượt giới hạn, khi dòng bất thường.

```
Jetson (Linux)            ESP32 handler (real-time)         Actuator
    │                          │                              │
    │  "muốn nâng mảng đầu     │  Kiểm tra:                   │
    │   lên 12cm"  ──UART/CAN─►│  - người có đang ngủ sâu?    │
    │                          │  - vượt giới hạn mềm?        │──► PWM/H-bridge
    │                          │  - dòng có bất thường?       │
    │  ◄── chấp nhận/từ chối ──│  - lệnh dồn quá nhiều?       │◄── dòng điện (ADC)
    │                          │  - watchdog còn sống?        │◄── encoder (vị trí)
                               │                              │
                               │  E-STOP ─────────────────────┤ (cắt nguồn phần cứng)
```

**ESP32 handler có quyền phủ quyết mọi lệnh từ Linux.** Linux treo, mất kết nối, hay bị hack thì actuator vẫn đứng yên an toàn.

## Position feedback (yêu cầu mới 13/07)

Hệ phải **biết mình đang ở vị trí nào** (%), không chỉ biết "đang chạy". Dùng encoder gắn vào cơ cấu.

**Pattern auto-calibrate** (Michael đã chạy thật trên hệ cửa tự động ở nhà, khuyến nghị áp dụng):

> Nếu actuator **tự dừng** (không phải do người ra lệnh dừng) tại vùng **< 15% gần đầu mút hành trình** → coi đó chính là điểm giới hạn vật lý → **tự sync vị trí đó về 0% hoặc 100%**.

Lợi ích: không cần công tắc hành trình, không cần calibrate thủ công. Encoder trượt vài % thì lần chạm biên kế tiếp tự sửa. Đây là ví dụ điển hình của "thuật toán thay thế phần cứng" — rẻ hơn, ít điểm hỏng hơn.

## Yêu cầu an toàn (bắt buộc, không phải nice-to-have)

| Yêu cầu | Cách làm | Cách verify |
|---|---|---|
| Phát hiện kẹt / quá tải | Đo dòng từng actuator. Dòng vượt ngưỡng đột ngột = có vật cản (tay, chân, thú cưng) → dừng ngay và lùi lại | Chèn khúc gỗ vào từng mảng nâng, actuator phải dừng dưới 200ms và lùi |
| E-stop | Nút cứng cắt nguồn actuator ở mức phần cứng, không đi qua phần mềm. **Trong tầm với của người đang nằm** | Bấm nút từ tư thế nằm, đo bằng oscilloscope, nguồn phải mất dưới 100ms |
| Mất điện = tự khoá | Cơ cấu tự hãm (ball-screw hoặc lead-screw có góc tự hãm), không dùng loại trôi tự do | Cắt điện đột ngột khi đang nâng tải 100kg, actuator phải giữ nguyên vị trí, không tụt |
| Giới hạn mềm + cứng | Giới hạn hành trình trong firmware + chặn cơ khí vật lý (hard stop) | Cố tình lệnh vượt hành trình, phải bị chặn cả hai tầng |
| Tốc độ chậm | Chậm là tính năng an toàn, không phải hạn chế. Giới hạn tốc độ nằm trong **firmware**, không chỉ trong software | Đo bằng thước và đồng hồ |
| Không chuyển động khi ngủ sâu | Ở v3, mặc định **cấm mọi chuyển động tự động khi người đang ngủ**. Chỉ chỉnh khi người còn thức hoặc chủ động ra lệnh | Test bằng state machine giả lập trạng thái ngủ |
| Chống dồn lệnh | **Handler tự chặn khi lệnh dồn quá nhiều** hoặc chạy quá giới hạn — yêu cầu Michael chốt 13/07 | Bắn 1000 lệnh/giây vào handler, phải bị throttle chứ không loạn |
| Watchdog | Linux mất tín hiệu heartbeat quá 500ms → ESP32 handler dừng mọi chuyển động | Rút dây UART giữa chừng khi đang nâng |

## Cơ khí (anh Khanh)

- Cơ cấu: **lead-screw hoặc ball-screw có tự hãm**. Không dùng khí nén hay thuỷ lực (rò rỉ, ồn, tụt áp).
- **3 mảng** (đầu / giữa rộng / chân). Cung độ nhỏ, tốc độ chậm, ồn thấp.
- **Verify lại thông số spec:** 500N và hành trình 50cm là con số của thiết kế 10 điểm năm 2023. Với 3 mảng, lực và hành trình thật cần bao nhiêu? **Anh Khanh tính lại, không copy số cũ.**
- Khung: nhôm định hình hoặc thép hộp, tính toán chịu tải tĩnh 150kg + hệ số an toàn tối thiểu 2.
- Vẽ CAD toàn bộ trước khi cắt sắt. Mô phỏng va chạm giữa 3 mảng (mảng chuyển động độc lập vẫn có thể kẹp vào nhau ở vùng giáp ranh).

## Việc phải làm

1. **Brief anh Khanh:** 3 mảng, ràng buộc ồn/tốc độ, yêu cầu handler + position feedback. Michael kết nối — hạn 18/07.
2. CAD khung + cơ cấu 3 mảng, mô phỏng động học, kiểm tra không tự kẹp nhau ở mọi tổ hợp vị trí.
3. Tính lại lực + hành trình thật cho cấu hình 3 mảng.
4. Mua 1 actuator mẫu trước, test riêng: đo dòng thật, **đo tiếng ồn thật bằng máy đo**, đo tốc độ thật. **Đừng tin datasheet.** Chỉ khi con mẫu đạt mới mua đủ bộ.
5. Mạch driver + đo dòng (shunt hoặc hall sensor) cho từng kênh + **encoder đọc vị trí**.
6. **Firmware ESP32 handler:** điều khiển vị trí, đo dòng, state machine an toàn, chống dồn lệnh, giao thức với Linux, watchdog, **auto-calibrate theo pattern 15% đầu mút**.
7. **Bench test không người:** bao cát 100kg, chạy 500 chu kỳ nâng/hạ. Ghi log dòng, nhiệt độ, độ trôi vị trí.
8. Test kẹt: chèn vật cản ở mọi mảng, mọi hướng.
9. Chỉ khi qua hết safety gate mới cho người thật nằm lên. **Người đầu tiên là kỹ sư, không phải khách.**
10. Ghi biên bản test, ký tên, lưu `docs/safety/phase-04-test-record.md`.

## Định nghĩa hoàn thành

- [ ] Qua đủ 5 mục Safety Gate trong `plan.md`
- [ ] 500 chu kỳ tải giả không lỗi, không trôi vị trí quá 2mm
- [ ] Phát hiện kẹt hoạt động ở cả 3 mảng
- [ ] Mất điện đột ngột: không tụt quá 5mm
- [ ] **Ồn thấp** — đo bằng máy đo dB tại vị trí đầu người nằm, không phải tại motor
- [ ] **Handler biết vị trí hiện tại (%) và tự calibrate khi chạm biên**, không cần công tắc hành trình
- [ ] Handler chặn được lệnh dồn / lệnh vượt giới hạn
- [ ] Chỉnh được tư thế từ app/tablet, mượt, không giật

## Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Actuator thực tế ồn hơn datasheet nhiều (rất hay xảy ra) | Mua mẫu test trước khi mua đủ bộ. Dự trù giảm chấn cao su, vỏ tiêu âm. **Nếu vẫn không đạt:** giảm tốc độ, hoặc chấp nhận chuyển động chỉ chạy khi người còn thức — lúc đó ồn không còn là vấn đề |
| 3 mảng kẹp vào nhau ở vùng giáp ranh, hoặc kẹp chăn/tay | Mô phỏng va chạm ở CAD + giới hạn mềm theo tổ hợp + phát hiện kẹt bằng dòng |
| Encoder trượt, mất vị trí thật | Pattern auto-calibrate 15% đầu mút xử lý được. Nhưng phải test: cố tình làm trượt encoder rồi xem hệ có tự sửa sau 1 lần chạm biên không |
| Copy nguyên thông số 500N/50cm của thiết kế 10 điểm cũ | Bắt anh Khanh tính lại từ đầu cho cấu hình 3 mảng. Số cũ không có căn cứ cho cấu hình mới |
| Người dùng bị thương | Đây là lý do tồn tại của toàn bộ Safety Gate. Không có đường tắt |
