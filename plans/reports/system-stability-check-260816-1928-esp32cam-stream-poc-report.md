# Kiểm tra độ ổn định hệ thống — 16/08/2026

Phạm vi: node `firmware/esp32cam-stream/` + `scripts/pose-poc/` + CI.

Kết luận: **hạ tầng đã thông từ đầu tới cuối** — node stream OK, PoC pose chạy được, 0 frame hỏng. **Chưa nghiệm thu chất lượng pose**: camera còn để trên bàn, chưa có người nằm trong khung. Hoãn sang phiên sau theo quyết định chủ dự án.

Ba việc đã sửa trong phiên: SSID sai trong `config.h`, firmware dựng từ cây bẩn, thiếu mediapipe phía Windows.

## Đã khắc phục trong phiên này

Ban đầu node chết vì `config.h` trỏ vào AP `mp` không tồn tại. Đã đổi sang `Tiệm Coffee của cá` (UTF-8, 21 byte) và nạp lại từ HEAD sạch.

Kết quả sau khi nạp (`App version: e27c088`, hash verified):

| Kiểm tra | Kết quả |
|---|---|
| WiFi `init -> auth -> assoc -> run` | OK, ~2s |
| IP | `192.168.0.120` |
| HTTP cổng 80 (từ Windows) | 200, 358 byte |
| Stream cổng 81, headers | 200 `multipart/x-mixed-replace` |
| Stream 15s liên tục | 205 frame, 3.0 MB |
| fps đo được (stream thuần, không suy luận) | **13.7** |
| Toàn vẹn JPEG | **204/205 SOI+EOI hợp lệ, 0 frame thiếu SOI** |
| Kích thước frame | min 14.4K / p50 14.7K / max 15.2K |

Hai kết luận rút ra:

- **`NO-SOI` lúc boot là vô hại.** 0/205 frame thiếu start marker trong stream thật → cảnh báo chỉ là frame rác lúc sensor khởi động, không đi vào pipeline. Nghi vấn đóng.
- **13.7 fps thấp hơn baseline 20.3 fps** (stream thuần, 14/08). Không phải hồi quy firmware — baseline đo trên mạng bench cách ly, lần này đo trên WiFi quán cà phê dùng chung. Ghi nhận là số đo môi trường, **không dùng làm baseline mới**.

Subnet là `192.168.0.x`, không phải `192.168.1.x` như tài liệu cũ giả định.

## Nguyên nhân gốc ban đầu (đã sửa)

Boot log đọc trực tiếp từ `/dev/ttyUSB0` @115200 (usbipd attach busid 2-2):

```
I (1733) esp32cam-stream: Camera OK — VGA 640x480, JPEG quality 12, 2 frame buffer trong PSRAM
W (4353) esp32cam-stream: WiFi rớt, thử lại lần 1/10
...
W (26313) esp32cam-stream: WiFi rớt, thử lại lần 10/10
E (28753) esp32cam-stream: Không nối được WiFi sau 10 lần thử — kiểm tra WIFI_SSID/WIFI_PASS...
E (28763) esp32cam-stream: Dừng ở đây — không có mạng thì không ai xem được stream.
I (28773) main_task: Returned from app_main()
```

Nguyên nhân gốc: `include/config.h` đặt `WIFI_SSID "mp"`, nhưng `netsh wlan show networks` từ Windows chỉ thấy **một** AP — `Tiệm Coffee của...` (802.11n, kênh 6). AP `mp` không phát sóng tại vị trí hiện tại.

Không phải lỗi firmware, không phải sai credentials, không phải 5GHz. Chỉ là mạng không có mặt.

Hệ quả: không có IP → quét `192.168.1.0/24` không ra gì → không chạy được `pose_poc.py`. fps / dropout / recovery của PoC **chưa kiểm chứng lại được vòng này**; số liệu duy nhất vẫn là baseline 14/08 trong `docs/sensor-characterization.md`.

Cách gỡ: bật AP `mp` (2.4GHz), hoặc sửa `config.h` sang SSID hiện có rồi nạp lại.

## Đã xác minh OK

| Hạng mục | Kết quả |
|---|---|
| Boot ESP32 (POWERON_RESET → app_main) | OK |
| Camera OV2640 init, PID=0x26, VGA 640x480 JPEG q12, 2 buffer PSRAM | OK |
| PSRAM 4096K vào heap | OK |
| ESP-IDF 5.5.5, chip rev v3.1 | OK |
| `scripts/check-doc-links.sh` | pass |
| `ruff check scripts/` | pass |
| Syntax `pose_poc.py` | pass |
| Gitignore secrets (`config.h`, `sdkconfig.*`) — chỉ `config.h.example` được track | đúng |

