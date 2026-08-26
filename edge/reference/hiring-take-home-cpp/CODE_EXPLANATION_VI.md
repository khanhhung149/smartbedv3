# Giải thích chi tiết code C++ SmartBed

File này giải thích chi tiết source code `src/smartbed_stream_processor.cpp`. Mục tiêu là giúp bạn hiểu và bảo vệ được bài làm khi phỏng vấn: chương trình đọc CSV cảm biến, phân loại trạng thái giường, ước lượng nhịp thở, phát hiện apnea và ghi output.

## 1. Tổng quan luồng xử lý

```text
CSV input
→ readCsv(): đọc và kiểm tra dữ liệu
→ cleanSamples(): xử lý HR=0 dropout và SpO2 missing
→ StateClassifier: fusion loadcell + presence + motion để phân loại state
→ RespiratoryRateEstimator: lọc chest_disp, tìm peak, tính breaths/min
→ Apnea detection: dùng biên độ thở ngắn hạn + SpO2 corroboration
→ write output: events.log, processed_timeline.csv, state_segments.csv, SVG plots
```

## 2. Các ý tưởng kỹ thuật quan trọng

- **Sensor fusion:** không dùng một cảm biến đơn lẻ; loadcell xác nhận tải, radar presence xác nhận có người, motion phân biệt nằm yên/cử động/rời giường.
- **HR dropout:** `hr_bpm = 0` được xem là dữ liệu lỗi, không phải nhịp tim bằng 0.
- **RR chỉ tính khi nằm yên:** tránh motion artifact làm sai `chest_disp`.
- **Apnea:** phát hiện bằng biên độ thở gần đây thấp hơn ngưỡng trong hơn 10 giây, SpO2 chỉ là tín hiệu phụ xác nhận.
- **Code sạch:** chia struct/class/function rõ ràng, output có log và CSV để kiểm tra lại.

## 3. Giải thích từng dòng code

> Bảng dưới đây giữ đúng số dòng trong file C++. Một số dòng đóng/mở ngoặc có giải thích ngắn vì vai trò chính là cấu trúc code.

