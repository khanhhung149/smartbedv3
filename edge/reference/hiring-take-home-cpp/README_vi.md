# SmartBed - bản nộp C++ có giải thích tiếng Việt

Repo này có hai phần chính:

1. `design_doc.md` / `design_doc.pdf`: design doc tiếng Anh để nộp.
2. `design_doc_vi.md` / `design_doc_vi.pdf`: bản tiếng Việt song song để bạn hiểu và tự bảo vệ khi phỏng vấn.
3. `src/smartbed_stream_processor.cpp`: chương trình C++17 xử lý file `smartbed-sensor-stream.csv`.

Thiết kế dựa trên PDF MVP SmartBed: camera/skeleton tracking, 10 servo lifter engines, 50 cm lift, 500 N push force, movement 7-12 mm/s, noise <42 dB, các cảm biến non-contact và safety emergency như smoke sensor/smart lock. Vì PDF MVP chưa phải datasheet actuator đầy đủ, các thông số còn thiếu được ghi ở phần giả định.

## 1. Cách chạy trên máy bạn: `D:\smartbed_submission_cpp_system_safety`

Bạn có 2 cách chạy. Nếu đã cài WSL Ubuntu thì nên dùng WSL. Nếu dùng PowerShell thì cần có `g++` trong Windows.

## Cách A - Chạy bằng WSL Ubuntu, khuyên dùng

Trong Ubuntu terminal, ổ D của Windows nằm tại `/mnt/d`.

```bash
cd /mnt/d/smartbed_submission_cpp_system_safety
ls
```

Nếu thấy các file như `Makefile`, `src`, `README.md`, `smartbed-sensor-stream.csv` là đúng thư mục.

Build:

```bash
make clean
make
```

Chạy chương trình với CSV thật:

```bash
./smartbed_stream_processor smartbed-sensor-stream.csv --outdir output
```

Xem log sự kiện:

```bash
cat output/events.log
```

Xem timeline trạng thái:

```bash
cat output/state_segments.csv
```

Chạy test nhỏ:

```bash
make test
```

Kết quả mong đợi:

```text
314.60s | APNEA_ALERT | breathing amplitude low for >10s while occupied/still; since=304.60s ... spo2_support=yes
325.20s | APNEA_END   | breathing amplitude recovered
```

## Cách B - Build trực tiếp bằng g++ trong WSL

Nếu `make` lỗi, dùng lệnh này:

```bash
g++ -std=c++17 -O2 -Wall -Wextra -pedantic src/smartbed_stream_processor.cpp -o smartbed_stream_processor
./smartbed_stream_processor smartbed-sensor-stream.csv --outdir output
```

## Cách C - Chạy bằng PowerShell/CMD Windows

Cách này chỉ dùng được nếu Windows đã cài `g++` qua MinGW/MSYS2.

```bat
D:
cd D:\smartbed_submission_cpp_system_safety
g++ -std=c++17 -O2 -Wall -Wextra -pedantic src\smartbed_stream_processor.cpp -o smartbed_stream_processor.exe
smartbed_stream_processor.exe smartbed-sensor-stream.csv --outdir output
```

## 2. Các file output

Sau khi chạy, chương trình tạo/cập nhật thư mục `output`:

```text
output/events.log              - log timeline: state, RR, HR dropout, apnea alert
output/state_segments.csv      - các đoạn EMPTY / LYING_STILL / MOVING / LEAVING
output/processed_timeline.csv  - từng sample sau xử lý
output/state_timeline.svg      - biểu đồ trạng thái
output/chest_disp.svg          - biểu đồ chest displacement
output/resp_rate.svg           - biểu đồ nhịp thở
```

## 3. Ý tưởng thuật toán C++

### 3.1 Phân loại trạng thái bằng sensor fusion

Code không dùng một cảm biến duy nhất. Nó kết hợp:

- `loadcell_kg`: tải trọng, biết có người nằm không.
- `presence`: radar mmWave xác nhận có người.
- `motion_intensity`: biết người nằm yên, đang cử động hay rời giường.
- load slope: phát hiện tải giảm nhanh khi người rời giường.

Kết quả gồm 4 trạng thái:

```text
EMPTY
LYING_STILL
MOVING
LEAVING
```

### 3.2 Xử lý HR dropout

Đề nói `hr_bpm = 0` là dropout, nên code xem đó là dữ liệu lỗi, không xem là nhịp tim thật bằng 0. Các gap ngắn được nội suy để timeline mượt hơn, nhưng không dùng HR=0 làm cảnh báo y tế.

### 3.3 Ước lượng nhịp thở

Nhịp thở chỉ tính khi người ở trạng thái `LYING_STILL` và motion thấp. Pipeline:

```text
chest_disp window -> interpolate -> moving average -> detrend -> peak detection -> median peak interval -> breaths/min
```

Cửa sổ 30 giây giúp có đủ chu kỳ thở để tính ổn định. Khi người đang cử động thì bỏ qua để tránh motion artifact.

### 3.4 Phát hiện apnea

Apnea không dùng trực tiếp RR window 30 giây, vì cửa sổ đó có thể còn chứa nhịp thở cũ. Code dùng biên độ `chest_disp` gần đây. Nếu biên độ thấp hơn ngưỡng hơn 10 giây trong lúc vẫn có người/nằm yên thì sinh `APNEA_ALERT`.

SpO2 chỉ là tín hiệu phụ xác nhận, không phải trigger chính, vì giảm SpO2 thường trễ hơn việc ngưng thở.

## 4. Khi phỏng vấn nên nói gì?

Bạn có thể nói:

```text
Em thiết kế hệ thống theo hướng closed-loop safety. Camera/skeleton chỉ đề xuất tư thế. Lệnh actuator không được gửi trực tiếp xuống motor mà phải qua Safety Supervisor. Safety Supervisor đọc feedback vị trí, dòng motor, limit switch, lỗi driver và camera confidence để quyết định có cho nâng/hạ hay không. Nếu actuator kẹt, quá dòng, lệch trái/phải, timeout hoặc có nguy cơ kẹp tay/chân, hệ thống dừng hoặc chỉ cho hạ chậm.
```

Về code:

```text
Em chọn C++17 vì em hiểu C++ hơn và nó phù hợp edge deployment. Code không phụ thuộc thư viện nặng, có thể build bằng g++. Em dùng sensor fusion để phân loại trạng thái, xử lý HR=0 như dropout, chỉ tính nhịp thở khi người nằm yên, và phát hiện apnea bằng biên độ thở gần đây kết hợp SpO2 corroboration.
```

## 5. Deploy lên Orange Pi / Coral / Jetson thì tối ưu gì?

- Đổi batch CSV thành streaming ring buffer.
- Pre-allocate bộ nhớ, tránh cấp phát động trong vòng lặp realtime.
- Tách safety/control loop khỏi AI inference, safety loop ưu tiên cao hơn.
- Dùng ONNX Runtime/TensorRT trên Jetson hoặc TFLite/Coral cho skeleton detection.
- Safety Supervisor độc lập với AI model: AI đề xuất, safety quyết định.
- Lưu actuator state và last safe position để khi mất điện không chạy tiếp lệnh cũ.
- Thêm watchdog, E-stop, current sensing từng kênh, limit switch, driver fault line trước khi nối actuator thật.