## Vấn đề tìm được (chưa sửa, chờ quyết định)

### 1. Mất WiFi 10 lần → firmware dừng vĩnh viễn

`main.c:30` `WIFI_MAX_RETRY 10`, hết retry thì `app_main()` return, board nằm im tới khi ngắt điện thủ công.

Với thiết bị theo dõi giấc ngủ chạy qua đêm, đây là chế độ hỏng thật: router reboot lúc 3h sáng → node chết tới sáng, mất trọn phiên ghi. 10 lần retry ≈ 25 giây, ngắn hơn thời gian boot của phần lớn router.

Cân nhắc: retry vô hạn với backoff, hoặc `esp_restart()` thay vì return. Chưa sửa — đây là quyết định thiết kế thuộc về bạn.

### 2. ~~Firmware dựng từ cây bẩn~~ — ĐÃ SỬA

Bản cũ là `dd083d1-dirty`, không tái tạo được từ commit nào. Đã nạp lại, giờ là `e27c088` sạch.

### 3. ~~Cảnh báo `NO-SOI` lúc boot~~ — ĐÃ ĐÓNG, vô hại

Đo 205 frame stream thật: 0 frame thiếu SOI. Chỉ là frame rác lúc sensor khởi động.

### 4. CI không gác code Python thật

`.github/workflows/lint.yml` chỉ ruff `edge cloud`. Cả hai thư mục **hiện rỗng** → job luôn skip → CI xanh mà không kiểm gì.

`scripts/pose-poc/` — code Python thật duy nhất trong repo — không được lint. Và nó đang fail `ruff format --check` (3 chỗ trong `pose_poc.py`: list comprehension dòng 49, dòng trống 63, f-string dòng 231).

Format là thuần thẩm mỹ, không ảnh hưởng runtime. Lỗ hổng CI mới là cái đáng sửa: một lỗi `F` (biến chưa định nghĩa, import sai) sẽ lọt tới lúc chạy trên phần cứng giữa đêm thay vì bị chặn ở PR.

### 5. `pip install -r requirements.txt` fail trên Windows

`scripts/pose-poc/requirements.txt` có comment tiếng Việt (UTF-8), nhưng pip trên Windows decode file requirements bằng codepage hệ thống (cp1252):

```
UnicodeDecodeError: 'charmap' codec can't decode byte 0x8f in position 391
```

Chết ngay khâu đọc file, chưa tải gói nào. Đây **đúng là câu lệnh `README.md` bảo chạy**, nên mọi máy Windows locale Việt/Tây Âu đều vấp. `PYTHONUTF8=1` không cứu được — pip đọc file này trước khi tôn trọng biến đó.

Cách vòng đã dùng: `pip install --user "mediapipe>=1.0.0"` (file chỉ có đúng một requirement thực). Cài xong đúng bộ version mà file ghi là đã verify: mediapipe 1.0.1, opencv-contrib-python 5.0.0.93, numpy 2.4.6. Import OK, `POSE_LANDMARKS` 35 cặp, `imshow` dùng được.

Cách sửa gọn: thêm **BOM UTF-8** vào đầu `requirements.txt` — pip kiểm tra BOM trước rồi mới rơi về locale encoding, giữ nguyên được comment tiếng Việt. Chưa sửa.

Ghi chú: mediapipe **không** được cài trong WSL (đã kiểm `python3` hệ thống, `~/.local`, và mọi venv: `~/.venvs/tts`, `~/.venvs/kws`, `~/venvs/eric-banner`, penv của PlatformIO). Dù có cài cũng không dùng được vì WSL2 NAT không chạm được node.

### 6. Không có test tự động

Repo chưa có test nào. "Ổn định" hiện chỉ đánh giá được bằng chạy thật trên phần cứng.

## Ghi chú môi trường

- WSL2 ở NAT mode (`172.29.132.234`), **không route sang LAN**. Mọi test mạng tới node phải chạy từ Windows host, hoặc bật mirrored networking.
- Serial thì đọc được từ WSL qua usbipd. Hai điểm vướng đã gặp:
  - Mở cổng bằng `cat`/`stty` làm CH340 kéo DTR/RTS (nối EN/IO0) → board reset hoặc vào download mode. Phải dùng pyserial đặt `dtr=False, rts=False` **trước** `open()`.
  - Board reset làm USB re-enumerate → usbipd **tự hủy attach**. Phải attach lại sau mỗi lần reset.

