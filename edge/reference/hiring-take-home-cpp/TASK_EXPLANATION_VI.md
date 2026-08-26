# Diễn giải bài tập SmartBed - CHTLab / EVsafe

**Ứng viên:** Cao Huỳnh Khánh Hưng  
**Vị trí:** Kỹ sư R&D / Kỹ sư Điện tử - Dự án SmartBed  
**Mục đích file này:** Giúp diễn giải bài làm khi gửi email hoặc khi phỏng vấn. File này không thay thế `README.md`, `design_doc.pdf` hoặc source code, mà dùng để giải thích rõ: đề bài yêu cầu gì, em hiểu bài toán như thế nào, em đã làm gì, và vì sao em chọn cách làm đó.

---

## 1. Tóm tắt bài toán trong 3 câu

Bài test yêu cầu phân tích một hệ thống **SmartBed / giường thông minh** có khả năng theo dõi người dùng bằng cảm biến và camera, sau đó điều chỉnh tư thế ngủ bằng nhiều actuator. Em hiểu trọng tâm của bài không phải tìm một đáp án tuyệt đối, mà là thể hiện **tư duy hệ thống, tư duy an toàn, khả năng đọc yêu cầu kỹ thuật và khả năng triển khai code xử lý dữ liệu cảm biến**. Vì vậy, bài làm của em chia thành hai phần chính: **design document cho hệ thống cơ điện tử** và **source code C++ xử lý dataset cảm biến**.

---

## 2. Em hiểu đề bài yêu cầu gì?

Theo tài liệu MVP và dataset được cung cấp, em hiểu bài test có hai nhóm yêu cầu:

### 2.1. Phần thiết kế hệ thống

Phần này yêu cầu đưa ra thiết kế ở mức hệ thống cho cơ chế tự điều chỉnh tư thế ngủ của SmartBed. Các điểm quan trọng trong tài liệu gồm:

- Hệ thống dùng camera/skeleton tracking để hiểu tư thế người nằm.
- Giường có **10 servo lifter engines / 10 actuator nâng hạ**.
- Actuator có các thông số MVP được nêu như: hành trình khoảng **50 cm**, lực đẩy **500 N**, tốc độ **7-12 mm/s**, mục tiêu độ ồn **< 42 dB**.
- Hệ thống có nhiều cảm biến như loadcell, radar/presence, breath/heartbeat, SpO2, camera hoặc thermal.
- Vì có người nằm trực tiếp trên cơ cấu nâng hạ, thiết kế phải ưu tiên **safety / fail-safe**.

Em diễn giải phần này thành bài toán: **AI/camera chỉ được đề xuất tư thế, còn việc actuator có được phép chuyển động hay không phải do Safety Supervisor quyết định dựa trên feedback thực tế**.

### 2.2. Phần coding với dataset cảm biến

Dataset là file CSV mô phỏng luồng cảm biến theo thời gian. Code cần đọc dữ liệu và xử lý các tín hiệu như:

- `loadcell_kg`: tải đo từ loadcell.
- `presence`: tín hiệu có/không có người.
- `motion_intensity`: mức độ chuyển động.
- `chest_disp`: dao động lồng ngực để suy ra nhịp thở.
- `hr_bpm`: nhịp tim, trong đó `0` được hiểu là dropout/mất tín hiệu.
- `spo2`: nồng độ oxy máu ngoại vi.

Em diễn giải phần này thành bài toán: **đọc dữ liệu cảm biến, phân loại trạng thái người dùng trên giường, ước lượng nhịp thở RR, phát hiện apnea/ngưng thở, và xuất log/timeline để người chấm kiểm tra được cách xử lý**.

---

## 3. Những gì em đã nộp trong project

Project của em gồm các phần chính:

| Thành phần | Vai trò |
|---|---|
| `design_doc.pdf` | Tài liệu thiết kế hệ thống bằng tiếng Anh |
| `design_doc_vi.pdf` | Bản tiếng Việt hỗ trợ giải thích |
| `README.md` | Hướng dẫn build/chạy và mô tả kỹ thuật chính |
| `README_vi.md` | Bản README tiếng Việt |
| `src/smartbed_stream_processor.cpp` | Source code C++ xử lý dataset |
| `smartbed-sensor-stream.csv` | Dataset đầu vào |
| `output/` | Kết quả chạy: log, timeline, biểu đồ |
| `tests/` | Dữ liệu test tổng hợp cho RR và apnea |
| `CODE_EXPLANATION_VI.md` | File giải thích chi tiết code |
| `TASK_EXPLANATION_VI.md` | File này - diễn giải tổng thể bài tập và cách trình bày |

