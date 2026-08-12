# Kiến trúc đề xuất: Snore Detection + Wakeword chung 1 mic trên voice-node

**Trạng thái: ĐỀ XUẤT KIẾN TRÚC — CHƯA TRIỂN KHAI.** Tài liệu này ghi lại thiết kế đã thống nhất qua
brainstorm (2026-08-12), chỉnh sửa lại từ 1 tài liệu tham khảo bên ngoài (nội dung gốc dùng board/pin
giả định, không phải project này) cho khớp với `firmware/voice-node` thật. Chưa có dòng code nào cho
snore detection tồn tại trong repo tại thời điểm viết tài liệu này — mọi số liệu (accuracy, false
alarm/hour, latency inference) đều là **mục tiêu cần đo thật**, không phải kết quả đã có.

## 1. Bối cảnh

`firmware/voice-node` (ESP32-S3-CAM N16R8 + mic INMP441) đã chạy wakeword "Vừng ơi" tại board (TFLite
Micro + esp-nn), field-test xong 2026-08-12: true-positive 73.3%, false-trigger ~2.48/h, threshold
0.80 — xem `docs/system-architecture.md` §"Voice-Node (Decision Maker)" mục "Wakeword gate".

Ý tưởng mới: dùng **chung con mic đó** để phát hiện tiếng ngáy (snore detection) khi giám sát giấc ngủ,
thay vì thêm board/mic riêng. Cả 2 việc chạy đồng thời trên cùng 1 nguồn audio.

## 2. Nguyên tắc cốt lõi (giữ từ tài liệu tham khảo — đúng và không đổi)

- I2S chỉ có **một luồng thu âm duy nhất** — không dừng/gỡ cài đặt I2S để đổi qua lại giữa 2 việc.
- Wakeword và Snore là **hai bài toán khác nhau** (bảng dưới) → **hai model riêng biệt**, không gộp
  thành 1 model 4 lớp (`wakeword`/`snoring`/`noise`/`silence`). Gộp có vẻ tiết kiệm nhưng tối ưu 1 model
  cho 2 mục tiêu có đặc tính rủi ro khác nhau (false trigger tức thời vs false alarm/hour dài hạn) thường
  kéo cả 2 xuống, không nên mặc định chọn hướng này.
- Threshold/debounce/hysteresis phải đo bằng dữ liệu thật tại vị trí lắp đặt thật — không chốt số liệu
  suông. Đây đã là văn hoá sẵn có của dự án (xem cách wakeword threshold 0.80 được chốt ở
  `docs/system-architecture.md`), áp dụng y hệt cho snore.

| Đặc điểm | Wakeword (đã có) | Snore Detection (đề xuất) |
|---|---|---|
| Bản chất | Nhận diện mẫu giọng nói cụ thể | Phân loại sự kiện âm thanh |
| Thời lượng | Ngắn (~1s) | Kéo dài, lặp lại |
| Mục tiêu | Latency thấp, phát hiện tức thời | Theo dõi sự kiện qua nhiều giờ |
| Rủi ro chính | False trigger / missed wakeword | False alarm/hour / missed event |
| Chỉ số đánh giá | Detection rate, false accept rate | Precision, recall, false alarm/hour |

## 3. Phần cứng — KHÔNG đổi, dùng nguyên board+mic đã có

Tài liệu tham khảo gốc giả định pin GPIO1/GPIO2/GPIO42 (chưa biết board thật). Project này **đã có**
board thật đang chạy (`firmware/voice-node/platformio.ini` env `esp32s3_kws`):

| Tín hiệu | Pin thật (đã dùng) | Ghi chú |
|---|---|---|
| I2S SCK (BCLK) | GPIO5 | `CFG_I2S_SCK`, đã né vùng flash (26-32)/PSRAM octal (35-37)/strapping |
| I2S WS (LRCLK) | GPIO6 | `CFG_I2S_WS` |
| I2S SD (DOUT mic) | GPIO7 | `CFG_I2S_SD`, có pulldown (`gpio_set_pull_mode`) |
| IR blaster | GPIO8 | Không liên quan audio, giữ nguyên |
| Kênh I2S | ONLY_RIGHT | Đã xác nhận thật 30/07 — ONLY_LEFT cho RMS=0.0 tuyệt đối trên board này, đừng thử lại |