## Hướng khung hình: phát hiện quan trọng nhất phiên 17/08

Camera đặt đứng, người nằm ngang ⇒ trục cơ thể lệch 90° so với thứ MediaPipe mong đợi (model huấn luyện trên người thẳng đứng). Đo thực nghiệm, cùng người cùng tư thế, mỗi lượt ~28s:

| Xoay ảnh trước suy luận | Phát hiện |
|---|---|
| 0° | 83% |
| **90°** | **99.7%** |
| 270° | **0%** |

270° lệch đúng 180° so với 90°: **người lộn đầu thì MediaPipe mất trắng, không phải giảm dần.** Đây là ràng buộc lắp đặt cứng, phải ghi vào tài liệu phần cứng.

Đã thêm cờ `--rotate {0,90,180,270}` (xoay bằng phần mềm ngay sau khi đọc frame). Không bắt người nằm theo camera — người dùng thật nằm theo giường của họ.

Ảnh hưởng tới bài đo có nhãn, cùng người cùng kịch bản:

| Pha | Phát hiện 0° | Phát hiện 90° |
|---|---|---|
| nằm ngửa | 56% | **95%** |
| nghiêng trái | 90% | 59% |
| nghiêng phải | 11% | 25% |
| ngửa + chăn | 66% | 66% |

Gộp cả ba cấu hình đã đo:

| Pha | ngang, 0° | ngang, xoay 90° | **dọc, 0°** |
|---|---|---|---|
| nằm ngửa | 56% | 95% | 44% |
| nghiêng trái | 90% | 59% | **99%** |
| nghiêng phải | 11% | **25%** | **25%** |
| ngửa + chăn | 66% | 66% | 33% |

**Bất đối xứng trái/phải rất mạnh và nhất quán.** Nghiêng phải đứng im ở 25% qua hai cấu hình khác hẳn nhau, trong khi nghiêng trái đạt tới 99%. Hướng khung hình không giải thích được — nguyên nhân nhiều khả năng là vật lý: camera lệch về một bên giường, hoặc ánh sáng một bên. **Còn treo, cần dời camera vào giữa giường rồi đo lại.**

Các số còn lại dao động lớn giữa ba cấu hình (nằm ngửa 44–95%, chăn 33–66%) mà không theo quy luật rõ ràng, gợi ý còn biến số chưa kiểm soát: vị trí người trong khung, khoảng cách, ánh sáng theo giờ. Mỗi lượt chỉ 45s/pha, một người, một phiên — đừng đọc các con số này như hằng số của hệ thống.

## Bài đo có nhãn 17/08 — luật phân loại tư thế thất bại

Camera đã gắn chĩa xuống giường. Bài 4 pha × 45s, người nằm theo hiệu lệnh trên cửa sổ nên mọi frame có nhãn thật (`--protocol`, `protocol.py`). 2089 frame, **0 lần đọc hỏng**.

| Pha (nhãn thật) | Phát hiện | Đoán đúng | Đoán sai thành |
|---|---|---|---|
| nằm ngửa | 56% | 33% | nghiêng phải 66% |
| nghiêng trái | 90% | 34% | nằm ngửa 54% |
| nghiêng phải | **11%** | 34% | không rõ 36%, nằm ngửa 26% |
| nằm ngửa + chăn | 66% | 25% | nghiêng phải 64% |

Lần đo lại sau khi xoay đúng 90° (dữ liệu sạch, pha nằm ngửa đạt 95% phát hiện):

| Pha (nhãn thật) | Đoán đúng | Đoán sai thành |
|---|---|---|
| nằm ngửa | 23% | nghiêng phải 76% |
| nghiêng trái | **0%** | nằm ngửa 84%, nghiêng phải 16% |
| nghiêng phải | 52% | nằm ngửa 43% |
| nằm ngửa + chăn | 16% | nghiêng phải 82% |

Lần đo thứ ba, người nằm **dọc** (cơ thể thẳng đứng sẵn trong khung, `--rotate 0`):

| Pha (nhãn thật) | Phát hiện | Đoán đúng |
|---|---|---|
| nằm ngửa | 44% | 76% |
| nghiêng trái | 99% | **1%** |
| nghiêng phải | 25% | 3% |
| nằm ngửa + chăn | 33% | 83% |

### Kết luận cuối phiên 17/08: tách đúng hai bài toán

Sau bảy lượt đo, vấn đề "phân loại tư thế" hoá ra là **hai bài toán riêng biệt** đã bị lẫn vào nhau từ đầu:

**1. Biết là đang nằm nghiêng → xác định bên nào: GIẢI QUYẾT ĐƯỢC.**

Dấu của `vai_trái_lệch` (độ lệch ngang của vai trái so với trục hông→vai, chuẩn hoá theo chiều dài thân) tách sạch hai bên và tái lập qua cả ba phiên:

| | lượt 1 | lượt 2 | lượt 3 |
|---|---|---|---|
| nghiêng trái | −0.282 | −0.304 | −0.289 |
| nghiêng phải | +0.431 | +0.350 | +0.260 |

**2. Phân biệt nằm nghiêng với nằm ngửa: CHƯA CÓ TÍN HIỆU.**

Nằm ngửa cũng cho `vai_trái_lệch` dương (+0.42…+0.49), trùng vùng với nghiêng phải (+0.26…+0.43). Dấu dương vì thế không tách được hai lớp này. Luật hiện gộp nghiêng phải vào "nằm ngửa" và đạt 0% ở pha đó — **cố ý**, không phải bug.

Ba tín hiệu đã thử và loại:

| Tín hiệu | Vì sao loại |
|---|---|
| tỉ lệ vai/thân, ngưỡng 0.55 | Suy biến về một lớp; lớp đó đổi theo hướng khung hình |
| `z` hai vai | Cho cùng dấu ở cả hai bên nghiêng — không mang thông tin bên |
| `mũi_lệch` | Không tái lập: nghiêng phải −0.191 → −0.005 giữa hai phiên, đổi chỗ với ngửa+chăn qua ngưỡng |

**Bất đối xứng trong PHÁT HIỆN đảo chiều giữa các phiên** — nghiêng trái 98–99% ở lượt 2 nhưng 16% ở lượt 3; nghiêng phải 11–25% ở lượt sớm nhưng 100% ở hai lượt cuối. Không phải đặc tính của tư thế mà của bố trí từng lần (vị trí người trong khung, ánh sáng, khoảng cách). **Chừng nào bố trí chưa cố định thì các tỉ lệ phát hiện giữa các lượt không so sánh được với nhau.** Đây là lời giải cho dấu hỏi "nghiêng phải 25% → 100%" từng treo trong phiên.

Số tốt nhất đạt được: **30.2/33 landmark nhìn rõ**, nhận nằm ngửa **99%** (ba lượt liên tiếp), nghiêng trái **89%**.

### ĐÍNH CHÍNH sau lượt đo thứ tư (đã tắt hmirror)

Kết luận "bỏ luật, đầu ra suy biến" bên dưới được rút ra từ dữ liệu đo khi ảnh **còn bị lật gương** và phát hiện kém. Lượt thứ tư — sau khi tắt `hmirror` ở firmware — cho bức tranh khác hẳn:

| Pha | Phát hiện | Đoán đúng | Sai thành |
|---|---|---|---|
| nằm ngửa | 93% | **92%** | — |
| nghiêng trái | 88% | **5%** | nghiêng phải 67% |
| nghiêng phải | **100%** | 37% | nằm ngửa 63% |
| ngửa + chăn | 84% | **97%** | — |

Tổng: 2324 frame, **87% phát hiện, 24.4/33 landmark, 0 lần đọc hỏng** — tốt nhất từ đầu dự án.

**Trạng thái thật của luật:**
- **Ngửa vs không-ngửa: dùng được** (92% và 97%, kể cả khi đắp chăn).
- **Trái vs phải: không dùng được** (5% và 37%). Nằm nghiêng trái bị đọc thành nghiêng phải 67% — đảo bên có hệ thống.

Đảo dấu phép so `z` KHÔNG cứu được: pha trái sẽ lên ~67% nhưng pha phải tụt về 0%. `z` của MediaPipe không mang đủ thông tin phân biệt bên ở bố trí này, chứ không phải sai dấu.

Luật không suy biến về một lớp như đã kết luận: nó xuất ra `nghiêng phải` ở 27% số frame và đúng 37% ở đúng pha đó.

**Bất đối xứng trái/phải trong PHÁT HIỆN đã tự biến mất** (nghiêng phải: 11–25% → 100%) mà chưa rõ nguyên nhân. Lật gương về lý thuyết không ảnh hưởng tỉ lệ phát hiện. Chưa xác nhận được bố trí vật lý có đổi giữa hai lượt hay không. **Còn treo.**

---

Phần dưới đây giữ lại làm lịch sử suy luận, **đã bị đính chính ở trên**:

**Kết luận (ĐÃ SAI): bỏ luật hình học thủ công trong `posture.py`. Đầu ra của nó suy biến về một lớp.**