---

## 4. Cách em diễn giải phần thiết kế hệ thống

### 4.1. Luồng điều khiển tổng quát

Em không thiết kế theo kiểu:

```text
Camera / AI -> Motor Driver -> Actuator
```

vì cách này nguy hiểm. Nếu AI nhận sai tư thế hoặc camera bị che bởi chăn, actuator có thể nâng/hạ sai khi có người đang nằm.

Thay vào đó, em thiết kế theo hướng closed-loop và có Safety Supervisor:

```text
Camera IR/RGB-D
-> Skeleton Detection
-> 10-point Mapper
-> Safety Supervisor
-> Motion Planner
-> Drivers x10
-> Actuators x10

Position + Current Feedback
-> Safety Supervisor
```

Ý tưởng chính là:

```text
AI proposes posture, Safety Supervisor permits motion.
```

Nghĩa là AI chỉ đề xuất mục tiêu, còn Safety Supervisor mới là lớp quyết định cuối cùng.

### 4.2. Vì sao cần closed-loop feedback?

Vì actuator đang tác động trực tiếp lên cơ cấu giường có người nằm. Nếu chỉ gửi lệnh một chiều mà không biết actuator có thật sự chạy đúng không thì rất nguy hiểm.

Feedback cần có tối thiểu:

- Vị trí actuator hiện tại.
- Dòng điện motor.
- Trạng thái fault của driver.
- Timeout khi actuator không tới vị trí mong muốn.
- Sai lệch trái/phải giữa các actuator cùng một vùng.

Nếu có lỗi, hệ thống phải dừng nhóm actuator liên quan thay vì tiếp tục nâng/hạ.

### 4.3. Cách chia 10 actuator

Em diễn giải 10 actuator thành 5 cặp trái/phải theo các vùng cơ thể:

| Vùng | Actuator |
|---|---|
| Head/Shoulder | 2 actuator trái/phải |
| Back | 2 actuator trái/phải |
| Hip | 2 actuator trái/phải |
| Thigh | 2 actuator trái/phải |
| Lower-leg | 2 actuator trái/phải |

Cách chia theo cặp giúp giảm xoắn khung. Nếu một actuator bên trái bị kẹt mà bên phải vẫn chạy thì khung có thể bị vặn, nên khi phát hiện lệch trái/phải vượt ngưỡng, hệ thống phải dừng cả cặp.

### 4.4. Cơ khí và tiếng ồn

Trong design doc, em chọn hướng:

- Dùng linear actuator gắn qua clevis/rod-end để giảm side-load.
- Dùng segmented lifting frame thay vì đẩy trực tiếp vào nệm mềm.
- Dùng khung thép hoặc nhôm định hình tùy giai đoạn MVP.
- Dùng rubber bushings, covered hinges, anti-rattle joints để giảm rung/ồn.
- Dùng S-curve motion profile để actuator tăng/giảm tốc mượt, tránh giật.

Điểm em muốn thể hiện là: độ ồn không chỉ phụ thuộc motor, mà còn phụ thuộc vào cơ khí, khớp nối, profile chuyển động và vật liệu cách rung.

### 4.5. Safety / fail-safe

Vì người nằm trên hệ thống nâng hạ, em ưu tiên các lỗi sau:

| Tình huống lỗi | Cách xử lý |
|---|---|
| Actuator kẹt/quá tải | Dừng actuator hoặc dừng cả nhóm/cặp liên quan |
| Sai lệch trái/phải | Dừng cả cặp để tránh xoắn khung |
| Có tay/chân trong vùng kẹp | Chặn chuyển động tự động |
| Camera mất confidence | Không cho actuator chạy tự động |
| Mất điện khi đang nâng | Ưu tiên self-locking actuator hoặc brake/backup lowering |
| Khởi động lại sau lỗi | Không resume lệnh cũ, phải đọc lại vị trí và kiểm tra trạng thái |