| Dòng | Code | Giải thích |
|---:|---|---|
| 1 | <code>// Smartbed sensor stream processor - C++17 implementation</code> | Chú thích trong code: Smartbed sensor stream processor - C++17 implementation |
| 2 | <code>//</code> | Chú thích trống/đường phân cách. |
| 3 | <code>// Reads smartbed-sensor-stream.csv and produces:</code> | Chú thích trong code: Reads smartbed-sensor-stream.csv and produces: |
| 4 | <code>// - state timeline: EMPTY, LYING_STILL, MOVING, LEAVING</code> | Chú thích trong code: - state timeline: EMPTY, LYING_STILL, MOVING, LEAVING |
| 5 | <code>// - respiratory-rate estimates from chest displacement while lying still</code> | Chú thích trong code: - respiratory-rate estimates from chest displacement while lying still |
| 6 | <code>// - apnea alerts when breathing amplitude is near zero for &gt;10 seconds</code> | Chú thích trong code: - apnea alerts when breathing amplitude is near zero for &gt;10 seconds |
| 7 | <code>// - HR dropout handling, where hr_bpm=0 is treated as invalid data</code> | Chú thích trong code: - HR dropout handling, where hr_bpm=0 is treated as invalid data |
| 8 | <code>//</code> | Chú thích trống/đường phân cách. |
| 9 | <code>// The implementation is dependency-free C++17 so it can run on edge Linux boards</code> | Chú thích trong code: The implementation is dependency-free C++17 so it can run on edge Linux boards |
| 10 | <code>// such as Orange Pi / Jetson without Python, pandas, or NumPy.</code> | Chú thích trong code: such as Orange Pi / Jetson without Python, pandas, or NumPy. |
| 11 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 12 | <code>#include &lt;algorithm&gt;</code> | Nạp thư viện `algorithm`. Cung cấp các hàm thuật toán như sort, unique, min_element, count_if, remove_if. |
| 13 | <code>#include &lt;cmath&gt;</code> | Nạp thư viện `cmath`. Cung cấp hàm toán học như isfinite, floor, ceil, abs, llround. |
| 14 | <code>#include &lt;cstddef&gt;</code> | Nạp thư viện `cstddef`. Cung cấp kiểu size_t và các kiểu kích thước chuẩn. |
| 15 | <code>#include &lt;cstdlib&gt;</code> | Nạp thư viện `cstdlib`. Cung cấp strtod, system, exit. |
| 16 | <code>#include &lt;deque&gt;</code> | Nạp thư viện `deque`. Cấu trúc hàng đợi hai đầu, dùng để giữ lịch sử loadcell gần đây. |
| 17 | <code>#include &lt;fstream&gt;</code> | Nạp thư viện `fstream`. Đọc/ghi file CSV, log và SVG. |
| 18 | <code>#include &lt;iomanip&gt;</code> | Nạp thư viện `iomanip`. Định dạng số khi in ra log/CSV như setprecision, setw. |
| 19 | <code>#include &lt;iostream&gt;</code> | Nạp thư viện `iostream`. In thông báo ra terminal bằng cout/cerr. |
| 20 | <code>#include &lt;limits&gt;</code> | Nạp thư viện `limits`. Lấy giá trị đặc biệt như NaN và infinity. |
| 21 | <code>#include &lt;map&gt;</code> | Nạp thư viện `map`. Map tên cột CSV sang chỉ số cột. |
| 22 | <code>#include &lt;numeric&gt;</code> | Nạp thư viện `numeric`. Các tiện ích số học chuẩn. |
| 23 | <code>#include &lt;optional&gt;</code> | Nạp thư viện `optional`. Biểu diễn giá trị có thể có hoặc chưa có, như trạng thái cuối/apnea_start. |
| 24 | <code>#include &lt;sstream&gt;</code> | Nạp thư viện `sstream`. Tạo chuỗi bằng stream, parse dòng CSV đơn giản. |
| 25 | <code>#include &lt;stdexcept&gt;</code> | Nạp thư viện `stdexcept`. Ném lỗi runtime_error khi input/output sai. |
| 26 | <code>#include &lt;string&gt;</code> | Nạp thư viện `string`. Kiểu chuỗi std::string. |
| 27 | <code>#include &lt;vector&gt;</code> | Nạp thư viện `vector`. Mảng động std::vector để lưu samples, events, tín hiệu. |
| 28 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 29 | <code>namespace smartbed {</code> | Mở namespace `smartbed` để gom toàn bộ code của bài, tránh trùng tên với thư viện hoặc project khác. |
| 30 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 31 | <code>constexpr double NaN = std::numeric_limits&lt;double&gt;::quiet_NaN();</code> | Khai báo hằng `NaN` để biểu diễn dữ liệu không hợp lệ/missing, ví dụ HR dropout. |
| 32 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 33 | <code>struct Thresholds {</code> | Bắt đầu struct `Thresholds`, gom tất cả ngưỡng cấu hình để dễ chỉnh/tune thuật toán. |
| 34 | <code>    double load_enter_kg = 18.0;</code> | Khai báo `load_enter_kg` = `18.0`. Ngưỡng loadcell để xác nhận có người lên giường; dùng hysteresis để tránh nhảy trạng thái. |
| 35 | <code>    double load_exit_kg = 8.0;</code> | Khai báo `load_exit_kg` = `8.0`. Ngưỡng thấp để xác nhận giường trống khi radar cũng không thấy người. |
| 36 | <code>    double motion_moving = 0.25;</code> | Khai báo `motion_moving` = `0.25`. Ngưỡng motion_intensity để phân loại người đang cử động. |
| 37 | <code>    double motion_leaving = 0.35;</code> | Khai báo `motion_leaving` = `0.35`. Ngưỡng motion liên quan đến hành vi rời giường; hiện chủ yếu dùng motion_moving và load slope. |
| 38 | <code>    double load_slope_leaving_kg_s = -8.0;</code> | Khai báo `load_slope_leaving_kg_s` = `-8.0`. Nếu tải giảm nhanh hơn ngưỡng này thì nghi ngờ người đang rời giường. |
| 39 | <code>    double min_state_hold_s = 1.0;</code> | Khai báo `min_state_hold_s` = `1.0`. Thời gian giữ tối thiểu để tránh trạng thái bị nhấp nháy do nhiễu. |
| 40 | <code>    double apnea_seconds = 10.0;</code> | Khai báo `apnea_seconds` = `10.0`. Số giây biên độ thở thấp liên tục trước khi báo apnea. |
| 41 | <code>    double apnea_abs_amp = 0.003;</code> | Khai báo `apnea_abs_amp` = `0.003`. Ngưỡng biên độ thở tuyệt đối tối thiểu để xem là gần như không thở. |
| 42 | <code>    double apnea_fraction_of_baseline = 0.20;</code> | Khai báo `apnea_fraction_of_baseline` = `0.20`. Ngưỡng apnea động theo phần trăm baseline biên độ thở. |
| 43 | <code>    // SpO2 is a corroborating signal for apnea/desaturation. It is not the</code> | Chú thích trong code: SpO2 is a corroborating signal for apnea/desaturation. It is not the |
| 44 | <code>    // primary trigger because pulse oximetry can lag breathing changes and can</code> | Chú thích trong code: primary trigger because pulse oximetry can lag breathing changes and can |
| 45 | <code>    // have dropouts, but it strengthens the event evidence when it drops.</code> | Chú thích trong code: have dropouts, but it strengthens the event evidence when it drops. |
| 46 | <code>    double spo2_low_pct = 94.0;</code> | Khai báo `spo2_low_pct` = `94.0`. Ngưỡng SpO₂ thấp dùng làm tín hiệu phụ xác nhận apnea/desaturation. |
| 47 | <code>    double spo2_drop_pct = 3.0;</code> | Khai báo `spo2_drop_pct` = `3.0`. Mức tụt SpO₂ so với baseline để hỗ trợ cảnh báo apnea. |
| 48 | <code>    double spo2_baseline_window_s = 60.0;</code> | Khai báo `spo2_baseline_window_s` = `60.0`. Khoảng thời gian trước apnea dùng để tính baseline SpO₂. |
| 49 | <code>    double spo2_recent_window_s = 20.0;</code> | Khai báo `spo2_recent_window_s` = `20.0`. Khoảng thời gian gần hiện tại dùng để tìm SpO₂ thấp nhất. |
| 50 | <code>    double rr_window_s = 30.0;</code> | Khai báo `rr_window_s` = `30.0`. Độ dài cửa sổ trượt để ước lượng nhịp thở. |
| 51 | <code>    double rr_update_s = 5.0;</code> | Khai báo `rr_update_s` = `5.0`. Chu kỳ cập nhật nhịp thở; tránh log RR quá dày. |
| 52 | <code>    double min_peak_distance_s = 1.5;</code> | Khai báo `min_peak_distance_s` = `1.5`. Khoảng cách tối thiểu giữa hai đỉnh thở để loại nhiễu. |
| 53 | <code>    double max_peak_distance_s = 10.0;</code> | Khai báo `max_peak_distance_s` = `10.0`. Khoảng cách tối đa giữa hai đỉnh thở hợp lệ. |
| 54 | <code>    double still_motion_for_rr = 0.18;</code> | Khai báo `still_motion_for_rr` = `0.18`. Chỉ tính nhịp thở khi motion thấp hơn ngưỡng này. |
| 55 | <code>};</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 56 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 57 | <code>struct SensorSample {</code> | Bắt đầu struct `SensorSample`, đại diện cho một dòng dữ liệu cảm biến trong CSV và các trường kết quả sau xử lý. |
| 58 | <code>    double timestamp_s = 0.0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 59 | <code>    double loadcell_kg = 0.0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 60 | <code>    int presence = 0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 61 | <code>    double motion_intensity = 0.0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 62 | <code>    double chest_disp = 0.0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 63 | <code>    double hr_bpm = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 64 | <code>    double spo2 = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 65 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 66 | <code>    // Cleaned fields.</code> | Chú thích trong code: Cleaned fields. |
| 67 | <code>    double hr_valid = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 68 | <code>    double hr_filled = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 69 | <code>    double spo2_valid = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 70 | <code>    double spo2_filled = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 71 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 72 | <code>    // Output fields.</code> | Chú thích trong code: Output fields. |
| 73 | <code>    std::string state = &quot;EMPTY&quot;;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 74 | <code>    double resp_rate_bpm = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 75 | <code>    std::string resp_quality = &quot;skipped&quot;;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 76 | <code>    double breath_amp = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 77 | <code>    double apnea_amp_threshold = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 78 | <code>    double spo2_apnea_baseline = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 79 | <code>    double spo2_apnea_recent_min = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 80 | <code>    double spo2_apnea_drop = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 81 | <code>    int spo2_supports_apnea = 0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 82 | <code>};</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 83 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 84 | <code>struct Event {</code> | Bắt đầu struct `Event`, dùng để lưu một sự kiện cần ghi log theo thời gian. |
| 85 | <code>    double timestamp_s = 0.0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 86 | <code>    std::string kind;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 87 | <code>    std::string message;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 88 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 89 | <code>    std::string toLogLine() const {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 90 | <code>        std::ostringstream oss;</code> | Tạo stream chuỗi để ghép message/log có định dạng. |
| 91 | <code>        oss &lt;&lt; std::fixed &lt;&lt; std::setw(8) &lt;&lt; std::setprecision(2) &lt;&lt; timestamp_s</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 92 | <code>            &lt;&lt; &quot;s &#124; &quot; &lt;&lt; std::left &lt;&lt; std::setw(12) &lt;&lt; kind &lt;&lt; &quot; &#124; &quot; &lt;&lt; message;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 93 | <code>        return oss.str();</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 94 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 95 | <code>};</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 96 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 97 | <code>struct RespirationEstimate {</code> | Bắt đầu struct `RespirationEstimate`, chứa kết quả ước lượng nhịp thở tại một thời điểm. |
| 98 | <code>    double timestamp_s = 0.0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 99 | <code>    double rr_bpm = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 100 | <code>    std::string quality;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 101 | <code>    double amplitude = 0.0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 102 | <code>};</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 103 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 104 | <code>struct SpO2Evidence {</code> | Bắt đầu struct `SpO2Evidence`, chứa bằng chứng SpO₂ hỗ trợ cho cảnh báo apnea. |
| 105 | <code>    double baseline = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 106 | <code>    double recent_min = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 107 | <code>    double drop_from_baseline = NaN;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 108 | <code>    bool supports_apnea = false;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 109 | <code>};</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 110 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 111 | <code>static bool isFinite(double x) {</code> | Khai báo/bắt đầu hàm `isFinite`. Hàm kiểm tra một số có hợp lệ không, loại NaN/inf. |
| 112 | <code>    return std::isfinite(x);</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 113 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 114 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 115 | <code>static std::string trim(const std::string&amp; s) {</code> | Khai báo/bắt đầu hàm `trim`. Hàm xóa khoảng trắng đầu/cuối chuỗi. |
| 116 | <code>    const auto begin = s.find_first_not_of(&quot; \t\r\n&quot;);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 117 | <code>    if (begin == std::string::npos) return &quot;&quot;;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 118 | <code>    const auto end = s.find_last_not_of(&quot; \t\r\n&quot;);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 119 | <code>    return s.substr(begin, end - begin + 1);</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 120 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 121 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 122 | <code>static std::vector&lt;std::string&gt; splitCsvLine(const std::string&amp; line) {</code> | Khai báo/bắt đầu hàm `splitCsvLine`. Hàm tách một dòng CSV thành các cột. |
| 123 | <code>    // Simple CSV splitter for the HR-provided file: numeric fields, no quoted commas.</code> | Chú thích trong code: Simple CSV splitter for the HR-provided file: numeric fields, no quoted commas. |
| 124 | <code>    std::vector&lt;std::string&gt; cols;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 125 | <code>    std::string cur;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 126 | <code>    std::stringstream ss(line);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 127 | <code>    while (std::getline(ss, cur, &#x27;,&#x27;)) cols.push_back(trim(cur));</code> | Vòng lặp `while`: lặp khi điều kiện còn đúng, thường dùng để đọc file hoặc binary search. |
| 128 | <code>    if (!line.empty() &amp;&amp; line.back() == &#x27;,&#x27;) cols.emplace_back(&quot;&quot;);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 129 | <code>    return cols;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 130 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 131 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 132 | <code>static double parseDouble(const std::string&amp; s, const std::string&amp; col, std::size_t line_no) {</code> | Khai báo/bắt đầu hàm `parseDouble`. Hàm chuyển chuỗi CSV thành số double và báo lỗi nếu không parse được. |
| 133 | <code>    const std::string t = trim(s);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 134 | <code>    if (t.empty()) return NaN;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 135 | <code>    char* end = nullptr;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 136 | <code>    const double value = std::strtod(t.c_str(), &amp;end);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 137 | <code>    if (end == t.c_str()) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 138 | <code>        std::ostringstream oss;</code> | Tạo stream chuỗi để ghép message/log có định dạng. |
| 139 | <code>        oss &lt;&lt; &quot;Invalid numeric value in column &#x27;&quot; &lt;&lt; col &lt;&lt; &quot;&#x27; at line &quot; &lt;&lt; line_no &lt;&lt; &quot;: &#x27;&quot; &lt;&lt; s &lt;&lt; &quot;&#x27;&quot;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 140 | <code>        throw std::runtime_error(oss.str());</code> | Báo lỗi bằng exception khi file/input/output không hợp lệ. |
| 141 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 142 | <code>    return value;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 143 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 144 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 145 | <code>static std::vector&lt;SensorSample&gt; readCsv(const std::string&amp; path) {</code> | Khai báo/bắt đầu hàm `readCsv`. Hàm đọc file CSV, kiểm tra cột bắt buộc, parse dữ liệu, sort timestamp và bỏ dòng trùng. |
| 146 | <code>    std::ifstream in(path);</code> | Mở file input để đọc dữ liệu. |
| 147 | <code>    if (!in) throw std::runtime_error(&quot;Cannot open CSV: &quot; + path);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 148 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 149 | <code>    std::string line;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 150 | <code>    if (!std::getline(in, line)) throw std::runtime_error(&quot;CSV is empty: &quot; + path);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 151 | <code>    const auto header = splitCsvLine(line);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 152 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 153 | <code>    std::map&lt;std::string, std::size_t&gt; idx;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 154 | <code>    for (std::size_t i = 0; i &lt; header.size(); ++i) idx[header[i]] = i;</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 155 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 156 | <code>    const std::vector&lt;std::string&gt; required = {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 157 | <code>        &quot;timestamp_s&quot;, &quot;loadcell_kg&quot;, &quot;presence&quot;, &quot;motion_intensity&quot;, &quot;chest_disp&quot;, &quot;hr_bpm&quot;, &quot;spo2&quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 158 | <code>    };</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 159 | <code>    for (const auto&amp; name : required) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 160 | <code>        if (idx.find(name) == idx.end()) throw std::runtime_error(&quot;Missing required column: &quot; + name);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 161 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 162 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 163 | <code>    std::vector&lt;SensorSample&gt; samples;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 164 | <code>    std::size_t line_no = 1;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 165 | <code>    while (std::getline(in, line)) {</code> | Vòng lặp `while`: lặp khi điều kiện còn đúng, thường dùng để đọc file hoặc binary search. |
| 166 | <code>        ++line_no;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 167 | <code>        if (trim(line).empty()) continue;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 168 | <code>        const auto cols = splitCsvLine(line);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 169 | <code>        auto get = [&amp;](const std::string&amp; name) -&gt; std::string {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 170 | <code>            const std::size_t pos = idx.at(name);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 171 | <code>            return pos &lt; cols.size() ? cols[pos] : &quot;&quot;;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 172 | <code>        };</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 173 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 174 | <code>        SensorSample s;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 175 | <code>        s.timestamp_s = parseDouble(get(&quot;timestamp_s&quot;), &quot;timestamp_s&quot;, line_no);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 176 | <code>        s.loadcell_kg = parseDouble(get(&quot;loadcell_kg&quot;), &quot;loadcell_kg&quot;, line_no);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 177 | <code>        s.presence = parseDouble(get(&quot;presence&quot;), &quot;presence&quot;, line_no) &gt;= 0.5 ? 1 : 0;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 178 | <code>        s.motion_intensity = parseDouble(get(&quot;motion_intensity&quot;), &quot;motion_intensity&quot;, line_no);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 179 | <code>        s.chest_disp = parseDouble(get(&quot;chest_disp&quot;), &quot;chest_disp&quot;, line_no);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 180 | <code>        s.hr_bpm = parseDouble(get(&quot;hr_bpm&quot;), &quot;hr_bpm&quot;, line_no);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 181 | <code>        s.spo2 = parseDouble(get(&quot;spo2&quot;), &quot;spo2&quot;, line_no);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 182 | <code>        samples.push_back(s);</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 183 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 184 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 185 | <code>    std::sort(samples.begin(), samples.end(), [](const auto&amp; a, const auto&amp; b) {</code> | Sắp xếp dữ liệu, thường để đảm bảo thứ tự thời gian hoặc chuẩn bị tính percentile. |
| 186 | <code>        return a.timestamp_s &lt; b.timestamp_s;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 187 | <code>    });</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 188 | <code>    samples.erase(std::unique(samples.begin(), samples.end(), [](const auto&amp; a, const auto&amp; b) {</code> | Loại bỏ phần tử trùng liền kề, dùng sau khi sort timestamp để bỏ dòng CSV trùng thời gian. |
| 189 | <code>        return a.timestamp_s == b.timestamp_s;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 190 | <code>    }), samples.end());</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 191 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 192 | <code>    return samples;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 193 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 194 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 195 | <code>static std::vector&lt;double&gt; interpolateShortGaps(const std::vector&lt;double&gt;&amp; values, std::size_t max_gap_samples) {</code> | Khai báo/bắt đầu hàm `interpolateShortGaps`. Hàm nội suy các đoạn dropout ngắn trong HR/SpO₂. |
| 196 | <code>    std::vector&lt;double&gt; out(values.size(), NaN);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 197 | <code>    if (values.empty()) return out;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 198 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 199 | <code>    std::vector&lt;std::size_t&gt; valid;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 200 | <code>    for (std::size_t i = 0; i &lt; values.size(); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 201 | <code>        if (isFinite(values[i])) valid.push_back(i);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 202 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 203 | <code>    if (valid.empty()) return out;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 204 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 205 | <code>    // Copy valid samples.</code> | Chú thích trong code: Copy valid samples. |
| 206 | <code>    for (auto i : valid) out[i] = values[i];</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 207 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 208 | <code>    // Fill leading/trailing short gaps using nearest valid value.</code> | Chú thích trong code: Fill leading/trailing short gaps using nearest valid value. |
| 209 | <code>    const std::size_t first = valid.front();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 210 | <code>    if (first &lt;= max_gap_samples) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 211 | <code>        for (std::size_t i = 0; i &lt; first; ++i) out[i] = values[first];</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 212 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 213 | <code>    const std::size_t last = valid.back();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 214 | <code>    if (values.size() - 1 - last &lt;= max_gap_samples) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 215 | <code>        for (std::size_t i = last + 1; i &lt; values.size(); ++i) out[i] = values[last];</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 216 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 217 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 218 | <code>    // Linear interpolation for internal short gaps.</code> | Chú thích trong code: Linear interpolation for internal short gaps. |
| 219 | <code>    for (std::size_t k = 0; k + 1 &lt; valid.size(); ++k) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 220 | <code>        const std::size_t a = valid[k];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 221 | <code>        const std::size_t b = valid[k + 1];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 222 | <code>        const std::size_t gap = b - a - 1;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 223 | <code>        if (gap == 0 &#124;&#124; gap &gt; max_gap_samples) continue;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 224 | <code>        for (std::size_t i = a + 1; i &lt; b; ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 225 | <code>            const double alpha = static_cast&lt;double&gt;(i - a) / static_cast&lt;double&gt;(b - a);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 226 | <code>            out[i] = values[a] * (1.0 - alpha) + values[b] * alpha;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 227 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 228 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 229 | <code>    return out;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 230 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 231 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 232 | <code>static void cleanSamples(std::vector&lt;SensorSample&gt;&amp; samples) {</code> | Khai báo/bắt đầu hàm `cleanSamples`. Hàm làm sạch dữ liệu đầu vào: HR=0 thành invalid, chuẩn hóa presence, nội suy dropout ngắn. |
| 233 | <code>    std::vector&lt;double&gt; hr_valid(samples.size(), NaN), spo2_valid(samples.size(), NaN);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 234 | <code>    for (std::size_t i = 0; i &lt; samples.size(); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 235 | <code>        samples[i].presence = samples[i].presence ? 1 : 0;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 236 | <code>        if (isFinite(samples[i].hr_bpm) &amp;&amp; samples[i].hr_bpm &gt; 0.0) hr_valid[i] = samples[i].hr_bpm;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 237 | <code>        if (isFinite(samples[i].spo2) &amp;&amp; samples[i].spo2 &gt; 0.0) spo2_valid[i] = samples[i].spo2;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 238 | <code>        samples[i].hr_valid = hr_valid[i];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 239 | <code>        samples[i].spo2_valid = spo2_valid[i];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 240 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 241 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 242 | <code>    const auto hr_filled = interpolateShortGaps(hr_valid, 50);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 243 | <code>    const auto spo2_filled = interpolateShortGaps(spo2_valid, 50);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 244 | <code>    for (std::size_t i = 0; i &lt; samples.size(); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 245 | <code>        samples[i].hr_filled = hr_filled[i];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 246 | <code>        samples[i].spo2_filled = spo2_filled[i];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 247 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 248 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 249 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 250 | <code>class StateClassifier {</code> | Bắt đầu class `StateClassifier`, chịu trách nhiệm phân loại EMPTY/LYING_STILL/MOVING/LEAVING bằng sensor fusion. |
| 251 | <code>public:</code> | Vùng `public:` của class: quy định thành phần nào được gọi từ bên ngoài và thành phần nào chỉ dùng nội bộ. |
| 252 | <code>    explicit StateClassifier(const Thresholds&amp; thresholds) : t_(thresholds) {}</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 253 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 254 | <code>    std::string classify(const SensorSample&amp; row) {</code> | Khai báo/bắt đầu hàm `classify`. Hàm phân loại trạng thái của giường tại một sample. |
| 255 | <code>        const double ts = row.timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 256 | <code>        const double load = row.loadcell_kg;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 257 | <code>        const int presence = row.presence;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 258 | <code>        const double motion = row.motion_intensity;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 259 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 260 | <code>        load_history_.push_back({ts, load});</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 261 | <code>        if (load_history_.size() &gt; 30) load_history_.pop_front();</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 262 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 263 | <code>        double slope = 0.0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 264 | <code>        if (load_history_.size() &gt;= 2) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 265 | <code>            const auto&amp; old = load_history_.front();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 266 | <code>            if (ts - old.first &gt;= 1.5) slope = (load - old.second) / (ts - old.first);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 267 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 268 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 269 | <code>        if (occupied_) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 270 | <code>            if (presence == 0 &amp;&amp; load &lt; t_.load_exit_kg) occupied_ = false;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 271 | <code>        } else {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 272 | <code>            if ((presence == 1 &amp;&amp; load &gt;= t_.load_exit_kg) &#124;&#124; load &gt;= t_.load_enter_kg) occupied_ = true;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 273 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 274 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 275 | <code>        std::string candidate;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 276 | <code>        if (!occupied_) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 277 | <code>            candidate = &quot;EMPTY&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 278 | <code>        } else {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 279 | <code>            const bool load_falling_fast = slope &lt;= t_.load_slope_leaving_kg_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 280 | <code>            const bool near_empty = load &lt; t_.load_enter_kg;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 281 | <code>            const bool leaving_by_slope = near_empty &amp;&amp; load_falling_fast &amp;&amp; motion &gt;= t_.motion_moving;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 282 | <code>            const bool leaving_by_radar_loss = near_empty &amp;&amp; presence == 0 &amp;&amp; state_ != &quot;EMPTY&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 283 | <code>            if (leaving_by_slope &#124;&#124; leaving_by_radar_loss) candidate = &quot;LEAVING&quot;;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 284 | <code>            else if (motion &gt;= t_.motion_moving) candidate = &quot;MOVING&quot;;</code> | Nhánh điều kiện phụ `else if`: chỉ kiểm tra khi các nhánh trước không thỏa. |
| 285 | <code>            else candidate = &quot;LYING_STILL&quot;;</code> | Nhánh `else`: xử lý trường hợp còn lại khi điều kiện phía trên không đúng. |
| 286 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 287 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 288 | <code>        if (candidate != state_) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 289 | <code>            const bool enough_hold = (ts - last_state_change_) &gt;= t_.min_state_hold_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 290 | <code>            const bool urgent = (candidate == &quot;EMPTY&quot; &#124;&#124; candidate == &quot;LEAVING&quot;);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 291 | <code>            if (enough_hold &#124;&#124; urgent) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 292 | <code>                state_ = candidate;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 293 | <code>                last_state_change_ = ts;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 294 | <code>            }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 295 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 296 | <code>        return state_;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 297 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 298 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 299 | <code>private:</code> | Vùng `private:` của class: quy định thành phần nào được gọi từ bên ngoài và thành phần nào chỉ dùng nội bộ. |
| 300 | <code>    Thresholds t_;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 301 | <code>    std::string state_ = &quot;EMPTY&quot;;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 302 | <code>    bool occupied_ = false;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 303 | <code>    double last_state_change_ = -std::numeric_limits&lt;double&gt;::infinity();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 304 | <code>    std::deque&lt;std::pair&lt;double, double&gt;&gt; load_history_;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 305 | <code>};</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 306 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 307 | <code>static double percentileFromSorted(const std::vector&lt;double&gt;&amp; sorted_values, double p) {</code> | Khai báo/bắt đầu hàm `percentileFromSorted`. Hàm lấy percentile từ vector đã sort. |
| 308 | <code>    if (sorted_values.empty()) return NaN;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 309 | <code>    if (sorted_values.size() == 1) return sorted_values.front();</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 310 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 311 | <code>    const double rank = (p / 100.0) * static_cast&lt;double&gt;(sorted_values.size() - 1);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 312 | <code>    const std::size_t lo = static_cast&lt;std::size_t&gt;(std::floor(rank));</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 313 | <code>    const std::size_t hi = static_cast&lt;std::size_t&gt;(std::ceil(rank));</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 314 | <code>    const double frac = rank - static_cast&lt;double&gt;(lo);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 315 | <code>    return sorted_values[lo] * (1.0 - frac) + sorted_values[hi] * frac;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 316 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 317 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 318 | <code>static double percentile(std::vector&lt;double&gt; values, double p) {</code> | Khai báo/bắt đầu hàm `percentile`. Hàm lọc giá trị hợp lệ, sort rồi lấy percentile. |
| 319 | <code>    // The vector is intentionally passed by value because percentile calculation</code> | Chú thích trong code: The vector is intentionally passed by value because percentile calculation |
| 320 | <code>    // reorders samples. For this 10-minute/10 Hz task the window sizes are small,</code> | Chú thích trong code: reorders samples. For this 10-minute/10 Hz task the window sizes are small, |
| 321 | <code>    // but filtering once and sorting once keeps the implementation predictable.</code> | Chú thích trong code: but filtering once and sorting once keeps the implementation predictable. |
| 322 | <code>    values.erase(std::remove_if(values.begin(), values.end(), [](double x) { return !isFinite(x); }), values.end());</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 323 | <code>    if (values.empty()) return NaN;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 324 | <code>    std::sort(values.begin(), values.end());</code> | Sắp xếp dữ liệu, thường để đảm bảo thứ tự thời gian hoặc chuẩn bị tính percentile. |
| 325 | <code>    return percentileFromSorted(values, p);</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 326 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 327 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 328 | <code>static double windowAmplitude(const std::vector&lt;double&gt;&amp; values) {</code> | Khai báo/bắt đầu hàm `windowAmplitude`. Hàm tính biên độ tín hiệu robust bằng q95-q05. |
| 329 | <code>    // Robust peak-to-peak amplitude using q95-q05. Filter and sort once instead</code> | Chú thích trong code: Robust peak-to-peak amplitude using q95-q05. Filter and sort once instead |
| 330 | <code>    // of computing two separate percentiles with two vector copies/sorts.</code> | Chú thích trong code: of computing two separate percentiles with two vector copies/sorts. |
| 331 | <code>    std::vector&lt;double&gt; finite;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 332 | <code>    finite.reserve(values.size());</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 333 | <code>    for (double x : values) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 334 | <code>        if (isFinite(x)) finite.push_back(x);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 335 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 336 | <code>    if (finite.empty()) return 0.0;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 337 | <code>    std::sort(finite.begin(), finite.end());</code> | Sắp xếp dữ liệu, thường để đảm bảo thứ tự thời gian hoặc chuẩn bị tính percentile. |
| 338 | <code>    const double q95 = percentileFromSorted(finite, 95.0);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 339 | <code>    const double q05 = percentileFromSorted(finite, 5.0);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 340 | <code>    if (!isFinite(q95) &#124;&#124; !isFinite(q05)) return 0.0;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 341 | <code>    return std::max(0.0, q95 - q05);</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 342 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 343 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 344 | <code>static std::vector&lt;double&gt; movingAverage(const std::vector&lt;double&gt;&amp; values, int n) {</code> | Khai báo/bắt đầu hàm `movingAverage`. Hàm làm mượt tín hiệu bằng trung bình trượt edge-aware. |
| 345 | <code>    if (n &lt;= 1 &#124;&#124; values.empty()) return values;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 346 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 347 | <code>    // Edge-aware moving average. At the first/last samples, average only real</code> | Chú thích trong code: Edge-aware moving average. At the first/last samples, average only real |
| 348 | <code>    // samples inside the truncated window instead of zero/repeated padding.</code> | Chú thích trong code: samples inside the truncated window instead of zero/repeated padding. |
| 349 | <code>    // This avoids artificially reducing breathing amplitude near window edges.</code> | Chú thích trong code: This avoids artificially reducing breathing amplitude near window edges. |
| 350 | <code>    std::vector&lt;double&gt; prefix(values.size() + 1, 0.0);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 351 | <code>    for (std::size_t i = 0; i &lt; values.size(); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 352 | <code>        prefix[i + 1] = prefix[i] + values[i];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 353 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 354 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 355 | <code>    std::vector&lt;double&gt; out(values.size(), 0.0);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 356 | <code>    const int left = n / 2;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 357 | <code>    const int right = n - 1 - left;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 358 | <code>    for (std::size_t i = 0; i &lt; values.size(); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 359 | <code>        const long begin_long = std::max&lt;long&gt;(0, static_cast&lt;long&gt;(i) - left);</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 360 | <code>        const long end_long = std::min&lt;long&gt;(static_cast&lt;long&gt;(values.size()) - 1,</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 361 | <code>                                             static_cast&lt;long&gt;(i) + right);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 362 | <code>        const std::size_t begin = static_cast&lt;std::size_t&gt;(begin_long);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 363 | <code>        const std::size_t end_exclusive = static_cast&lt;std::size_t&gt;(end_long + 1);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 364 | <code>        const double count = static_cast&lt;double&gt;(end_exclusive - begin);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 365 | <code>        out[i] = (prefix[end_exclusive] - prefix[begin]) / count;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 366 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 367 | <code>    return out;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 368 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 369 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 370 | <code>static std::vector&lt;double&gt; interpolateFinite(const std::vector&lt;double&gt;&amp; ts, const std::vector&lt;double&gt;&amp; raw) {</code> | Khai báo/bắt đầu hàm `interpolateFinite`. Hàm nội suy các giá trị missing trong chuỗi chest_disp. |
| 371 | <code>    std::vector&lt;double&gt; out = raw;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 372 | <code>    std::vector&lt;std::size_t&gt; valid;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 373 | <code>    for (std::size_t i = 0; i &lt; raw.size(); ++i) if (isFinite(raw[i])) valid.push_back(i);</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 374 | <code>    if (valid.empty()) return out;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 375 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 376 | <code>    for (std::size_t i = 0; i &lt; valid.front(); ++i) out[i] = raw[valid.front()];</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 377 | <code>    for (std::size_t i = valid.back() + 1; i &lt; raw.size(); ++i) out[i] = raw[valid.back()];</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 378 | <code>    for (std::size_t k = 0; k + 1 &lt; valid.size(); ++k) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 379 | <code>        const std::size_t a = valid[k], b = valid[k + 1];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 380 | <code>        for (std::size_t i = a + 1; i &lt; b; ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 381 | <code>            const double alpha = (ts[i] - ts[a]) / (ts[b] - ts[a]);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 382 | <code>            out[i] = raw[a] * (1.0 - alpha) + raw[b] * alpha;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 383 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 384 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 385 | <code>    return out;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 386 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 387 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 388 | <code>class RespiratoryRateEstimator {</code> | Bắt đầu class `RespiratoryRateEstimator`, chịu trách nhiệm lọc chest_disp, tìm đỉnh thở và tính breaths/min. |
| 389 | <code>public:</code> | Vùng `public:` của class: quy định thành phần nào được gọi từ bên ngoài và thành phần nào chỉ dùng nội bộ. |
| 390 | <code>    explicit RespiratoryRateEstimator(const Thresholds&amp; thresholds) : t_(thresholds) {}</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 391 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 392 | <code>    RespirationEstimate estimate(const std::vector&lt;SensorSample&gt;&amp; samples,</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 393 | <code>                                 std::size_t start_idx,</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 394 | <code>                                 std::size_t end_idx,</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 395 | <code>                                 double current_ts,</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 396 | <code>                                 bool force = false) {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 397 | <code>        if (!force &amp;&amp; (current_ts - last_update_ts_) &lt; t_.rr_update_s) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 398 | <code>            return {current_ts, NaN, &quot;not_due&quot;, 0.0};</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 399 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 400 | <code>        last_update_ts_ = current_ts;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 401 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 402 | <code>        if (end_idx &lt; start_idx &#124;&#124; (end_idx - start_idx + 1) &lt; 5) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 403 | <code>            return {current_ts, NaN, &quot;not_enough_data&quot;, 0.0};</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 404 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 405 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 406 | <code>        std::vector&lt;double&gt; ts;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 407 | <code>        std::vector&lt;double&gt; raw;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 408 | <code>        ts.reserve(end_idx - start_idx + 1);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 409 | <code>        raw.reserve(end_idx - start_idx + 1);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 410 | <code>        for (std::size_t i = start_idx; i &lt;= end_idx; ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 411 | <code>            ts.push_back(samples[i].timestamp_s);</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 412 | <code>            raw.push_back(samples[i].chest_disp);</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 413 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 414 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 415 | <code>        const std::size_t finite_count = static_cast&lt;std::size_t&gt;(std::count_if(raw.begin(), raw.end(), isFinite));</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 416 | <code>        if (finite_count &lt; 5) return {current_ts, NaN, &quot;bad_signal&quot;, 0.0};</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 417 | <code>        raw = interpolateFinite(ts, raw);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 418 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 419 | <code>        const double duration = ts.back() - ts.front();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 420 | <code>        if (duration &lt; 12.0) return {current_ts, NaN, &quot;window_too_short&quot;, windowAmplitude(raw)};</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 421 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 422 | <code>        std::vector&lt;double&gt; diffs;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 423 | <code>        diffs.reserve(ts.size() - 1);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 424 | <code>        for (std::size_t i = 1; i &lt; ts.size(); ++i) diffs.push_back(ts[i] - ts[i - 1]);</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 425 | <code>        const double dt = percentile(diffs, 50.0);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 426 | <code>        const double fs = dt &gt; 0.0 ? 1.0 / dt : 10.0;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 427 | <code>        const int smooth_n = std::max(1, static_cast&lt;int&gt;(std::llround(0.5 * fs)));</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 428 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 429 | <code>        const auto smoothed = movingAverage(raw, smooth_n);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 430 | <code>        const auto trend = movingAverage(smoothed, std::max(smooth_n * 8, 3));</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 431 | <code>        std::vector&lt;double&gt; detrended(smoothed.size(), 0.0);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 432 | <code>        for (std::size_t i = 0; i &lt; smoothed.size(); ++i) detrended[i] = smoothed[i] - trend[i];</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 433 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 434 | <code>        const double amplitude = windowAmplitude(detrended);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 435 | <code>        if (amplitude &lt; t_.apnea_abs_amp) return {current_ts, NaN, &quot;low_amplitude&quot;, amplitude};</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 436 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 437 | <code>        const int min_dist = std::max(1, static_cast&lt;int&gt;(std::llround(t_.min_peak_distance_s * fs)));</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 438 | <code>        const double peak_threshold = std::max(0.10 * amplitude, 1e-9);</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 439 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 440 | <code>        std::vector&lt;int&gt; peaks;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 441 | <code>        int last_peak = -1000000000;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 442 | <code>        for (int i = 1; i + 1 &lt; static_cast&lt;int&gt;(detrended.size()); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 443 | <code>            const bool is_peak = detrended[i] &gt; detrended[i - 1] &amp;&amp; detrended[i] &gt;= detrended[i + 1];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 444 | <code>            if (!is_peak &#124;&#124; detrended[i] &lt; peak_threshold) continue;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 445 | <code>            if (i - last_peak &lt; min_dist) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 446 | <code>                if (!peaks.empty() &amp;&amp; detrended[i] &gt; detrended[static_cast&lt;std::size_t&gt;(peaks.back())]) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 447 | <code>                    peaks.back() = i;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 448 | <code>                    last_peak = i;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 449 | <code>                }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 450 | <code>                continue;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 451 | <code>            }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 452 | <code>            peaks.push_back(i);</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 453 | <code>            last_peak = i;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 454 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 455 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 456 | <code>        if (peaks.size() &lt; 3) return {current_ts, NaN, &quot;few_peaks&quot;, amplitude};</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 457 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 458 | <code>        std::vector&lt;double&gt; intervals;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 459 | <code>        for (std::size_t i = 1; i &lt; peaks.size(); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 460 | <code>            const double interval = ts[static_cast&lt;std::size_t&gt;(peaks[i])] - ts[static_cast&lt;std::size_t&gt;(peaks[i - 1])];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 461 | <code>            if (interval &gt;= t_.min_peak_distance_s &amp;&amp; interval &lt;= t_.max_peak_distance_s) intervals.push_back(interval);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 462 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 463 | <code>        if (intervals.size() &lt; 2) return {current_ts, NaN, &quot;bad_intervals&quot;, amplitude};</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 464 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 465 | <code>        const double median_period = percentile(intervals, 50.0);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 466 | <code>        const double rr = median_period &gt; 0.0 ? 60.0 / median_period : NaN;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 467 | <code>        if (!isFinite(rr) &#124;&#124; rr &lt; 6.0 &#124;&#124; rr &gt; 40.0) return {current_ts, NaN, &quot;out_of_range&quot;, amplitude};</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 468 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 469 | <code>        baseline_amplitudes_.push_back(amplitude);</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 470 | <code>        if (baseline_amplitudes_.size() &gt; 60) baseline_amplitudes_.erase(baseline_amplitudes_.begin());</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 471 | <code>        return {current_ts, rr, &quot;ok&quot;, amplitude};</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 472 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 473 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 474 | <code>    double apneaThreshold() const {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 475 | <code>        if (baseline_amplitudes_.empty()) return t_.apnea_abs_amp;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 476 | <code>        const std::size_t n = baseline_amplitudes_.size();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 477 | <code>        const std::size_t start = n &gt; 30 ? n - 30 : 0;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 478 | <code>        std::vector&lt;double&gt; recent(baseline_amplitudes_.begin() + static_cast&lt;long&gt;(start), baseline_amplitudes_.end());</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 479 | <code>        const double baseline = percentile(recent, 50.0);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 480 | <code>        return std::max(t_.apnea_abs_amp, t_.apnea_fraction_of_baseline * baseline);</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 481 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 482 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 483 | <code>private:</code> | Vùng `private:` của class: quy định thành phần nào được gọi từ bên ngoài và thành phần nào chỉ dùng nội bộ. |
| 484 | <code>    Thresholds t_;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 485 | <code>    double last_update_ts_ = -std::numeric_limits&lt;double&gt;::infinity();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 486 | <code>    std::vector&lt;double&gt; baseline_amplitudes_;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 487 | <code>};</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 488 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 489 | <code>static std::size_t lowerBoundTimestamp(const std::vector&lt;SensorSample&gt;&amp; samples, double timestamp_s, std::size_t hi_exclusive) {</code> | Khai báo/bắt đầu hàm `lowerBoundTimestamp`. Hàm binary search tìm index đầu tiên có timestamp &gt;= mốc cần tìm. |
| 490 | <code>    std::size_t lo = 0, hi = hi_exclusive;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 491 | <code>    while (lo &lt; hi) {</code> | Vòng lặp `while`: lặp khi điều kiện còn đúng, thường dùng để đọc file hoặc binary search. |
| 492 | <code>        const std::size_t mid = lo + (hi - lo) / 2;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 493 | <code>        if (samples[mid].timestamp_s &lt; timestamp_s) lo = mid + 1;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 494 | <code>        else hi = mid;</code> | Nhánh `else`: xử lý trường hợp còn lại khi điều kiện phía trên không đúng. |
| 495 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 496 | <code>    return lo;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 497 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 498 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 499 | <code>static double recentChestAmplitude(const std::vector&lt;SensorSample&gt;&amp; samples, double start_ts, std::size_t end_idx) {</code> | Khai báo/bắt đầu hàm `recentChestAmplitude`. Hàm tính biên độ chest_disp trong vài giây gần nhất để phát hiện apnea. |
| 500 | <code>    const std::size_t start_idx = lowerBoundTimestamp(samples, start_ts, end_idx + 1);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 501 | <code>    std::vector&lt;double&gt; values;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 502 | <code>    values.reserve(end_idx - start_idx + 1);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 503 | <code>    for (std::size_t i = start_idx; i &lt;= end_idx; ++i) values.push_back(samples[i].chest_disp);</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 504 | <code>    return windowAmplitude(values);</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 505 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 506 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 507 | <code>static SpO2Evidence computeSpO2Evidence(const std::vector&lt;SensorSample&gt;&amp; samples,</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 508 | <code>                                          double apnea_start_ts,</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 509 | <code>                                          double current_ts,</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 510 | <code>                                          std::size_t end_idx,</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 511 | <code>                                          const Thresholds&amp; thresholds) {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 512 | <code>    SpO2Evidence evidence;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 513 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 514 | <code>    const double baseline_start_ts = apnea_start_ts - thresholds.spo2_baseline_window_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 515 | <code>    const double baseline_end_ts = apnea_start_ts;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 516 | <code>    const std::size_t baseline_start_idx = lowerBoundTimestamp(samples, baseline_start_ts, end_idx + 1);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 517 | <code>    const std::size_t recent_start_idx = lowerBoundTimestamp(samples,</code> | Khai báo biến hằng cục bộ, giúp tránh sửa nhầm giá trị trong logic xử lý. |
| 518 | <code>        std::max(apnea_start_ts, current_ts - thresholds.spo2_recent_window_s), end_idx + 1);</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 519 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 520 | <code>    std::vector&lt;double&gt; baseline_values;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 521 | <code>    std::vector&lt;double&gt; recent_values;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 522 | <code>    for (std::size_t k = baseline_start_idx; k &lt;= end_idx; ++k) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 523 | <code>        const auto&amp; sample = samples[k];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 524 | <code>        if (!isFinite(sample.spo2_filled) &#124;&#124; sample.spo2_filled &lt;= 0.0) continue;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 525 | <code>        if (sample.timestamp_s &gt;= baseline_start_ts &amp;&amp; sample.timestamp_s &lt; baseline_end_ts) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 526 | <code>            baseline_values.push_back(sample.spo2_filled);</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 527 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 528 | <code>        if (k &gt;= recent_start_idx &amp;&amp; sample.timestamp_s &lt;= current_ts) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 529 | <code>            recent_values.push_back(sample.spo2_filled);</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 530 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 531 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 532 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 533 | <code>    if (!baseline_values.empty()) evidence.baseline = percentile(baseline_values, 50.0);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 534 | <code>    if (!recent_values.empty()) evidence.recent_min = *std::min_element(recent_values.begin(), recent_values.end());</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 535 | <code>    if (isFinite(evidence.baseline) &amp;&amp; isFinite(evidence.recent_min)) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 536 | <code>        evidence.drop_from_baseline = evidence.baseline - evidence.recent_min;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 537 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 538 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 539 | <code>    evidence.supports_apnea =</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 540 | <code>        (isFinite(evidence.recent_min) &amp;&amp; evidence.recent_min &lt;= thresholds.spo2_low_pct) &#124;&#124;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 541 | <code>        (isFinite(evidence.drop_from_baseline) &amp;&amp; evidence.drop_from_baseline &gt;= thresholds.spo2_drop_pct);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 542 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 543 | <code>    return evidence;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 544 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 545 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 546 | <code>static std::vector&lt;Event&gt; processStream(std::vector&lt;SensorSample&gt;&amp; samples, const Thresholds&amp; thresholds) {</code> | Khai báo/bắt đầu hàm `processStream`. Hàm chính xử lý toàn bộ stream: clean, phân loại state, RR, apnea, events. |
| 547 | <code>    cleanSamples(samples);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 548 | <code>    StateClassifier classifier(thresholds);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 549 | <code>    RespiratoryRateEstimator rr_estimator(thresholds);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 550 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 551 | <code>    std::vector&lt;Event&gt; events;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 552 | <code>    std::optional&lt;std::string&gt; last_state;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 553 | <code>    std::optional&lt;double&gt; apnea_active_since;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 554 | <code>    bool apnea_reported = false;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 555 | <code>    double rr_suppressed_until = -std::numeric_limits&lt;double&gt;::infinity();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 556 | <code>    bool hr_dropout_active = false;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 557 | <code>    double hr_dropout_start = 0.0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 558 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 559 | <code>    for (std::size_t i = 0; i &lt; samples.size(); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 560 | <code>        auto&amp; row = samples[i];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 561 | <code>        const double ts = row.timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 562 | <code>        const std::string state = classifier.classify(row);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 563 | <code>        row.state = state;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 564 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 565 | <code>        if (!last_state.has_value() &#124;&#124; state != *last_state) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 566 | <code>            events.push_back({ts, &quot;STATE&quot;, (last_state.has_value() ? *last_state : &quot;START&quot;) + &quot; -&gt; &quot; + state});</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 567 | <code>            last_state = state;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 568 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 569 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 570 | <code>        const bool occupied_for_hr = (state == &quot;LYING_STILL&quot; &#124;&#124; state == &quot;MOVING&quot; &#124;&#124; state == &quot;LEAVING&quot;);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 571 | <code>        const bool bad_hr = (!isFinite(row.hr_bpm) &#124;&#124; row.hr_bpm &lt;= 0.0);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 572 | <code>        if (occupied_for_hr &amp;&amp; bad_hr) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 573 | <code>            if (!hr_dropout_active) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 574 | <code>                hr_dropout_active = true;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 575 | <code>                hr_dropout_start = ts;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 576 | <code>            }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 577 | <code>        } else if (hr_dropout_active) {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 578 | <code>            const double duration = ts - hr_dropout_start;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 579 | <code>            if (duration &gt;= 2.0) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 580 | <code>                std::ostringstream msg;</code> | Tạo stream chuỗi để ghép message/log có định dạng. |
| 581 | <code>                msg &lt;&lt; &quot;hr_bpm=0/invalid for &quot; &lt;&lt; std::fixed &lt;&lt; std::setprecision(1)</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 582 | <code>                    &lt;&lt; duration &lt;&lt; &quot;s while occupied; ignored/interpolated&quot;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 583 | <code>                events.push_back({hr_dropout_start, &quot;HR_DROPOUT&quot;, msg.str()});</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 584 | <code>            }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 585 | <code>            hr_dropout_active = false;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 586 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 587 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 588 | <code>        double apnea_thr = rr_estimator.apneaThreshold();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 589 | <code>        row.resp_rate_bpm = NaN;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 590 | <code>        row.resp_quality = &quot;skipped&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 591 | <code>        row.breath_amp = NaN;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 592 | <code>        row.spo2_apnea_baseline = NaN;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 593 | <code>        row.spo2_apnea_recent_min = NaN;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 594 | <code>        row.spo2_apnea_drop = NaN;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 595 | <code>        row.spo2_supports_apnea = 0;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 596 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 597 | <code>        const bool still = (state == &quot;LYING_STILL&quot; &amp;&amp; row.motion_intensity &lt;= thresholds.still_motion_for_rr);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 598 | <code>        if (still) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 599 | <code>            // Detect apnea using a short recent-amplitude window before estimating RR.</code> | Chú thích trong code: Detect apnea using a short recent-amplitude window before estimating RR. |
| 600 | <code>            // A 30 s RR window can still contain normal pre-apnea breaths and may</code> | Chú thích trong code: A 30 s RR window can still contain normal pre-apnea breaths and may |
| 601 | <code>            // produce a mathematically valid rate while the current breathing signal</code> | Chú thích trong code: produce a mathematically valid rate while the current breathing signal |
| 602 | <code>            // is already flat. Suppressing RR during possible/active apnea keeps the</code> | Chú thích trong code: is already flat. Suppressing RR during possible/active apnea keeps the |
| 603 | <code>            // clinical timeline consistent.</code> | Chú thích trong code: clinical timeline consistent. |
| 604 | <code>            const double recent_amp = recentChestAmplitude(samples, ts - 5.0, i);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 605 | <code>            apnea_thr = rr_estimator.apneaThreshold();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 606 | <code>            row.breath_amp = recent_amp;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 607 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 608 | <code>            bool apnea_suspected_now = false;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 609 | <code>            if (recent_amp &lt;= apnea_thr) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 610 | <code>                apnea_suspected_now = true;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 611 | <code>                if (!apnea_active_since.has_value()) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 612 | <code>                    apnea_active_since = ts;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 613 | <code>                    apnea_reported = false;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 614 | <code>                } else if (!apnea_reported &amp;&amp; ts - *apnea_active_since &gt;= thresholds.apnea_seconds) {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 615 | <code>                    const auto spo2_evidence = computeSpO2Evidence(samples, *apnea_active_since, ts, i, thresholds);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 616 | <code>                    row.spo2_apnea_baseline = spo2_evidence.baseline;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 617 | <code>                    row.spo2_apnea_recent_min = spo2_evidence.recent_min;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 618 | <code>                    row.spo2_apnea_drop = spo2_evidence.drop_from_baseline;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 619 | <code>                    row.spo2_supports_apnea = spo2_evidence.supports_apnea ? 1 : 0;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 620 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 621 | <code>                    std::ostringstream msg;</code> | Tạo stream chuỗi để ghép message/log có định dạng. |
| 622 | <code>                    msg &lt;&lt; &quot;breathing amplitude low for &gt;&quot; &lt;&lt; std::fixed &lt;&lt; std::setprecision(0)</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 623 | <code>                        &lt;&lt; thresholds.apnea_seconds &lt;&lt; &quot;s while occupied/still; since=&quot;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 624 | <code>                        &lt;&lt; std::setprecision(2) &lt;&lt; *apnea_active_since &lt;&lt; &quot;s, threshold=&quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 625 | <code>                        &lt;&lt; std::setprecision(5) &lt;&lt; apnea_thr</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 626 | <code>                        &lt;&lt; &quot;; spo2_support=&quot; &lt;&lt; (spo2_evidence.supports_apnea ? &quot;yes&quot; : &quot;no&quot;);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 627 | <code>                    if (isFinite(spo2_evidence.baseline) &amp;&amp; isFinite(spo2_evidence.recent_min)) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 628 | <code>                        msg &lt;&lt; &quot;, spo2_baseline=&quot; &lt;&lt; std::setprecision(1) &lt;&lt; spo2_evidence.baseline</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 629 | <code>                            &lt;&lt; &quot;%, spo2_recent_min=&quot; &lt;&lt; spo2_evidence.recent_min</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 630 | <code>                            &lt;&lt; &quot;%, drop=&quot; &lt;&lt; spo2_evidence.drop_from_baseline &lt;&lt; &quot;%&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 631 | <code>                    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 632 | <code>                    // Use detection time, not apnea start time, so events.log is naturally chronological.</code> | Chú thích trong code: Use detection time, not apnea start time, so events.log is naturally chronological. |
| 633 | <code>                    events.push_back({ts, &quot;APNEA_ALERT&quot;, msg.str()});</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 634 | <code>                    apnea_reported = true;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 635 | <code>                }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 636 | <code>            } else {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 637 | <code>                if (apnea_active_since.has_value() &amp;&amp; apnea_reported) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 638 | <code>                    events.push_back({ts, &quot;APNEA_END&quot;, &quot;breathing amplitude recovered&quot;});</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 639 | <code>                    rr_suppressed_until = ts + thresholds.rr_update_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 640 | <code>                }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 641 | <code>                apnea_active_since.reset();</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 642 | <code>                apnea_reported = false;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 643 | <code>            }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 644 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 645 | <code>            if (apnea_suspected_now) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 646 | <code>                row.resp_quality = apnea_reported ? &quot;apnea_active&quot; : &quot;possible_apnea&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 647 | <code>            } else if (ts &lt; rr_suppressed_until) {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 648 | <code>                row.resp_quality = &quot;post_apnea_recovery&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 649 | <code>                row.breath_amp = recent_amp;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 650 | <code>            } else {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 651 | <code>                const double start_ts = ts - thresholds.rr_window_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 652 | <code>                const std::size_t start_idx = lowerBoundTimestamp(samples, start_ts, i + 1);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 653 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 654 | <code>                std::size_t low_motion_count = 0;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 655 | <code>                const std::size_t window_count = i &gt;= start_idx ? (i - start_idx + 1) : 0;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 656 | <code>                for (std::size_t k = start_idx; k &lt;= i; ++k) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 657 | <code>                    if (samples[k].motion_intensity &lt;= thresholds.still_motion_for_rr) ++low_motion_count;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 658 | <code>                }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 659 | <code>                const double low_motion_ratio = window_count &gt; 0</code> | Khai báo biến hằng cục bộ, giúp tránh sửa nhầm giá trị trong logic xử lý. |
| 660 | <code>                    ? static_cast&lt;double&gt;(low_motion_count) / static_cast&lt;double&gt;(window_count)</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 661 | <code>                    : 0.0;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 662 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 663 | <code>                if (low_motion_ratio &gt;= 0.70) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 664 | <code>                    const auto est = rr_estimator.estimate(samples, start_idx, i, ts);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 665 | <code>                    row.resp_rate_bpm = est.rr_bpm;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 666 | <code>                    row.resp_quality = est.quality;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 667 | <code>                    row.breath_amp = est.amplitude;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 668 | <code>                    if (isFinite(est.rr_bpm) &amp;&amp; est.quality == &quot;ok&quot;) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 669 | <code>                        std::ostringstream msg;</code> | Tạo stream chuỗi để ghép message/log có định dạng. |
| 670 | <code>                        msg &lt;&lt; &quot;RR=&quot; &lt;&lt; std::fixed &lt;&lt; std::setprecision(1) &lt;&lt; est.rr_bpm</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 671 | <code>                            &lt;&lt; &quot; bpm, amp=&quot; &lt;&lt; std::setprecision(5) &lt;&lt; est.amplitude;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 672 | <code>                        events.push_back({ts, &quot;RESP_RATE&quot;, msg.str()});</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 673 | <code>                    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 674 | <code>                } else {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 675 | <code>                    row.resp_quality = &quot;motion_in_window&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 676 | <code>                    row.breath_amp = recent_amp;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 677 | <code>                }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 678 | <code>            }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 679 | <code>        } else {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 680 | <code>            if (apnea_active_since.has_value() &amp;&amp; apnea_reported) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 681 | <code>                events.push_back({ts, &quot;APNEA_END&quot;, &quot;monitoring stopped due to state change&quot;});</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 682 | <code>            }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 683 | <code>            apnea_active_since.reset();</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 684 | <code>            apnea_reported = false;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 685 | <code>            apnea_thr = rr_estimator.apneaThreshold();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 686 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 687 | <code>        row.apnea_amp_threshold = apnea_thr;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 688 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 689 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 690 | <code>    if (hr_dropout_active &amp;&amp; !samples.empty()) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 691 | <code>        const double duration = samples.back().timestamp_s - hr_dropout_start;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 692 | <code>        if (duration &gt;= 2.0) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 693 | <code>            std::ostringstream msg;</code> | Tạo stream chuỗi để ghép message/log có định dạng. |
| 694 | <code>            msg &lt;&lt; &quot;hr_bpm=0/invalid until end for &quot; &lt;&lt; std::fixed &lt;&lt; std::setprecision(1) &lt;&lt; duration &lt;&lt; &quot;s&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 695 | <code>            events.push_back({hr_dropout_start, &quot;HR_DROPOUT&quot;, msg.str()});</code> | Thêm một phần tử mới vào vector/deque, ví dụ thêm sample, event, peak hoặc giá trị tín hiệu. |
| 696 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 697 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 698 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 699 | <code>    std::stable_sort(events.begin(), events.end(), [](const Event&amp; a, const Event&amp; b) {</code> | Sắp xếp event theo timestamp nhưng giữ nguyên thứ tự tương đối nếu cùng thời điểm. |
| 700 | <code>        return a.timestamp_s &lt; b.timestamp_s;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 701 | <code>    });</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 702 | <code>    return events;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 703 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 704 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 705 | <code>static std::string csvValue(double x, int precision = 5) {</code> | Khai báo/bắt đầu hàm `csvValue`. Hàm định dạng số khi ghi CSV; NaN thành ô trống. |
| 706 | <code>    if (!isFinite(x)) return &quot;&quot;;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 707 | <code>    std::ostringstream oss;</code> | Tạo stream chuỗi để ghép message/log có định dạng. |
| 708 | <code>    oss &lt;&lt; std::fixed &lt;&lt; std::setprecision(precision) &lt;&lt; x;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 709 | <code>    return oss.str();</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 710 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 711 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 712 | <code>static void ensureDir(const std::string&amp; dir) {</code> | Khai báo/bắt đầu hàm `ensureDir`. Hàm tạo thư mục output nếu chưa có. |
| 713 | <code>#ifdef _WIN32</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 714 | <code>    const std::string cmd = &quot;if not exist \&quot;&quot; + dir + &quot;\&quot; mkdir \&quot;&quot; + dir + &quot;\&quot;&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 715 | <code>#else</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 716 | <code>    const std::string cmd = &quot;mkdir -p \&quot;&quot; + dir + &quot;\&quot;&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 717 | <code>#endif</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 718 | <code>    if (std::system(cmd.c_str()) != 0) throw std::runtime_error(&quot;Cannot create output directory: &quot; + dir);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 719 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 720 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 721 | <code>static void writeProcessedTimeline(const std::vector&lt;SensorSample&gt;&amp; samples, const std::string&amp; outdir) {</code> | Khai báo/bắt đầu hàm `writeProcessedTimeline`. Ghi file processed_timeline.csv với dữ liệu đã xử lý. |
| 722 | <code>    std::ofstream out(outdir + &quot;/processed_timeline.csv&quot;);</code> | Mở file output để ghi kết quả. |
| 723 | <code>    if (!out) throw std::runtime_error(&quot;Cannot write processed_timeline.csv&quot;);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 724 | <code>    out &lt;&lt; &quot;timestamp_s,loadcell_kg,presence,motion_intensity,chest_disp,hr_bpm,spo2,&quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 725 | <code>        &lt;&lt; &quot;hr_valid,hr_filled,spo2_valid,spo2_filled,state,resp_rate_bpm,resp_quality,breath_amp,apnea_amp_threshold,&quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 726 | <code>        &lt;&lt; &quot;spo2_apnea_baseline,spo2_apnea_recent_min,spo2_apnea_drop,spo2_supports_apnea\n&quot;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 727 | <code>    for (const auto&amp; s : samples) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 728 | <code>        out &lt;&lt; csvValue(s.timestamp_s, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 729 | <code>            &lt;&lt; csvValue(s.loadcell_kg, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 730 | <code>            &lt;&lt; s.presence &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 731 | <code>            &lt;&lt; csvValue(s.motion_intensity, 5) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 732 | <code>            &lt;&lt; csvValue(s.chest_disp, 5) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 733 | <code>            &lt;&lt; csvValue(s.hr_bpm, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 734 | <code>            &lt;&lt; csvValue(s.spo2, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 735 | <code>            &lt;&lt; csvValue(s.hr_valid, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 736 | <code>            &lt;&lt; csvValue(s.hr_filled, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 737 | <code>            &lt;&lt; csvValue(s.spo2_valid, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 738 | <code>            &lt;&lt; csvValue(s.spo2_filled, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 739 | <code>            &lt;&lt; s.state &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 740 | <code>            &lt;&lt; csvValue(s.resp_rate_bpm, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 741 | <code>            &lt;&lt; s.resp_quality &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 742 | <code>            &lt;&lt; csvValue(s.breath_amp, 5) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 743 | <code>            &lt;&lt; csvValue(s.apnea_amp_threshold, 5) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 744 | <code>            &lt;&lt; csvValue(s.spo2_apnea_baseline, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 745 | <code>            &lt;&lt; csvValue(s.spo2_apnea_recent_min, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 746 | <code>            &lt;&lt; csvValue(s.spo2_apnea_drop, 3) &lt;&lt; &#x27;,&#x27;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 747 | <code>            &lt;&lt; s.spo2_supports_apnea &lt;&lt; &#x27;\n&#x27;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 748 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 749 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 750 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 751 | <code>static void writeEvents(const std::vector&lt;Event&gt;&amp; events, const std::string&amp; outdir) {</code> | Khai báo/bắt đầu hàm `writeEvents`. Ghi events.log. |
| 752 | <code>    std::ofstream out(outdir + &quot;/events.log&quot;);</code> | Mở file output để ghi kết quả. |
| 753 | <code>    if (!out) throw std::runtime_error(&quot;Cannot write events.log&quot;);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 754 | <code>    for (const auto&amp; e : events) out &lt;&lt; e.toLogLine() &lt;&lt; &#x27;\n&#x27;;</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 755 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 756 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 757 | <code>static void writeStateSegments(const std::vector&lt;SensorSample&gt;&amp; samples, const std::string&amp; outdir) {</code> | Khai báo/bắt đầu hàm `writeStateSegments`. Ghi state_segments.csv, gom các đoạn cùng trạng thái. |
| 758 | <code>    std::ofstream out(outdir + &quot;/state_segments.csv&quot;);</code> | Mở file output để ghi kết quả. |
| 759 | <code>    if (!out) throw std::runtime_error(&quot;Cannot write state_segments.csv&quot;);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 760 | <code>    out &lt;&lt; &quot;start_s,end_s,state\n&quot;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 761 | <code>    if (samples.empty()) return;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 762 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 763 | <code>    double start_ts = samples.front().timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 764 | <code>    std::string last_state = samples.front().state;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 765 | <code>    double prev_ts = start_ts;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 766 | <code>    for (std::size_t i = 1; i &lt; samples.size(); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 767 | <code>        if (samples[i].state != last_state) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 768 | <code>            out &lt;&lt; csvValue(start_ts, 3) &lt;&lt; &#x27;,&#x27; &lt;&lt; csvValue(prev_ts, 3) &lt;&lt; &#x27;,&#x27; &lt;&lt; last_state &lt;&lt; &#x27;\n&#x27;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 769 | <code>            start_ts = samples[i].timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 770 | <code>            last_state = samples[i].state;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 771 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 772 | <code>        prev_ts = samples[i].timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 773 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 774 | <code>    out &lt;&lt; csvValue(start_ts, 3) &lt;&lt; &#x27;,&#x27; &lt;&lt; csvValue(prev_ts, 3) &lt;&lt; &#x27;,&#x27; &lt;&lt; last_state &lt;&lt; &#x27;\n&#x27;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 775 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 776 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 777 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 778 | <code>static std::string svgEscape(const std::string&amp; text) {</code> | Khai báo/bắt đầu hàm `svgEscape`. Escape ký tự đặc biệt để ghi SVG an toàn. |
| 779 | <code>    std::string out;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 780 | <code>    for (char c : text) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 781 | <code>        if (c == &#x27;&amp;&#x27;) out += &quot;&amp;amp;&quot;;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 782 | <code>        else if (c == &#x27;&lt;&#x27;) out += &quot;&amp;lt;&quot;;</code> | Nhánh điều kiện phụ `else if`: chỉ kiểm tra khi các nhánh trước không thỏa. |
| 783 | <code>        else if (c == &#x27;&gt;&#x27;) out += &quot;&amp;gt;&quot;;</code> | Nhánh điều kiện phụ `else if`: chỉ kiểm tra khi các nhánh trước không thỏa. |
| 784 | <code>        else out += c;</code> | Nhánh `else`: xử lý trường hợp còn lại khi điều kiện phía trên không đúng. |
| 785 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 786 | <code>    return out;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 787 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 788 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 789 | <code>static double clamp01(double x) {</code> | Khai báo/bắt đầu hàm `clamp01`. Giới hạn số vào khoảng [0,1]. |
| 790 | <code>    return std::max(0.0, std::min(1.0, x));</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 791 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 792 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 793 | <code>static void writeSvgHeader(std::ofstream&amp; out, int w, int h, const std::string&amp; title) {</code> | Khai báo/bắt đầu hàm `writeSvgHeader`. Ghi phần header chung cho SVG plot. |
| 794 | <code>    out &lt;&lt; &quot;&lt;svg xmlns=\&quot;http://www.w3.org/2000/svg\&quot; width=\&quot;&quot; &lt;&lt; w &lt;&lt; &quot;\&quot; height=\&quot;&quot; &lt;&lt; h</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 795 | <code>        &lt;&lt; &quot;\&quot; viewBox=\&quot;0 0 &quot; &lt;&lt; w &lt;&lt; &#x27; &#x27; &lt;&lt; h &lt;&lt; &quot;\&quot;&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 796 | <code>    out &lt;&lt; &quot;&lt;rect width=\&quot;100%\&quot; height=\&quot;100%\&quot; fill=\&quot;white\&quot;/&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 797 | <code>    out &lt;&lt; &quot;&lt;text x=\&quot;&quot; &lt;&lt; (w / 2) &lt;&lt; &quot;\&quot; y=\&quot;24\&quot; text-anchor=\&quot;middle\&quot; &quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 798 | <code>        &lt;&lt; &quot;font-family=\&quot;Arial, sans-serif\&quot; font-size=\&quot;16\&quot;&gt;&quot; &lt;&lt; svgEscape(title) &lt;&lt; &quot;&lt;/text&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 799 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 800 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 801 | <code>static double stateToNumber(const std::string&amp; state) {</code> | Khai báo/bắt đầu hàm `stateToNumber`. Đổi state dạng chuỗi thành số để vẽ timeline. |
| 802 | <code>    if (state == &quot;EMPTY&quot;) return 0.0;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 803 | <code>    if (state == &quot;LYING_STILL&quot;) return 1.0;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 804 | <code>    if (state == &quot;MOVING&quot;) return 2.0;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 805 | <code>    if (state == &quot;LEAVING&quot;) return 3.0;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 806 | <code>    return 0.0;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 807 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 808 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 809 | <code>static void writeStateTimelineSvg(const std::vector&lt;SensorSample&gt;&amp; samples, const std::string&amp; outdir) {</code> | Khai báo/bắt đầu hàm `writeStateTimelineSvg`. Vẽ biểu đồ state timeline dạng SVG. |
| 810 | <code>    if (samples.empty()) return;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 811 | <code>    std::ofstream out(outdir + &quot;/state_timeline.svg&quot;);</code> | Mở file output để ghi kết quả. |
| 812 | <code>    if (!out) throw std::runtime_error(&quot;Cannot write state_timeline.svg&quot;);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 813 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 814 | <code>    const int w = 1000, h = 280;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 815 | <code>    const int left = 100, right = 30, top = 45, bottom = 45;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 816 | <code>    const double t0 = samples.front().timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 817 | <code>    const double t1 = samples.back().timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 818 | <code>    auto xOf = [&amp;](double t) { return left + (w - left - right) * clamp01((t - t0) / std::max(1e-9, t1 - t0)); };</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 819 | <code>    auto yOf = [&amp;](double v) { return top + (h - top - bottom) * (1.0 - v / 3.0); };</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 820 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 821 | <code>    writeSvgHeader(out, w, h, &quot;Smartbed state timeline&quot;);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 822 | <code>    out &lt;&lt; &quot;&lt;line x1=\&quot;&quot; &lt;&lt; left &lt;&lt; &quot;\&quot; y1=\&quot;&quot; &lt;&lt; (h - bottom) &lt;&lt; &quot;\&quot; x2=\&quot;&quot; &lt;&lt; (w - right)</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 823 | <code>        &lt;&lt; &quot;\&quot; y2=\&quot;&quot; &lt;&lt; (h - bottom) &lt;&lt; &quot;\&quot; stroke=\&quot;#333\&quot;/&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 824 | <code>    out &lt;&lt; &quot;&lt;line x1=\&quot;&quot; &lt;&lt; left &lt;&lt; &quot;\&quot; y1=\&quot;&quot; &lt;&lt; top &lt;&lt; &quot;\&quot; x2=\&quot;&quot; &lt;&lt; left</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 825 | <code>        &lt;&lt; &quot;\&quot; y2=\&quot;&quot; &lt;&lt; (h - bottom) &lt;&lt; &quot;\&quot; stroke=\&quot;#333\&quot;/&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 826 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 827 | <code>    const std::vector&lt;std::string&gt; labels = {&quot;EMPTY&quot;, &quot;LYING_STILL&quot;, &quot;MOVING&quot;, &quot;LEAVING&quot;};</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 828 | <code>    for (std::size_t i = 0; i &lt; labels.size(); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 829 | <code>        const double y = yOf(static_cast&lt;double&gt;(i));</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 830 | <code>        out &lt;&lt; &quot;&lt;line x1=\&quot;&quot; &lt;&lt; left &lt;&lt; &quot;\&quot; y1=\&quot;&quot; &lt;&lt; y &lt;&lt; &quot;\&quot; x2=\&quot;&quot; &lt;&lt; (w - right)</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 831 | <code>            &lt;&lt; &quot;\&quot; y2=\&quot;&quot; &lt;&lt; y &lt;&lt; &quot;\&quot; stroke=\&quot;#ddd\&quot;/&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 832 | <code>        out &lt;&lt; &quot;&lt;text x=\&quot;&quot; &lt;&lt; (left - 8) &lt;&lt; &quot;\&quot; y=\&quot;&quot; &lt;&lt; (y + 4) &lt;&lt; &quot;\&quot; text-anchor=\&quot;end\&quot; &quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 833 | <code>            &lt;&lt; &quot;font-family=\&quot;Arial, sans-serif\&quot; font-size=\&quot;11\&quot;&gt;&quot; &lt;&lt; labels[i] &lt;&lt; &quot;&lt;/text&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 834 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 835 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 836 | <code>    out &lt;&lt; &quot;&lt;polyline fill=\&quot;none\&quot; stroke=\&quot;#111\&quot; stroke-width=\&quot;2\&quot; points=\&quot;&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 837 | <code>    double prev_x = xOf(samples.front().timestamp_s);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 838 | <code>    double prev_y = yOf(stateToNumber(samples.front().state));</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 839 | <code>    out &lt;&lt; prev_x &lt;&lt; &#x27;,&#x27; &lt;&lt; prev_y &lt;&lt; &#x27; &#x27;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 840 | <code>    for (std::size_t i = 1; i &lt; samples.size(); ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 841 | <code>        const double x = xOf(samples[i].timestamp_s);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 842 | <code>        const double y = yOf(stateToNumber(samples[i].state));</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 843 | <code>        if (std::abs(y - prev_y) &gt; 1e-9) out &lt;&lt; x &lt;&lt; &#x27;,&#x27; &lt;&lt; prev_y &lt;&lt; &#x27; &#x27;;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 844 | <code>        out &lt;&lt; x &lt;&lt; &#x27;,&#x27; &lt;&lt; y &lt;&lt; &#x27; &#x27;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 845 | <code>        prev_x = x;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 846 | <code>        prev_y = y;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 847 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 848 | <code>    (void)prev_x;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 849 | <code>    out &lt;&lt; &quot;\&quot;/&gt;\n&lt;/svg&gt;\n&quot;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 850 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 851 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 852 | <code>static void writeChestDispSvg(const std::vector&lt;SensorSample&gt;&amp; samples, const std::string&amp; outdir) {</code> | Khai báo/bắt đầu hàm `writeChestDispSvg`. Vẽ biểu đồ chest displacement dạng SVG. |
| 853 | <code>    if (samples.empty()) return;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 854 | <code>    std::ofstream out(outdir + &quot;/chest_disp.svg&quot;);</code> | Mở file output để ghi kết quả. |
| 855 | <code>    if (!out) throw std::runtime_error(&quot;Cannot write chest_disp.svg&quot;);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 856 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 857 | <code>    const int w = 1000, h = 300;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 858 | <code>    const int left = 70, right = 30, top = 45, bottom = 45;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 859 | <code>    const double t0 = samples.front().timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 860 | <code>    const double t1 = samples.back().timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 861 | <code>    double ymin = std::numeric_limits&lt;double&gt;::infinity();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 862 | <code>    double ymax = -std::numeric_limits&lt;double&gt;::infinity();</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 863 | <code>    for (const auto&amp; s : samples) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 864 | <code>        if (isFinite(s.chest_disp)) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 865 | <code>            ymin = std::min(ymin, s.chest_disp);</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 866 | <code>            ymax = std::max(ymax, s.chest_disp);</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 867 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 868 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 869 | <code>    if (!isFinite(ymin) &#124;&#124; !isFinite(ymax) &#124;&#124; std::abs(ymax - ymin) &lt; 1e-9) { ymin = -1.0; ymax = 1.0; }</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 870 | <code>    const double pad = 0.05 * (ymax - ymin);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 871 | <code>    ymin -= pad; ymax += pad;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 872 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 873 | <code>    auto xOf = [&amp;](double t) { return left + (w - left - right) * clamp01((t - t0) / std::max(1e-9, t1 - t0)); };</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 874 | <code>    auto yOf = [&amp;](double v) { return top + (h - top - bottom) * (1.0 - (v - ymin) / std::max(1e-9, ymax - ymin)); };</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 875 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 876 | <code>    writeSvgHeader(out, w, h, &quot;Chest displacement signal&quot;);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 877 | <code>    out &lt;&lt; &quot;&lt;line x1=\&quot;&quot; &lt;&lt; left &lt;&lt; &quot;\&quot; y1=\&quot;&quot; &lt;&lt; (h - bottom) &lt;&lt; &quot;\&quot; x2=\&quot;&quot; &lt;&lt; (w - right)</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 878 | <code>        &lt;&lt; &quot;\&quot; y2=\&quot;&quot; &lt;&lt; (h - bottom) &lt;&lt; &quot;\&quot; stroke=\&quot;#333\&quot;/&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 879 | <code>    out &lt;&lt; &quot;&lt;line x1=\&quot;&quot; &lt;&lt; left &lt;&lt; &quot;\&quot; y1=\&quot;&quot; &lt;&lt; top &lt;&lt; &quot;\&quot; x2=\&quot;&quot; &lt;&lt; left</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 880 | <code>        &lt;&lt; &quot;\&quot; y2=\&quot;&quot; &lt;&lt; (h - bottom) &lt;&lt; &quot;\&quot; stroke=\&quot;#333\&quot;/&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 881 | <code>    out &lt;&lt; &quot;&lt;polyline fill=\&quot;none\&quot; stroke=\&quot;#111\&quot; stroke-width=\&quot;1.2\&quot; points=\&quot;&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 882 | <code>    for (const auto&amp; s : samples) if (isFinite(s.chest_disp)) out &lt;&lt; xOf(s.timestamp_s) &lt;&lt; &#x27;,&#x27; &lt;&lt; yOf(s.chest_disp) &lt;&lt; &#x27; &#x27;;</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 883 | <code>    out &lt;&lt; &quot;\&quot;/&gt;\n&quot;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 884 | <code>    out &lt;&lt; &quot;&lt;text x=\&quot;&quot; &lt;&lt; left &lt;&lt; &quot;\&quot; y=\&quot;&quot; &lt;&lt; (h - 12) &lt;&lt; &quot;\&quot; font-family=\&quot;Arial, sans-serif\&quot; font-size=\&quot;11\&quot;&gt;time (s)&lt;/text&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 885 | <code>    out &lt;&lt; &quot;&lt;/svg&gt;\n&quot;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 886 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 887 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 888 | <code>static void writeRespRateSvg(const std::vector&lt;SensorSample&gt;&amp; samples, const std::string&amp; outdir) {</code> | Khai báo/bắt đầu hàm `writeRespRateSvg`. Vẽ biểu đồ respiratory rate dạng SVG. |
| 889 | <code>    if (samples.empty()) return;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 890 | <code>    std::ofstream out(outdir + &quot;/resp_rate.svg&quot;);</code> | Mở file output để ghi kết quả. |
| 891 | <code>    if (!out) throw std::runtime_error(&quot;Cannot write resp_rate.svg&quot;);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 892 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 893 | <code>    const int w = 1000, h = 300;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 894 | <code>    const int left = 70, right = 30, top = 45, bottom = 45;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 895 | <code>    const double t0 = samples.front().timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 896 | <code>    const double t1 = samples.back().timestamp_s;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 897 | <code>    double ymin = 6.0, ymax = 24.0;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 898 | <code>    auto xOf = [&amp;](double t) { return left + (w - left - right) * clamp01((t - t0) / std::max(1e-9, t1 - t0)); };</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 899 | <code>    auto yOf = [&amp;](double v) { return top + (h - top - bottom) * (1.0 - (v - ymin) / std::max(1e-9, ymax - ymin)); };</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 900 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 901 | <code>    writeSvgHeader(out, w, h, &quot;Respiratory-rate estimates while lying still&quot;);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 902 | <code>    out &lt;&lt; &quot;&lt;line x1=\&quot;&quot; &lt;&lt; left &lt;&lt; &quot;\&quot; y1=\&quot;&quot; &lt;&lt; (h - bottom) &lt;&lt; &quot;\&quot; x2=\&quot;&quot; &lt;&lt; (w - right)</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 903 | <code>        &lt;&lt; &quot;\&quot; y2=\&quot;&quot; &lt;&lt; (h - bottom) &lt;&lt; &quot;\&quot; stroke=\&quot;#333\&quot;/&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 904 | <code>    out &lt;&lt; &quot;&lt;line x1=\&quot;&quot; &lt;&lt; left &lt;&lt; &quot;\&quot; y1=\&quot;&quot; &lt;&lt; top &lt;&lt; &quot;\&quot; x2=\&quot;&quot; &lt;&lt; left</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 905 | <code>        &lt;&lt; &quot;\&quot; y2=\&quot;&quot; &lt;&lt; (h - bottom) &lt;&lt; &quot;\&quot; stroke=\&quot;#333\&quot;/&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 906 | <code>    for (const auto&amp; s : samples) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 907 | <code>        if (isFinite(s.resp_rate_bpm)) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 908 | <code>            out &lt;&lt; &quot;&lt;circle cx=\&quot;&quot; &lt;&lt; xOf(s.timestamp_s) &lt;&lt; &quot;\&quot; cy=\&quot;&quot; &lt;&lt; yOf(s.resp_rate_bpm)</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 909 | <code>                &lt;&lt; &quot;\&quot; r=\&quot;2\&quot; fill=\&quot;#111\&quot;/&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 910 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 911 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 912 | <code>    out &lt;&lt; &quot;&lt;text x=\&quot;&quot; &lt;&lt; left &lt;&lt; &quot;\&quot; y=\&quot;&quot; &lt;&lt; (h - 12) &lt;&lt; &quot;\&quot; font-family=\&quot;Arial, sans-serif\&quot; font-size=\&quot;11\&quot;&gt;time (s)&lt;/text&gt;\n&quot;;</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 913 | <code>    out &lt;&lt; &quot;&lt;/svg&gt;\n&quot;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 914 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 915 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 916 | <code>static void writeSvgPlots(const std::vector&lt;SensorSample&gt;&amp; samples, const std::string&amp; outdir) {</code> | Khai báo/bắt đầu hàm `writeSvgPlots`. Gọi 3 hàm vẽ SVG. |
| 917 | <code>    writeStateTimelineSvg(samples, outdir);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 918 | <code>    writeChestDispSvg(samples, outdir);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 919 | <code>    writeRespRateSvg(samples, outdir);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 920 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 921 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 922 | <code>struct Args {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 923 | <code>    std::string csv_path;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 924 | <code>    std::string outdir = &quot;output&quot;;</code> | Khai báo biến/trường dữ liệu dùng để lưu trạng thái, giá trị cảm biến hoặc kết quả xử lý. |
| 925 | <code>    Thresholds thresholds;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 926 | <code>};</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 927 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 928 | <code>static void printUsage(const char* prog) {</code> | Khai báo/bắt đầu hàm `printUsage`. In hướng dẫn cách chạy chương trình. |
| 929 | <code>    std::cerr &lt;&lt; &quot;Usage: &quot; &lt;&lt; prog &lt;&lt; &quot; &lt;smartbed-sensor-stream.csv&gt; [options]\n\n&quot;</code> | In lỗi/hướng dẫn ra terminal error stream. |
| 930 | <code>              &lt;&lt; &quot;Options:\n&quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 931 | <code>              &lt;&lt; &quot;  --outdir &lt;dir&gt;          Output directory, default: output\n&quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 932 | <code>              &lt;&lt; &quot;  --rr-window-s &lt;sec&gt;     Respiratory-rate window, default: 30\n&quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 933 | <code>              &lt;&lt; &quot;  --apnea-seconds &lt;sec&gt;   Low-breathing duration before alert, default: 10\n&quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 934 | <code>              &lt;&lt; &quot;  --load-enter-kg &lt;kg&gt;    Occupied hysteresis enter threshold, default: 18\n&quot;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 935 | <code>              &lt;&lt; &quot;  --load-exit-kg &lt;kg&gt;     Empty hysteresis exit threshold, default: 8\n&quot;;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 936 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 937 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 938 | <code>static Args parseArgs(int argc, char** argv) {</code> | Khai báo/bắt đầu hàm `parseArgs`. Đọc tham số dòng lệnh. |
| 939 | <code>    if (argc &lt; 2) {</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 940 | <code>        printUsage(argv[0]);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 941 | <code>        throw std::runtime_error(&quot;Missing CSV path&quot;);</code> | Báo lỗi bằng exception khi file/input/output không hợp lệ. |
| 942 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 943 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 944 | <code>    Args args;</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 945 | <code>    args.csv_path = argv[1];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 946 | <code>    for (int i = 2; i &lt; argc; ++i) {</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 947 | <code>        const std::string key = argv[i];</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 948 | <code>        auto needValue = [&amp;](const std::string&amp; option) -&gt; std::string {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 949 | <code>            if (i + 1 &gt;= argc) throw std::runtime_error(&quot;Missing value for &quot; + option);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 950 | <code>            return argv[++i];</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 951 | <code>        };</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 952 | <code>        if (key == &quot;--outdir&quot;) args.outdir = needValue(key);</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 953 | <code>        else if (key == &quot;--rr-window-s&quot;) args.thresholds.rr_window_s = std::stod(needValue(key));</code> | Nhánh điều kiện phụ `else if`: chỉ kiểm tra khi các nhánh trước không thỏa. |
| 954 | <code>        else if (key == &quot;--apnea-seconds&quot;) args.thresholds.apnea_seconds = std::stod(needValue(key));</code> | Nhánh điều kiện phụ `else if`: chỉ kiểm tra khi các nhánh trước không thỏa. |
| 955 | <code>        else if (key == &quot;--load-enter-kg&quot;) args.thresholds.load_enter_kg = std::stod(needValue(key));</code> | Nhánh điều kiện phụ `else if`: chỉ kiểm tra khi các nhánh trước không thỏa. |
| 956 | <code>        else if (key == &quot;--load-exit-kg&quot;) args.thresholds.load_exit_kg = std::stod(needValue(key));</code> | Nhánh điều kiện phụ `else if`: chỉ kiểm tra khi các nhánh trước không thỏa. |
| 957 | <code>        else if (key == &quot;--help&quot; &#124;&#124; key == &quot;-h&quot;) {</code> | Nhánh điều kiện phụ `else if`: chỉ kiểm tra khi các nhánh trước không thỏa. |
| 958 | <code>            printUsage(argv[0]);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 959 | <code>            std::exit(0);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 960 | <code>        } else {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 961 | <code>            throw std::runtime_error(&quot;Unknown option: &quot; + key);</code> | Báo lỗi bằng exception khi file/input/output không hợp lệ. |
| 962 | <code>        }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 963 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 964 | <code>    return args;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 965 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 966 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 967 | <code>}  // namespace smartbed</code> | Đóng namespace `smartbed`. |
| 968 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 969 | <code>int main(int argc, char** argv) {</code> | Khai báo/bắt đầu hàm `main`. Điểm bắt đầu chương trình: parse args, đọc CSV, xử lý, ghi output. |
| 970 | <code>    try {</code> | Bắt đầu khối `try`: các lỗi runtime bên trong sẽ được bắt ở `catch`. |
| 971 | <code>        auto args = smartbed::parseArgs(argc, argv);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 972 | <code>        auto samples = smartbed::readCsv(args.csv_path);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 973 | <code>        auto events = smartbed::processStream(samples, args.thresholds);</code> | Gán giá trị hoặc cập nhật biến/trường dữ liệu trong quá trình xử lý. |
| 974 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 975 | <code>        smartbed::ensureDir(args.outdir);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 976 | <code>        smartbed::writeProcessedTimeline(samples, args.outdir);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 977 | <code>        smartbed::writeStateSegments(samples, args.outdir);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 978 | <code>        smartbed::writeEvents(events, args.outdir);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 979 | <code>        smartbed::writeSvgPlots(samples, args.outdir);</code> | Dòng code thực thi một bước xử lý trong chương trình; xem ngữ cảnh hàm/phần bên trên để hiểu vai trò cụ thể. |
| 980 | <code>&nbsp;</code> | Dòng trống để tách khối code, giúp file dễ đọc hơn. |
| 981 | <code>        std::cout &lt;&lt; &quot;Processed &quot; &lt;&lt; samples.size() &lt;&lt; &quot; samples\n&quot;;</code> | In thông tin kết quả ra terminal cho người dùng biết chương trình đã ghi file nào. |
| 982 | <code>        std::cout &lt;&lt; &quot;Wrote: &quot; &lt;&lt; args.outdir &lt;&lt; &quot;/processed_timeline.csv\n&quot;;</code> | In thông tin kết quả ra terminal cho người dùng biết chương trình đã ghi file nào. |
| 983 | <code>        std::cout &lt;&lt; &quot;Wrote: &quot; &lt;&lt; args.outdir &lt;&lt; &quot;/state_segments.csv\n&quot;;</code> | In thông tin kết quả ra terminal cho người dùng biết chương trình đã ghi file nào. |
| 984 | <code>        std::cout &lt;&lt; &quot;Wrote: &quot; &lt;&lt; args.outdir &lt;&lt; &quot;/events.log\n&quot;;</code> | In thông tin kết quả ra terminal cho người dùng biết chương trình đã ghi file nào. |
| 985 | <code>        std::cout &lt;&lt; &quot;Wrote: &quot; &lt;&lt; args.outdir &lt;&lt; &quot;/state_timeline.svg, chest_disp.svg, resp_rate.svg\n\n&quot;;</code> | In thông tin kết quả ra terminal cho người dùng biết chương trình đã ghi file nào. |
| 986 | <code>        std::cout &lt;&lt; &quot;Key events:\n&quot;;</code> | In thông tin kết quả ra terminal cho người dùng biết chương trình đã ghi file nào. |
| 987 | <code>        const std::size_t n = std::min&lt;std::size_t&gt;(30, events.size());</code> | Dùng min/max để giới hạn hoặc chọn giá trị biên phù hợp. |
| 988 | <code>        for (std::size_t i = 0; i &lt; n; ++i) std::cout &lt;&lt; events[i].toLogLine() &lt;&lt; &#x27;\n&#x27;;</code> | Vòng lặp `for`: duyệt qua nhiều phần tử, ví dụ samples, cột CSV, peak hoặc event. |
| 989 | <code>        if (events.size() &gt; n) std::cout &lt;&lt; &quot;... &quot; &lt;&lt; (events.size() - n) &lt;&lt; &quot; more events in events.log\n&quot;;</code> | Câu điều kiện `if`: kiểm tra điều kiện để chọn nhánh xử lý phù hợp. |
| 990 | <code>        return 0;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 991 | <code>    } catch (const std::exception&amp; ex) {</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 992 | <code>        std::cerr &lt;&lt; &quot;Error: &quot; &lt;&lt; ex.what() &lt;&lt; &#x27;\n&#x27;;</code> | In lỗi/hướng dẫn ra terminal error stream. |
| 993 | <code>        return 1;</code> | Trả kết quả về cho hàm gọi; đây là đầu ra của nhánh xử lý hiện tại. |
| 994 | <code>    }</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |
| 995 | <code>}</code> | Mở/đóng một khối lệnh hoặc định nghĩa struct/class/function. |

## 4. Cách trình bày khi được hỏi về code

Bạn có thể nói ngắn gọn: “Em chia chương trình thành các module nhỏ: đọc CSV, làm sạch dữ liệu, phân loại trạng thái, ước lượng nhịp thở, phát hiện apnea và ghi output. Em dùng C++17 dependency-free để gần với môi trường edge/embedded. Với dữ liệu lỗi HR=0, em không báo alarm mà xử lý như dropout. Với apnea, em không chỉ dựa vào RR 30 giây vì cửa sổ dài có thể còn chứa nhịp thở cũ; em dùng thêm biên độ thở 5 giây gần nhất và SpO2 làm tín hiệu phụ xác nhận.”