Điểm 76–83% ở hai pha nằm ngửa KHÔNG phải bằng chứng luật chạy đúng. Phân bố nhãn toàn phiên là `nằm ngửa 90%, nghiêng trái 5%, nghiêng phải 4%` — luật gần như luôn trả lời "nằm ngửa". Một luật hằng số sẽ cho đúng hình dạng kết quả này: cao ở pha ngửa, ~0 ở pha nghiêng.

Bằng chứng quyết định là **lớp bị sụp vào thay đổi theo hướng khung hình**:

| Cấu hình | Phân bố nhãn |
|---|---|
| nằm ngang, xoay 90° | nghiêng phải 58%, nằm ngửa 40%, nghiêng trái 1% |
| nằm dọc, xoay 0° | nằm ngửa 90%, nghiêng trái 5%, nghiêng phải 4% |

Cùng người, cùng bốn tư thế, chỉ khác hướng khung. Tỉ lệ vai/thân bị chi phối bởi hình học khung ảnh chứ không bởi tư thế cơ thể. Không ngưỡng nào sửa được chuyện đó.

(Chẩn đoán trước đó trong phiên — "quan hệ hình học bị ngược" — sai. Dữ liệu lượt ba cho thấy vấn đề là suy biến một lớp, không phải đảo chiều.)

**Đắp chăn không tệ như lo ngại**: 66% phát hiện, ngang hoặc hơn nằm ngửa lúc chưa xoay. Giả thuyết "chăn che giết pipeline" trong report brainstorm 14/08 chưa được dữ liệu này ủng hộ. Nhưng nhãn tư thế ở pha này sai 84% — chăn không giết phát hiện, mà giết phân loại.

## PoC pose: đường ống thông, chưa nghiệm thu

Chạy được từ Windows (WSL2 NAT không route sang `192.168.0.x`). Phải cài mediapipe trước — xem mục 5.

Hai lần chạy:

| Lần | Thời lượng | fps TB | Đọc hỏng |
|---|---|---|---|
| 1 | 11s | 12.6 | 0/138 |
| 2 | 7s | 16.5 | 0/108 |

**Kết luận được:** toàn chuỗi camera → WiFi → MJPEG → OpenCV → MediaPipe hoạt động. 0 lần đọc hỏng trên 246 frame. Không crash.

**KHÔNG kết luận được — chưa nghiệm thu:**

- Cả hai lần đều chỉ chạy 7–11 giây (cửa sổ bị đóng sớm), quá ngắn để nói về độ ổn định.
- **Nhiều khả năng không có người trong khung.** 16.5–18.5 fps nằm ở vùng cảnh trống (baseline 22.8); có người thật thì model chạy đủ hồi quy 33 landmark và tụt về ~8.7. Camera hiện **chưa gắn, đang để trên bàn**, không chĩa vào chỗ nằm.
- Chưa test recovery (rút nguồn giữa chừng).
- Script không in tỉ lệ phát hiện, nên không phân biệt được "không có người" với "có người mà model trượt". Đây là **thiếu sót của công cụ đo**: fps là chỉ báo gián tiếp và mơ hồ. Cân nhắc log số frame có/không có landmark.

Bài nghiệm thu thật cần: gắn camera chĩa xuống giường, rồi nằm ngửa → nằm nghiêng → nằm nghiêng có đắp chăn, mỗi tư thế ~1 phút. Ca khó là nằm nghiêng (nửa thân bị che) và đắp chăn (mất contour), cộng góc chụp từ trên xuống khác dữ liệu huấn luyện của MediaPipe.

Hoãn sang phiên sau theo quyết định của chủ dự án (16/08).

## Cảnh báo bảo mật đang hiện hữu

Stream **không có xác thực** (hazard H-25), và node đang nằm trên **WiFi công cộng dùng chung** — không phải mạng bench cách ly như `firmware/README.md` yêu cầu. Bất kỳ ai trong quán mở `http://192.168.0.120/` đều xem được camera. Tắt nguồn board khi ngừng thử.

## Câu hỏi chưa giải quyết

1. Mất WiFi giữa đêm nên xử lý thế nào — retry vô hạn, tự restart, hay giữ nguyên hành vi dừng? (mục 1 ở trên)
2. Có sửa lỗ hổng CI (`lint.yml` bỏ sót `scripts/`) không?
3. Số fps đo trên mạng quán cà phê có cần đo lại trên mạng bench trước khi ghi vào `docs/sensor-characterization.md` không?