Câu diễn giải quan trọng:

```text
Default safe behavior is stop, hold, or slow lowering - not continue moving.
```

---

## 5. Cách em diễn giải phần code C++

### 5.1. Vì sao chọn C++?

Em chọn C++ vì em tự tin hơn khi giải thích logic hệ thống/embedded và muốn thể hiện cách tổ chức code rõ ràng, có struct/class, có test và có output kiểm chứng. Với các pipeline AI/data thực tế, em sẵn sàng dùng Python nếu stack của team yêu cầu.

Câu có thể nói khi phỏng vấn:

```text
I implemented the coding task in C++ because it is the language I can best reason about and defend for system-level logic. I am also open to using Python for data processing or AI pipelines depending on the team's stack.
```

### 5.2. Luồng xử lý trong code

Code xử lý theo pipeline:

```text
Read CSV
-> parse sensor samples
-> clean/interpolate invalid values
-> classify bed state
-> estimate respiratory rate from chest_disp
-> detect apnea event
-> generate logs, timeline CSV, SVG charts
```

### 5.3. Phân loại trạng thái người nằm

Code phân loại thành các trạng thái:

| State | Ý nghĩa |
|---|---|
| `EMPTY` | Không có người trên giường |
| `LYING_STILL` | Có người và đang nằm yên |
| `MOVING` | Có người và đang cử động |
| `LEAVING` | Người đang rời khỏi giường |

Em không dùng một cảm biến duy nhất. Em kết hợp:

```text
loadcell + presence + motion_intensity + load slope
```

Lý do: nếu chỉ dùng loadcell thì người trở mình hoặc nằm lệch có thể làm tải thay đổi; nếu chỉ dùng presence thì radar có thể nhiễu; nếu chỉ dùng motion thì không biết người còn trên giường hay không.

### 5.4. Ngưỡng `load_enter_kg` và `load_exit_kg`

```cpp
load_enter_kg = 18.0;
load_exit_kg  = 8.0;
```

Hai số này **không phải cân nặng người dùng**. Đây là hai ngưỡng hysteresis để xác định occupied/empty.

- `load_enter_kg = 18 kg`: nếu tải đủ lớn thì bắt đầu tin là có người.
- `load_exit_kg = 8 kg`: nếu tải giảm xuống thấp và presence cũng không thấy người thì mới kết luận giường trống.

Mục đích của hai ngưỡng khác nhau là tránh trạng thái bị nhấp nháy khi người cử động hoặc tải đo dao động.

Câu diễn giải:

```text
These are occupancy thresholds, not body weight. They are tunable hysteresis values selected for the provided dataset and should be calibrated on the real bed.
```

### 5.5. HR dropout

Trong dataset, `hr_bpm = 0` không được hiểu là người có nhịp tim bằng 0. Đây là mất tín hiệu tạm thời.

Code xử lý theo hướng:

```text
hr_bpm = 0 -> sensor dropout -> ignore/interpolate, do not treat as real heart rate
```

Điểm này thể hiện hiểu đúng dữ liệu cảm biến thực tế: cảm biến có thể mất tín hiệu, nhiễu, hoặc đo sai.

### 5.6. RR là gì và được tính thế nào?

**RR = Respiratory Rate**, nghĩa là nhịp thở, đơn vị là breaths per minute.

Code tính RR từ `chest_disp`:

```text
chest_disp signal
-> smoothing / filtering
-> peak detection
-> measure time between peaks
-> RR = 60 / median breath period
```

Ví dụ nếu khoảng cách giữa hai đỉnh thở là 4 giây:

```text
RR = 60 / 4 = 15 breaths/min
```

Code chỉ tính RR khi người đang `LYING_STILL`, vì nếu người đang cử động thì `chest_disp` có thể bị nhiễu bởi chuyển động cơ thể.

### 5.7. Apnea là gì và được phát hiện thế nào?

**Apnea** nghĩa là ngưng thở. Trong bài này, code phát hiện apnea khi:

```text
bed occupied
+ user lying still
+ recent breathing amplitude is very low
+ duration > 10 seconds
-> APNEA_ALERT
```