**Không cần đổi/đấu lại dây gì cho snore detection** — cùng 1 mic, cùng 1 I2S RX, chỉ thêm 1 consumer
phần mềm mới đọc cùng luồng PCM.

## 4. Kiến trúc audio pipeline đề xuất cho project này (khác kiến trúc gốc)

### 4.1. Vì sao KHÔNG theo nguyên văn "Ring Buffer + FreeRTOS task riêng cho từng engine"

Tài liệu tham khảo đề xuất kiến trúc chuẩn cho audio đa-consumer: 1 Ring Buffer dùng chung, Wakeword
Engine và Snore Engine là 2 FreeRTOS task độc lập đọc từ ring buffer theo nhịp riêng. Đây là kiến trúc
**đúng sách vở**, nhưng `firmware/voice-node/src/main.cpp` hiện tại là **1 vòng lặp Arduino đơn giản**
(không FreeRTOS task nào ngoài main loop), đã chạy **E2E thật ngoài đời** (README: "E2E CHẠY THẬT").
Đổi sang kiến trúc multi-task + ring buffer + mutex là thay đổi kiến trúc lớn, thêm rủi ro race
condition mới trên code đang chạy ổn định — không đáng đánh đổi khi chưa có bằng chứng cần thiết
(YAGNI).

### 4.2. Kiến trúc chọn: "B+" — vòng lặp đơn cho wakeword, tách riêng CHỈ bước snore inference sang core kia

```
Core 1 (APP CPU, loop() Arduino — KHÔNG ĐỔI GÌ so với hiện tại)
  i2s_read() 256 mẫu/lần
       │
       ├──► Wakeword feature+inference (đã có, ~5.4ms, chạy MỌI frame)
       │
       └──► Append vào buffer tích luỹ ~1s cho snore
                  (kiểu preRoll đã có sẵn trong main.cpp — memmove trượt, KHÔNG cần
                   cấu trúc ring buffer tổng quát mới)
                  │
                  │  khi đủ ~1s mẫu, COPY snapshot buffer (không phải con trỏ)
                  ▼
Core 0 (PRO CPU) ── 1 FreeRTOS task duy nhất, xTaskCreatePinnedToCore
  Snore feature extraction (MFCC/MFE) + inference, chạy ~1 lần/giây
  (KHÔNG đụng I2S, KHÔNG đụng wakeword — chỉ đọc snapshot đã copy sẵn)
       │
       ▼
  Snore score → temporal smoothing/hysteresis → Snore Event
```

**Vì sao chọn hướng này thay vì giữ 100% trong 1 vòng lặp (Option "B thuần")**: snore inference (MFCC
trên cửa sổ ~1s + model) nặng hơn hẳn wakeword (frame 30ms). Nếu chạy chung lõi với `i2s_read()`, một
lần inference chậm có thể làm trễ nhịp đọc I2S kế tiếp → nguy cơ mất mẫu audio (buffer overrun). Tách
sang lõi còn lại triệt tiêu rủi ro này mà **chỉ cần thêm 1 task đơn**, không cần hàng đợi/mutex phức tạp
như kiến trúc Ring Buffer đầy đủ — vì chỉ có 1 producer (loop chính) và 1 consumer (task snore), copy
snapshot 1 chiều mỗi ~1s là đủ, không có ai ghi ngược lại buffer đó.

**Lưu ý về "tranh chấp" khi 2 âm thanh chồng nhau** (VD ai đó ngáy đúng lúc người khác gọi "Vừng ơi"):
đây **không phải vấn đề kiến trúc phần mềm** — cả 2 engine cùng đọc **một** waveform PCM đã trộn sẵn từ
1 mic mono (giới hạn vật lý, không có 2 luồng audio tách biệt). Đây là bài toán độ bền với nhiễu nền
(cùng loại với TV/nói chuyện đã đo ở Phase 4 wakeword — kết luận thật: tạp âm KHÔNG phải nguyên nhân
chính gây trượt/báo giả). Không cần xử lý gì thêm ở tầng kiến trúc cho trường hợp này; đây là thuộc
tính cần đo bằng dữ liệu thật khi có model snore, không phải thứ thiết kế trước được.

### 4.3. Khi nào mới cân nhắc kiến trúc Ring Buffer đầy đủ (Option A gốc)