Điểm quan trọng: điều kiện **> 10 giây** là từ đề bài. Nhưng ngưỡng biên độ thấp bao nhiêu là `near zero` thì đề không cho cụ thể, nên em dùng ngưỡng kỹ thuật có thể tune:

```text
max(apnea_abs_amp, apnea_fraction_of_baseline * baseline_amplitude)
```

Cách này tốt hơn ngưỡng cố định vì mỗi người, mỗi tư thế và mỗi cảm biến có biên độ thở khác nhau.

### 5.8. SpO2 dùng để làm gì?

**SpO2 = Peripheral Oxygen Saturation**, tức độ bão hòa oxy trong máu ngoại vi.

Trong code, SpO2 chỉ là tín hiệu phụ để tăng độ tin cậy, không phải trigger chính của apnea. Lý do là SpO2 thường có độ trễ và cũng có thể dropout.

Câu diễn giải:

```text
SpO2 is used as a corroborating signal, not the primary trigger. The primary trigger is low breathing amplitude for more than 10 seconds while the bed is occupied and the user is still.
```

---

## 6. Những số liệu nào là từ đề bài, số nào là giả định?

Đây là phần rất quan trọng khi bảo vệ bài làm.

### 6.1. Số liệu từ đề bài/tài liệu

| Số liệu | Ý nghĩa |
|---|---|
| `10 actuator` | Hệ có 10 điểm nâng |
| `50 cm` | Hành trình nâng |
| `500 N` | Lực đẩy actuator |
| `7-12 mm/s` | Tốc độ chuyển động |
| `< 42 dB` | Mục tiêu độ ồn |
| `hr_bpm = 0` | Dropout, không phải nhịp tim thật |
| `apnea > 10s` | Điều kiện thời gian để cảnh báo ngưng thở |
| Dataset CSV | Dữ liệu cảm biến được cung cấp |

### 6.2. Số liệu là engineering assumptions / tunable thresholds

Các giá trị như dưới đây là ngưỡng kỹ thuật em chọn để xử lý dataset mẫu:

```cpp
load_enter_kg = 18.0;
load_exit_kg = 8.0;
motion_moving = 0.25;
motion_leaving = 0.35;
still_motion_for_rr = 0.18;
apnea_abs_amp = 0.003;
apnea_fraction_of_baseline = 0.20;
spo2_low_pct = 94.0;
spo2_drop_pct = 3.0;
rr_window_s = 30.0;
rr_update_s = 5.0;
```

Những ngưỡng này **không phải tiêu chuẩn y tế** và **không phải datasheet**. Chúng là tham số có thể hiệu chỉnh khi có dữ liệu thực tế.

Câu trả lời ngắn gọn khi được hỏi:

```text
Only the actuator specs, HR dropout behavior, CSV structure, and apnea duration are fixed by the assignment. The state-classification thresholds and signal-processing thresholds are tunable engineering assumptions selected for this dataset. I put them in a Thresholds structure so they can be calibrated later instead of being hidden throughout the code.
```

---

## 7. Các thuật ngữ tiếng Anh cần nhớ

| Thuật ngữ | Viết đầy đủ | Nghĩa |
|---|---|---|
| Apnea | Sleep Apnea / Apnea Event | Ngưng thở khi ngủ |
| RR | Respiratory Rate | Nhịp thở |
| HR | Heart Rate | Nhịp tim |
| BPM | Beats Per Minute / Breaths Per Minute | Nhịp mỗi phút |
| SpO2 | Peripheral Oxygen Saturation | Độ bão hòa oxy máu ngoại vi |
| Dropout | Sensor Dropout | Mất tín hiệu cảm biến |
| CSV | Comma-Separated Values | File dữ liệu dạng bảng |
| MVP | Minimum Viable Product | Sản phẩm khả dụng tối thiểu |
| AI | Artificial Intelligence | Trí tuệ nhân tạo |
| CV | Computer Vision | Thị giác máy tính |
| IR | Infrared | Hồng ngoại |
| RGB-D | RGB plus Depth | Camera màu + chiều sâu |
| mmWave | Millimeter Wave | Sóng milimet |
| GPIO | General Purpose Input/Output | Chân vào/ra đa dụng |
| PWM | Pulse Width Modulation | Điều chế độ rộng xung |
| PID | Proportional Integral Derivative | Bộ điều khiển PID |
| Feedback | Position/Current Feedback | Phản hồi vị trí/dòng điện |
| Closed-loop | Closed-loop Control | Điều khiển vòng kín |
| Fail-safe | Fail-safe Mechanism | Cơ chế an toàn khi lỗi |
| E-stop | Emergency Stop | Dừng khẩn cấp |
| Self-locking | Self-locking Actuator | Actuator tự hãm khi mất điện |
| S-curve | S-curve Motion Profile | Profile chuyển động mượt dạng chữ S |
| Fault | Fault Signal / Fault Condition | Tín hiệu/trạng thái lỗi |
| Stall | Motor Stall | Motor bị kẹt/đứng |
| Overcurrent | Overcurrent Condition | Quá dòng |
| Timeout | Timeout | Quá thời gian cho phép |
| Edge device | Edge Computing Device | Thiết bị xử lý tại chỗ |

---

## 8. Kết quả output cần nhắc khi phỏng vấn

Khi chạy trên dataset, output chính gồm:

- `events.log`: log sự kiện như `STATE_CHANGE`, `RESP_RATE`, `APNEA_ALERT`, `APNEA_END`.
- `processed_timeline.csv`: timeline dữ liệu sau xử lý.
- `state_segments.csv`: các đoạn trạng thái theo thời gian.
- `state_timeline.svg`, `chest_disp.svg`, `resp_rate.svg`: biểu đồ kiểm chứng.

Ví dụ sự kiện apnea:

```text
314.60s | APNEA_ALERT | breathing amplitude low for >10s while occupied/still; since=304.60s
325.20s | APNEA_END | breathing amplitude recovered
```

Cách giải thích:

```text
At around 304.60 seconds, the recent breathing amplitude became very low. After it stayed low for more than 10 seconds while the bed was occupied and the user was still, the system generated an APNEA_ALERT at 314.60 seconds. When the breathing amplitude recovered, the system generated APNEA_END at 325.20 seconds.
```

---

## 9. Cách trình bày bài làm trong 1 phút

### Bản tiếng Việt

```text
Trong bài test SmartBed, em chia bài toán thành hai phần: thiết kế hệ thống cơ điện tử an toàn và xử lý dữ liệu cảm biến. Ở phần thiết kế, em không cho AI điều khiển actuator trực tiếp. Camera/skeleton chỉ đề xuất tư thế, sau đó Safety Supervisor kiểm tra giới hạn, feedback vị trí, dòng điện, timeout, sai lệch trái/phải và độ tin cậy cảm biến trước khi cho phép Motion Planner điều khiển 10 actuator. 10 actuator được xem như 5 cặp trái/phải để tránh xoắn khung, và khi một actuator lỗi thì dừng cả cặp hoặc cả nhóm liên quan.

Ở phần coding, em viết chương trình C++ đọc dataset CSV, xử lý dropout, phân loại trạng thái EMPTY/LYING_STILL/MOVING/LEAVING bằng loadcell, presence và motion. Sau đó em ước lượng respiratory rate từ chest displacement bằng sliding window và peak detection. Apnea được cảnh báo khi biên độ thở gần như bằng 0 hơn 10 giây trong lúc người vẫn nằm yên trên giường. Các ngưỡng như load_enter, motion threshold, apnea amplitude là engineering assumptions có thể tune lại; còn các thông số như 10 actuator, 50 cm, 500 N, 7-12 mm/s, <42 dB và apnea >10s là từ tài liệu/đề bài.
```

### English version

```text
For the SmartBed assignment, I split the problem into two parts: a safe mechatronic system design and a sensor-stream processing program. For the design part, I do not let the AI control the actuators directly. The camera and skeleton pipeline only propose the posture target. The Safety Supervisor checks command limits, position feedback, motor current, timeout, left-right mismatch, and sensor confidence before the Motion Planner is allowed to command the ten actuators. I treat the ten actuators as five left-right pairs to reduce frame twisting, and if one actuator fails, the related pair or group is stopped.

For the coding part, I implemented a C++ program that reads the CSV dataset, handles sensor dropout, classifies bed states such as EMPTY, LYING_STILL, MOVING, and LEAVING using loadcell, presence, and motion data. Then I estimate respiratory rate from chest displacement using a sliding window and peak detection. Apnea is detected when the breathing amplitude stays near zero for more than 10 seconds while the bed is occupied and the user is lying still. Thresholds such as load_enter, motion thresholds, and apnea amplitude are tunable engineering assumptions, while actuator specs, HR dropout behavior, and apnea duration are based on the assignment.
```