Nếu đo thật thấy: (a) snore inference trên core 0 vẫn ảnh hưởng core 1 (VD do tranh bus/cache, hiếm
nhưng có thể), hoặc (b) cần thêm consumer thứ 3 (VD cough detection) khiến việc quản lý nhiều buffer
tích luỹ riêng lẻ trở nên cồng kềnh — lúc đó mới đáng đổi sang Ring Buffer + multi-task như tài liệu gốc
đề xuất. Không làm trước khi có bằng chứng.

## 5. Thiết kế dữ liệu cho Snore Detection

### 5.1. Dataset

Không nên chỉ dùng dataset công khai (VD Kaggle Snoring Dataset). Cần bổ sung mẫu thu **từ chính**:
INMP441 + vị trí mic thật + khoảng cách tới người ngủ + phòng ngủ thật + tiếng ồn nền thật (quạt/điều
hoà/TV) — đúng bài học "acoustic thật khác phòng test" mà voice-node đã gặp với VAD năng lượng và
wakeword (xem `docs/system-architecture.md`, false-trigger thật 2.48/h khác biệt với ROC offline).

Nên tái dùng pattern các script thu mẫu đã viết cho wakeword (`scripts/sinh-mau-tts-local.py`,
`scripts/tai-mau-everai.py`, `scripts/thu-mau-wakeword.ps1`) — đổi mục tiêu sang thu mẫu ngáy thật +
hard-negative (nói chuyện, TV, quạt, điều hoà) thay vì mẫu giọng nói "Vừng ơi".

### 5.2. Lớp dữ liệu đề xuất

```
snoring
speech
noise
silence
other_sound
```

### 5.3. Data leakage

Chia train/validation/test theo **người/nguồn ghi âm**, không chia ngẫu nhiên từng đoạn — nếu cùng 1
người xuất hiện ở cả train và test, accuracy đo được không phản ánh khả năng tổng quát sang người mới.

## 6. Cấu hình DSP/TinyML

- Sample rate 16kHz mono, PCM16 — **đã khớp sẵn** với cấu hình I2S hiện tại của voice-node, không đổi.
- Feature extraction wakeword hiện dùng window 30ms / step 10ms / 40 mel channel
  (`firmware/voice-node/src/wakeword_features.h`) — **trùng khớp** baseline mà tài liệu tham khảo đề
  xuất cho DSP nói chung (30ms/10ms). Có thể tái dùng cùng thư viện `microfrontend` cho bước trích đặc
  trưng frame-level của snore, chỉ khác ở **kích thước cửa sổ tích luỹ** (~1s cho snore so với ~1s cũng
  cho wakeword nhưng dùng preRoll ngắn hơn nhiều).
- Baseline cần benchmark thật trên board (không chốt số cố định trước): thử window 500ms/1000ms/1500ms,
  dải tần 100-4000Hz / 200-4000Hz / 300-3800Hz, MFCC vs MFE — chọn dựa trên precision/recall/false
  alarm-per-hour/latency/RAM/Flash đo thật, đúng cách wakeword threshold đã được chốt (đo thật, không
  suy đoán).
- Quantization INT8 — không đặt mục tiêu cứng "model < 32KB, RAM < 80KB" như tài liệu cũ gợi ý; N16R8 có
  16MB Flash/8MB PSRAM, dư địa đủ lớn. Ngân sách tài nguyên nên tính trên toàn hệ thống (audio buffer +
  tensor arena wakeword + tensor arena snore + WiFi/MQTT stack), không phải mục tiêu model nhỏ nhất.

## 7. Event Manager + mở rộng MQTT contract — ĐÃ SCAFFOLD XONG (2026-08-12)

**Trạng thái: đã triển khai bằng placeholder, KHÔNG còn là đề xuất.** Xem
`plans/260812-1029-voice-node-snore-buffer-task-scaffold/phase-02-event-manager-mqtt-topic.md` cho chi
tiết + số liệu đo thật.