---

## 10. Những câu hỏi phỏng vấn có thể gặp và cách trả lời

### Câu 1: Vì sao không cho AI điều khiển actuator trực tiếp?

Vì AI/camera có thể nhận sai khi bị chăn che, ánh sáng kém hoặc skeleton confidence thấp. Actuator tác động trực tiếp lên người nằm nên phải có Safety Supervisor và feedback vòng kín để quyết định có cho phép chuyển động hay không.

### Câu 2: `load_enter_kg = 18` có phải cân nặng người không?

Không. Đây là ngưỡng occupied/empty cho thuật toán, không phải cân nặng người. Em dùng hai ngưỡng `load_enter` và `load_exit` để tạo hysteresis, tránh trạng thái nhấp nháy khi người cử động hoặc loadcell dao động.

### Câu 3: Các ngưỡng trong code lấy từ đâu?

Một số thông tin là từ đề bài như apnea >10s, HR=0 là dropout, thông số actuator. Còn các ngưỡng phân loại trạng thái, motion, SpO2 và biên độ thở là engineering assumptions được chọn để xử lý dataset mẫu. Khi triển khai thật phải calibration lại bằng dữ liệu thực tế.

### Câu 4: Vì sao RR chỉ tính khi người nằm yên?

Vì khi người cử động, tín hiệu `chest_disp` không còn phản ánh riêng chuyển động hô hấp mà có thể bị nhiễu bởi chuyển động toàn thân. Do đó code chỉ tính RR khi trạng thái là `LYING_STILL` và motion thấp.

### Câu 5: SpO2 có dùng để chẩn đoán apnea không?

Không. Trong code, SpO2 chỉ là tín hiệu hỗ trợ xác nhận. Trigger chính là biên độ thở thấp hơn 10 giây trong lúc người vẫn nằm yên. Em không xem đây là chẩn đoán y tế.

### Câu 6: Vì sao cần dừng cả cặp actuator khi một bên lỗi?

Vì các actuator hoạt động theo cặp trái/phải. Nếu một bên kẹt mà bên còn lại vẫn tiếp tục nâng, khung giường có thể bị xoắn và gây nguy hiểm. Dừng cả cặp là lựa chọn an toàn hơn.

### Câu 7: Nếu mất điện khi giường đang nâng thì sao?

Thiết kế cần actuator self-locking hoặc brake/cơ chế hãm để không tụt tự do. Khi có điện lại, hệ thống không được resume lệnh cũ mà phải đọc lại vị trí, kiểm tra occupancy, sau đó homing hoặc hạ chậm nếu an toàn.

---

## 11. Điểm mạnh nên nhấn mạnh trong bài làm

Khi trình bày, em nên nhấn mạnh các điểm sau:

1. Em không bịa số liệu không có trong tài liệu; phần thiếu được ghi rõ là assumptions.
2. Em đặt Safety Supervisor giữa AI và actuator để tránh điều khiển nguy hiểm.
3. Em dùng closed-loop feedback thay vì điều khiển một chiều.
4. Em xem 10 actuator như các cặp đồng bộ để tránh xoắn khung.
5. Em xử lý dữ liệu cảm biến theo hướng thực tế: có dropout, nhiễu, hysteresis, sliding window.
6. Em tách rõ thông số từ đề bài và ngưỡng kỹ thuật có thể tune.
7. Em có output log, timeline, chart và test để kiểm chứng code.

---

## 12. Kết luận diễn giải

Bài làm của em không chỉ cố gắng chạy được code trên dataset, mà còn thể hiện cách tiếp cận của một kỹ sư R&D: đọc yêu cầu, xác định giới hạn dữ liệu, đưa ra giả định rõ ràng, thiết kế hệ thống có feedback và fail-safe, sau đó triển khai code có cấu trúc để xử lý dữ liệu cảm biến. Trọng tâm của bài là **logic, safety, system thinking, và khả năng giải thích được quyết định kỹ thuật**.