`firmware/voice-node` đã có 1 dạng Event Manager tối giản cho wakeword: `WAKEWORD_COOLDOWN_MS` (thêm
2026-08-11, xem `docs/system-architecture.md`) — chặn 1 utterance thật bị tách thành nhiều trigger giả
do score dư âm còn cao vài frame sau khi kết thúc. Nguyên tắc y hệt áp dụng cho snore, đã cài đặt trong
`snoreTask()`: N=3 cửa sổ liên tiếp vượt `SNORE_PLACEHOLDER_THRESHOLD` (500.0f, thấp hơn
`VAD_THRESHOLD_MIN`=600.0f) mới confirm event, sau đó cooldown 5s trước khi gửi event kế tiếp.

**Topic đã thêm vào contract thật** (`firmware/mqtt/README.md`, canonical source, VÀ
`docs/system-architecture.md`):

| Topic | Direction | Payload | Retain | QoS |
|-------|-----------|---------|--------|-----|
| `home/room/snore_event` | voice-node → backend | `{"ts":millis(),"confidence":0-1,"duration_ms":int}` | ❌ | 1 |

`ts` = `millis()` (uptime tương đối, KHÔNG phải unix epoch — voice-node không có NTP sync, xem
`firmware/mqtt/README.md`). `confidence` = RMS chuẩn hoá (đạt ngưỡng = 0.5, gấp đôi ngưỡng = 1.0, kẹp
trên) — KHÔNG phải điểm số model thật, sẽ đổi hẳn khi có model MFCC.

**Đo thật xác nhận (test tay, vỗ tay/hét to sát mic, 2026-08-12)**: publish thành công qua
`mqtt.publish()` (thread-safety xử lý bằng cờ `snoreEventPending`, KHÔNG gọi publish trực tiếp từ
`snoreTask` — lib `256dpi/MQTT` không có mutex nội bộ nào, xác nhận qua đọc source). Subscriber
`mosquitto_sub` nhận đúng 2 message riêng biệt trong 60s (`confidence=0.628` và `0.701`), không bị dồn
dập — xác nhận cooldown hoạt động, không kẹt trạng thái.

## 8. Chỉ số đánh giá (áp dụng khi đo thật, không phải số mục tiêu cố định)

**Wakeword** (đã đo thật, tham khảo): true detection rate, false accept rate, latency — xem
`docs/system-architecture.md`.

**Snore** (chưa đo, cần đo khi có model): precision, recall, F1, **false alarm/hour**, missed
event/hour, latency, ổn định theo từng người. Với theo dõi giấc ngủ, false alarm/hour và missed event
thường có ý nghĩa thực tế hơn 1 accuracy tổng quát — đúng bài học đã áp dụng cho wakeword false-trigger
rate (mục tiêu <1/h, thực đo 2.48/h, chấp nhận có lý do ghi rõ).

## 9. Quy trình triển khai đề xuất (nếu làm — chưa bắt đầu)

1. **Hardware validation**: xác nhận raw audio ổn định dài hạn (đã có sẵn qua wakeword đang chạy, không
   cần lặp lại bước này).
2. **Buffer tích luỹ cho snore**: thêm buffer trượt kiểu preRoll trong `main.cpp`, CHƯA có inference —
   xác nhận không mất mẫu I2S khi buffer tích luỹ chạy song song wakeword.
3. **Snore model**: dataset → DSP → training → validation → quantization → chạy thử inference trên
   board (chưa nối vào pipeline audio thật, test độc lập bằng mẫu ghi sẵn).
4. **Tích hợp task core 0**: nối snore inference vào task riêng như mục 4.2, đo latency + tác động lên
   nhịp I2S (mục tiêu: KHÔNG tăng false-trigger/miss của wakeword so với baseline đã đo).
5. **Chạy đồng thời thật**: soak test wakeword + snore cùng lúc, xác nhận cả 2 không suy giảm so với đo
   riêng lẻ.
6. **MQTT**: chỉ tích hợp Event Manager → `home/room/snore_event` sau khi bước 5 ổn định.
7. **Soak test qua đêm**: chạy thật nhiều đêm, đo memory leak/heap/PSRAM/WiFi-MQTT reconnect/false
   event — theo đúng văn hoá đo số liệu thật của dự án, không chốt ngưỡng sau vài lần thử qua loa.

## 10. Việc tiếp theo

Tài liệu này dừng ở mức kiến trúc đề xuất. Chưa tạo plan triển khai (`plans/`), chưa đụng code. Khi cần
triển khai thật, lập plan qua `/ck:plan` dựa theo quy trình 7 bước ở mục 9.
