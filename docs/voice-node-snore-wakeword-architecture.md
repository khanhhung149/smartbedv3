# Kiến trúc đề xuất: Snore Detection + Wakeword chung 1 mic trên voice-node

**Trạng thái (2026-08-12): model TFLite Micro THẬT đã tích hợp, đã flash + verify trên board thật —
pipeline kỹ thuật chạy đúng (arena/op resolver/tensor type xác nhận qua log thật, latency đo được
~114ms/lần). CHƯA test tay với âm thanh ngáy thật (chỉ mới đo được ở phòng yên tĩnh).** Tài liệu này
ban đầu là đề xuất kiến trúc thuần (brainstorm 2026-08-12), sau đó scaffold bằng placeholder RMS
(`plans/260812-1029-...-scaffold/`), và nay (`plans/260812-1401-voice-node-snore-model-integration/`)
đã thay placeholder bằng model pretrained thật từ
[`alek6kun/snore-recognition`](https://github.com/alek6kun/snore-recognition) (Apache-2.0, TensorFlow
Authors — bản retrain ví dụ TFLite Micro `micro_speech` trên dataset Khan 2019, 500 mẫu ngáy/500 mẫu
không ngáy). Xem mục 6a. Số liệu accuracy thực địa (test tay với âm thanh ngáy thật) **CHƯA có** — cần
người thao tác phát âm thanh gần mic, ghi rõ ở mục 6a khi có.

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
Core 1 (APP CPU, loop() Arduino)
  i2s_read() 256 mẫu/lần
       │
       ├──► Wakeword feature+inference (đã có, ~5.4ms, chạy MỌI frame)
       │
       ├──► Đẩy frame vào queue gửi WS (chỉ memcpy 512B, KHÔNG chờ mạng — xem 4.3)
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

### 4.3. Task thứ ba: `wsSendTask` (core 0) — gửi WebSocket

Thêm 2026-08-18, cùng triết lý "tách chỉ phần nặng/chậm ra khỏi vòng mic":

`webSocket.sendBIN()` của `links2004/WebSockets` gửi ĐỒNG BỘ — `WebSockets::write()` lặp `tcp->write()`
tới khi hết byte hoặc timeout 5s. Khi TCP nghẽn, gọi nó trong `loop()` là chặn luôn `i2s_read()`: đo
trên board thấy 2 stream đứng 1372ms và 1979ms, backend không nhận byte nào trong ngần ấy thời gian nên
cắt utterance làm đôi, sinh mảnh 48-160ms bị bỏ.

- `wsSendTask` (core 0, priority 2, stack 6144) **sở hữu trọn vẹn** `webSocket`: gọi cả `webSocket.loop()`
  lẫn `sendBIN`. Lib KHÔNG thread-safe (hai đường đều chạm `_client.tcp`), nên không thể chia đôi.
- `loop()` chỉ `wsQueuePush()`: copy 512B vào frame lấy từ pool. Pool 128 frame (~2s audio, 64KB) đặt
  PSRAM; hai queue giữ CON TRỎ (đầy/rỗng) nên chỉ tốn ~1KB DRAM.
- Queue đầy (TCP tắc lâu hơn 2s) → thả frame CŨ NHẤT, giữ phần mới nhất của câu; đếm vào `wsQueueDropped`.
- Marker `samples == 0` đi qua CHÍNH queue đó để gửi khung text `"eou"` báo hết câu — nhờ chung hàng đợi
  nên nó luôn tới sau frame cuối, kể cả khi TCP đang tắc.
- Cấp phát lỗi → task không tạo, `loop()` quay về gửi đồng bộ như trước (không ai tranh `webSocket`).
- OTA `onStart` suspend task trước khi `webSocket.disconnect()`.

Đo lại (18/08, 3 vòng): `gapMaxMs` (khoảng cách giữa 2 lần đẩy frame) 88-240ms so với 1372/1979ms trước
đó, `dropped=0`, `i2sTimeout=0` — dù `wsSendMaxUs` vẫn lên tới 1,23s khi TCP giật. Backend hết mảnh ngắn:
6 TRIGGER → đúng 6 utterance.

### 4.4. Khi nào mới cân nhắc kiến trúc Ring Buffer đầy đủ (Option A gốc)

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
- Quantization — model snore thật (mục 6a) dùng UINT8 full-integer (không phải INT8 như wakeword) —
  không đặt mục tiêu cứng "model < 32KB, RAM < 80KB" như tài liệu cũ gợi ý; N16R8 có 16MB Flash/8MB
  PSRAM, dư địa đủ lớn. Ngân sách tài nguyên nên tính trên toàn hệ thống (audio buffer + tensor arena
  wakeword + tensor arena snore + WiFi/MQTT stack), không phải mục tiêu model nhỏ nhất.

## 6a. Model snore thật — TÍCH HỢP XONG (code), CHƯA FLASH/TEST HARDWARE (2026-08-12)

**Trạng thái: đã tích hợp, KHÔNG còn là đề xuất.** Xem
`plans/260812-1401-voice-node-snore-model-integration/` cho chi tiết implementation.

Model: [`alek6kun/snore-recognition`](https://github.com/alek6kun/snore-recognition) (Apache-2.0) — bản
retrain ví dụ TFLite Micro `micro_speech` chính thức của Google trên dataset Khan 2019 (T. H. Khan, "A
deep learning model for snoring detection and vibration notification using a smart wearable gadget",
Electronics, vol. 8, no. 9, 2019). README repo gốc công bố accuracy 95% trên tập test CỦA HỌ (không phải
đo tại nhà user) — số này KHÔNG được coi là bằng chứng độ chính xác thật tại vị trí lắp đặt, chỉ là điểm
khởi đầu hợp lý để KHÔNG train từ đầu.

**Đã xác minh trực tiếp** (không suy đoán từ README):
- `firmware/voice-node/models/snore.tflite` — 171832 byte, magic `TFL3` đúng offset 4 (chuyển từ
  `model.cc` định dạng `xxd -i` của repo gốc bằng script Python dùng 1 lần, không commit).
- 2 lớp output `{"snoring", "background"}` (index 0 = snoring), qua `Logistic` ở lớp cuối.
- `kAudioSampleFrequency=16000` khớp `SAMPLE_RATE` hiện tại — KHÔNG cần resample.
- Feature extraction: window 32ms/step 16ms/30 kênh mel/dải 40-6000Hz — KHÁC hẳn wakeword (30ms/10ms/40
  kênh/125-7500Hz), 2 instance `FrontendState` độc lập (`SnoreFeatures` vs `WakewordFeatures`).
- Input model là uint8 **THÔ đã rescale thủ công** lúc train (`(frontend_raw*128)/335`, clamp
  [0,255]), KHÔNG phải affine-quantize chuẩn TFLite qua scale/zero_point như input wakeword (int8) —
  đọc trực tiếp từ `main/micro_features_generator.cc` repo gốc, cài trong `SnoreFeatures::pushSamples()`
  (`firmware/voice-node/src/snore_features.cpp`).
- Output NGƯỢC LẠI dequantize qua `scale`/`zero_point` thật đọc từ tensor (`SnoreModel::infer()`,
  `firmware/voice-node/src/snore_model.cpp`) — an toàn hơn cách repo gốc so thẳng uint8 thô với ngưỡng
  128 (ngầm định zero_point=0/scale=1/255).
- Op resolver 11 op (`Conv2D/FullyConnected/Reshape/MaxPool2D/Shape/StridedSlice/Pack/ResizeBilinear/
  Quantize/Dequantize/Logistic`), đọc trực tiếp từ `main/main_functions.cc` repo gốc — KHÔNG có
  resource-variable ops (`VarHandle`/`CallOnce`) như wakeword vì model này KHÔNG streaming.
- `SNORE_SCORE_THRESHOLD = 0.5f` (thay `SNORE_PLACEHOLDER_THRESHOLD=500.0f` đơn vị RMS cũ) — điểm giữa
  hợp lý cho sigmoid/Logistic, khớp gần đúng ngưỡng 128/255≈0.502 mà repo gốc dùng. Đây là số KHỞI ĐIỂM,
  cần tinh chỉnh khi có test tay thật với âm thanh ngáy (chưa làm — xem "Việc còn thiếu" bên dưới).

**Build đã xác nhận** (`pio run -e esp32s3_kws`, nhiều lần qua các vòng sửa lỗi thật — xem dưới).

**Code review (2026-08-12, agent `code-reviewer`) tìm 2 vấn đề, đã sửa**: output tensor type chưa được
validate trước khi đọc `data.uint8` (đọc sai kiểu không crash, chỉ cho điểm số vô nghĩa — thêm check
`g_output->type == kTfLiteUInt8` vào `SnoreModel::begin()`); stack `snoreTask` 4096 byte kế thừa từ
placeholder RMS cũ, không đủ cho `Invoke()` thật — tăng lên 8192 byte.

**Flash board thật + đo THẬT (2026-08-12, ESP32-S3-CAM N16R8, board thật gắn qua TTL/CH340)**:
- Lần flash đầu tiên (arena 100KB tĩnh DIRAM) **LỖI THẬT** đúng như rủi ro plan cảnh báo: `Failed to
  resize buffer. Requested: 152384, available 98580, missing: 53804` — 100KB không đủ, `[snore] model
  init: features=OK model=LỖI -> TẮT`. DIRAM lúc đó chỉ còn ~57KB trống, không đủ tăng tĩnh lên mức cần
  → quyết định (xem
  `plans/reports/brainstorm-260812-1542-wakeword-arena-psram-migration-report.md`) chuyển
  `kTensorArenaSize` sang 200KB cấp phát ĐỘNG trên PSRAM (`heap_caps_aligned_alloc(...,
  MALLOC_CAP_SPIRAM)` trong `SnoreModel::begin()`) thay vì mảng tĩnh — PSRAM 8MB gần như trống, DIRAM chỉ
  còn ~57KB. Nhân tiện dời luôn wakeword arena (34KB) sang PSRAM cùng cách (xem mục "Wakeword gate" ở
  `docs/system-architecture.md`) — RAM tĩnh toàn firmware giảm từ 58.6% xuống **16.7%** (192024→54816
  byte) vì 2 arena không còn tính vào ảnh linker.
- Sau fix: `[snore] model sẵn sàng: arena dùng=156332/204800 byte, input type=3 bytes=1830, output
  type=3 bytes=1` — `input type=3`/`output type=3` = `kTfLiteUInt8` xác nhận đúng giả định (không phải
  suy luận từ upstream nữa, đọc trực tiếp từ model đã convert). `bytes=1830` = đúng 61×30 (khớp
  `SnoreFeatures::kFeatureSliceCount × kNumChannels`). `[snore] model init: features=OK model=OK ->
  sẵn sàng`.
- **Latency `SnoreModel::infer()` đo thật**: 105-129ms, trung bình ~114ms (so với wakeword 5-12ms, ~17-20x
  nặng hơn — đúng dự đoán "nặng hơn hẳn do Conv2D/MaxPool2D/ResizeBilinear" trong plan). Chạy 1 lần/~1s
  nên KHÔNG ảnh hưởng nhịp I2S/wakeword (khác core, task riêng).
- `uxTaskGetStackHighWaterMark(snoreTaskHandle)` **đã đo trực tiếp** (2026-08-13, xem mục 11) —
  3804 byte free / 8192 byte khai báo (dùng ~53.6%), xác nhận không cần suy luận gián tiếp qua
  stack-canary nữa.
- `SnoreFeatures`/`SnoreModel` pipeline: score = 0.000 liên tục qua nhiều chục lần đọc — **phòng yên
  tĩnh lúc đo, CHƯA có tiếng ngáy thật để test dương tính**. Không phân biệt được đây là "model đúng,
  đang im lặng thật" hay "pipeline luôn trả 0 bất kể input" chỉ từ số liệu này — cần test tay đối chứng
  âm thanh có/không ngáy (xem dưới), đúng cảnh báo Risk Assessment của plan.

**Việc còn thiếu (CẦN người thao tác phát âm thanh, không tự động hoá được)**:
- Test tay âm thanh ngáy thật + test đối chứng (nói chuyện/TV/im lặng) — xác nhận score đổi hợp lý theo
  input (không phải hằng số 0 bất kể input), đo số lần trigger giả ban đầu qua MQTT
  `home/room/snore_event`. Dataset train (Khan 2019) khác acoustic phòng ngủ thật của user — test tay
  ban đầu chỉ xác nhận PIPELINE kỹ thuật, KHÔNG phải bằng chứng độ chính xác dùng hàng đêm (cần soak
  test riêng, ngoài phạm vi hiện tại).
- Tinh chỉnh `SNORE_SCORE_THRESHOLD`/`SNORE_CONSECUTIVE_WINDOWS`/`SNORE_COOLDOWN_MS` dựa trên kết quả
  test tay ở trên — số hiện tại (0.5f/3/5000ms) là điểm khởi đầu, chưa phải số đã tune.

## 7. Event Manager + mở rộng MQTT contract — ĐÃ SCAFFOLD XONG (2026-08-12)

**Trạng thái: đã triển khai bằng placeholder, KHÔNG còn là đề xuất.** Xem
`plans/260812-1029-voice-node-snore-buffer-task-scaffold/phase-02-event-manager-mqtt-topic.md` cho chi
tiết + số liệu đo thật.

`firmware/voice-node` đã có 1 dạng Event Manager tối giản cho wakeword: `WAKEWORD_COOLDOWN_MS` (thêm
2026-08-11, xem `docs/system-architecture.md`) — chặn 1 utterance thật bị tách thành nhiều trigger giả
do score dư âm còn cao vài frame sau khi kết thúc. Nguyên tắc y hệt áp dụng cho snore, đã cài đặt trong
`snoreTask()`: N=3 cửa sổ liên tiếp vượt `SNORE_SCORE_THRESHOLD` (0.5f — **đã đổi từ**
`SNORE_PLACEHOLDER_THRESHOLD`=500.0f đơn vị RMS cũ, xem mục 6a) mới confirm event, sau đó cooldown 5s
trước khi gửi event kế tiếp. Kiến trúc Event Manager (N cửa sổ + cooldown) GIỮ NGUYÊN 100% từ scaffold —
chỉ đổi NGUỒN của giá trị so ngưỡng, từ RMS placeholder sang score model thật.

**Topic đã thêm vào contract thật** (`firmware/mqtt/README.md`, canonical source, VÀ
`docs/system-architecture.md`):

| Topic | Direction | Payload | Retain | QoS |
|-------|-----------|---------|--------|-----|
| `home/room/snore_event` | voice-node → backend | `{"ts":millis(),"confidence":0-1,"duration_ms":int}` | ❌ | 1 |

`ts` = `millis()` (uptime tương đối, KHÔNG phải unix epoch — voice-node không có NTP sync, xem
`firmware/mqtt/README.md`). `confidence` = điểm số lớp "snoring" của model thật, đã dequantize về [0,1]
(xem mục 6a) — **đã thay** mô tả cũ "RMS chuẩn hoá" (placeholder trước 2026-08-12).

**Đo thật xác nhận (test tay, vỗ tay/hét to sát mic, giai đoạn placeholder RMS, trước 2026-08-12)**:
publish thành công qua `mqtt.publish()` (thread-safety xử lý bằng cờ `snoreEventPending`, KHÔNG gọi
publish trực tiếp từ `snoreTask` — lib `256dpi/MQTT` không có mutex nội bộ nào, xác nhận qua đọc
source). Subscriber `mosquitto_sub` nhận đúng 2 message riêng biệt trong 60s (`confidence=0.628` và
`0.701`), không bị dồn dập — xác nhận cooldown hoạt động, không kẹt trạng thái. Cơ chế MQTT/cooldown này
KHÔNG đổi khi thay placeholder bằng model thật (mục 6a) — chỉ nguồn `confidence` đổi, đợi test tay lại
với model thật để có số liệu mới (xem "Việc còn thiếu" ở mục 6a).

## 8. Chỉ số đánh giá (áp dụng khi đo thật, không phải số mục tiêu cố định)

**Wakeword** (đã đo thật, tham khảo): true detection rate, false accept rate, latency — xem
`docs/system-architecture.md`.

**Snore** (chưa đo, cần đo khi có model): precision, recall, F1, **false alarm/hour**, missed
event/hour, latency, ổn định theo từng người. Với theo dõi giấc ngủ, false alarm/hour và missed event
thường có ý nghĩa thực tế hơn 1 accuracy tổng quát — đúng bài học đã áp dụng cho wakeword false-trigger
rate (mục tiêu <1/h, thực đo 2.48/h, chấp nhận có lý do ghi rõ).

## 9. Quy trình triển khai (cập nhật trạng thái 2026-08-12)

1. **Hardware validation** — ✅ Xong (audio ổn định dài hạn qua wakeword đang chạy).
2. **Buffer tích luỹ cho snore** — ✅ Xong (`plans/260812-1029-...-scaffold/`).
3. **Snore model** — ✅ Xong CODE + đã chạy thật trên board (`begin()`/`AllocateTensors()`/`Invoke()`
   xác nhận qua log thật, xem mục 6a) — ❌ CHƯA test tay âm thanh ngáy thật (chỉ mới đo phòng yên tĩnh).
4. **Tích hợp task core 0** — ✅ Xong, latency đo thật ~114ms/lần, không ảnh hưởng nhịp I2S/wakeword
   (khác core, task riêng, xác nhận qua log wakeword vẫn chạy bình thường song song).
5. **Chạy đồng thời thật** (soak test wakeword + snore cùng lúc) — ✅ Đã xác nhận chạy song song ổn định
   trong lúc đo (cả 2 log liên tục không lỗi/crash) — ❌ CHƯA soak test dài hạn (qua đêm).
6. **MQTT**: Event Manager → `home/room/snore_event` — ✅ Cơ chế giữ nguyên từ scaffold — ❌ CHƯA test
   publish với confidence từ model thật (cần score đủ cao đủ lâu — cần âm thanh ngáy thật để trigger).
7. **Soak test qua đêm** — ❌ Chưa làm, ngoài phạm vi plan hiện tại.

## 10. Việc tiếp theo

Bước kế tiếp DUY NHẤT đang chặn: test tay với âm thanh ngáy thật + đối chứng (nói chuyện/TV/im lặng) gần
mic — cần người thao tác phát âm thanh, không tự động hoá được (xem "Việc còn thiếu" ở mục 6a). Firmware
đã flash sẵn trên board (2026-08-12), chỉ cần bật `pio device monitor -e esp32s3_kws` (hoặc
`screen /dev/ttyUSB0 115200`) để xem log `[snore] score=...` trong lúc test.

## 11. Ngân sách bộ nhớ toàn hệ thống (đo thật, 2026-08-13)

Số liệu dưới đo trực tiếp trên board thật qua log `[hb][perf]` (heartbeat, xem `main.cpp`), KHÔNG suy
đoán — xem `plans/260812-1619-power-memory-architecture-review/phase-01-instrumentation-baseline.md`
cho bối cảnh. Board chạy `ENABLE_WAKEWORD` + snore song song, mẫu lấy qua ~3 phút có kích hoạt wakeword
vài lần.

### PSRAM (Octal, 8MB = 8388608 byte)

| Vùng cấp phát | Kích thước | Ghi chú |
|---|---|---|
| Wakeword tensor arena | 34 KiB (34816 byte) | `heap_caps_aligned_alloc(..., MALLOC_CAP_SPIRAM)`, `wakeword_model.cpp` |
| Snore tensor arena | 200 KiB (204800 byte) | Cấp dư — dùng thật 156332 byte (log `[snore] model sẵn sàng`) |
| Snore accum + snapshot buffer | 62.5 KiB (64000 byte) | 2× `SNORE_WINDOW_SAMPLES` (16000 mẫu × 2 byte), `main.cpp` |
| **Tổng cấp phát chủ động** | **~296.5 KiB (303616 byte)** | ~3.6% của 8MB |
| **Free PSRAM đo thật** | **8080064 byte (~7.7 MiB)** | Log `[hb][perf] psramFree=...` |
| Chênh lệch (allocator overhead) | ~4.8 KiB (4928 byte) | MicroAllocator/MicroResourceVariables bookkeeping của 2 interpreter TFLM |

Kết luận: PSRAM dư rất nhiều (~96.4% còn trống), không phải điểm nghẽn cho kiến trúc hiện tại.

### SRAM nội bộ (320 KiB = 327680 byte)

| Chỉ số | Giá trị | Ghi chú |
|---|---|---|
| RAM tĩnh (.data+.bss, link-time) | 54848 byte (16.7%) | `pio run` size report, sau khi dời 2 arena sang PSRAM |
| Free heap runtime đo thật | ~189000 byte (dao động 188823–189099) | Log `[hb][perf] heapFree=...`, không có xu hướng giảm rõ trong 3 phút quan sát (cần Phase 2 soak test dài hạn để kết luận leak/không leak) |

### Stack high-water-mark (đo thật, board S3/Xtensa — API trả byte, KHÔNG nhân 4)

| Task | Khai báo | Free đo thật | Đã dùng | Tỷ lệ dùng |
|---|---|---|---|---|
| `loopTask` (core 1, Arduino main loop) | 8192 byte | 5232 byte | 2960 byte | 36.1% |
| `snoreTask` (core 0) | 8192 byte | 3804 byte | 4388 byte | 53.6% |
| `wsSendTask` (core 0, thêm 18/08) | 6144 byte | 4272 byte | 1872 byte | 30.5% |

Cả 3 task còn dư margin an toàn (>30% dùng, tức >69% free ở `wsSendTask`), không cần tăng kích
thước stack. `wsSendTask` đo 18/08 sau khi đã chạy qua nhiều utterance thật (gồm cả lần TCP
block hàng giây) — 6144 byte rộng hơn mức cần, hạ về 4096 vẫn an toàn nếu sau này cần chỗ.

### Latency `WakewordModel::infer()` sau khi dời arena sang PSRAM (đo thật)

| Chỉ số | Giá trị | So với baseline DIRAM 5.4ms (journal 08/08) |
|---|---|---|
| Min | ~5.43–5.46 ms | Gần bằng baseline (frame đơn giản, ít khác biệt PSRAM/DIRAM) |
| Avg (điển hình) | ~5.9–6.3 ms | +9–17% |
| Max (spike thỉnh thoảng) | ~10–15 ms | +85–178%, hiếm gặp — không xảy ra mọi frame |

Độ trễ tăng nhẹ ở mức trung bình, đúng dự đoán "PSRAM chậm hơn DIRAM cho truy cập ghi/đọc liên tục". Các
spike max (10-15ms) xảy ra không thường xuyên trong mẫu quan sát, chưa tương quan rõ với sự kiện cụ thể
nào (WiFi/MQTT hoạt động cùng lúc trên core 1) — không phải vấn đề với `WAKEWORD_COOLDOWN_MS=1200`
hiện tại (spike lớn nhất vẫn < cooldown), nhưng đáng theo dõi nếu tần suất tăng khi bật thêm tính năng
power-management (Phase 3-4).

## 12. Thu dữ liệu huấn luyện từ mic thật (2026-08-14)

Model snore hiện train trên dataset Khan 2019 — ngáy thu gần, phòng thu sạch. Mic INMP441 đặt
cách giường 30-40cm nghe khác hẳn: nhiễu nền phòng ngủ, đáp tuyến mic, khoảng cách. Đo trên board
14/08 thấy đúng biểu hiện lệch miền: model **có** phản ứng (score 0,05-0,29, 5 lần vượt 0,5) nhưng
không đủ tự tin để bắn EVENT.

Cách thu hẹp: thu mẫu qua ĐÚNG mic, ĐÚNG vị trí, ĐÚNG nhiễu nền, rồi trộn với dataset gốc và
train lại.

### Đường thu

Board (env `esp32s3_record`) bỏ qua wakeword, stream PCM16 liên tục vào `/api/voice/record`;
backend (`internal/voice/record.go`) ghi thẳng thành WAV, cắt từng đoạn 60s.

Tách hẳn khỏi đường `/api/voice/stream` đang chạy: đường wakeword→ASR→lệnh AC đã ổn định, không
đáng để một công cụ thu dữ liệu tạm thời chen vào.

### Quy trình

1. Bật ghi ở backend — `VOICE_RECORD_DIR=/records` (rỗng = endpoint không được đăng ký):
   ```
   cd backend && VOICE_RECORD_DIR=/records docker compose up -d --no-deps backend
   ```
2. Đổi nhãn buổi thu trong `platformio.ini` env `esp32s3_record`
   (`VOICE_RECORD_LABEL`: `snore` | `quiet` | `fan` | `talk`), rồi nạp:
   ```
   pio run -e esp32s3_record -t upload
   ```
3. Đặt mic **cách đầu người nằm 30-40cm**. Tính từ số đo thật: nền phòng ngủ ~30 dBA ↔ RMS 40-60;
   ngáy nhẹ 40 dBA@1m thành ~49 dBA ở 35cm ↔ RMS ~400, tức gấp 8-10 lần nền. Xa hơn 1m thì ngáy
   nhẹ chìm vào nền và không model nào cứu được.
4. Thu. Kiểm tra bằng log Serial `[record] đang thu, RMS=... ws=up` (5s/lần) và
   `docker exec home-backend ls /records`.
5. Xong thì trả board về bản chạy thật: `pio run -e esp32s3_kws -t upload`.

### Cần thu những gì

| Nhãn | Nội dung | Lượng |
|---|---|---|
| `snore` | Ngáy thật qua đêm, hoặc phát lại ở vị trí đầu giường | ~20-30 phút |
| `quiet` | Phòng ngủ im, chỉ nhiễu nền | ~20 phút |
| `fan` | Quạt/điều hoà chạy — nguồn dương giả nguy hiểm nhất | ~10 phút |
| `talk` | Nói chuyện, TV — model cũ từng bắn 0,996 với tiếng động ngẫu nhiên | ~10 phút |

### Trích đặc trưng phải dùng đúng pipeline của board

Biên dịch `src/microfrontend/lib/` thành `.so` rồi gọi từ Python — KHÔNG viết lại bằng librosa
hay thư viện khác. Model chỉ đúng khi đặc trưng lúc train trùng khít lúc inference; viết lại thì
noise_reduction, PCAN gain control và log_scale gần như chắc chắn lệch. Cấu hình phải khớp
`SnoreFeatures::begin()`: 30 kênh, window 32ms, step 16ms, band 40-6000Hz, rescale `(raw*128)/335`.

### Bẫy đã mắc — lượng tử hoá đầu vào

Model cũ có `input scale=0.0756, zero_point=183` trong khi board `memcpy` thẳng uint8 thô (0-255).
Cùng dữ liệu đó bị dequantize thành `(raw-183)*0.0756`, dải -13,8..+5,4 — không phải thang nó được
huấn luyện. Model chạy không báo lỗi nhưng nhận vào rác nên trả 0,000 mãi mãi.

Khi export TFLite phải ép `inference_input_type=uint8` với representative dataset ở thang `x/255`,
cho ra `scale=1/255, zero_point=0`. Kiểm lại bằng cách in `input_details[0]['quantization']` —
không khớp thì model vô dụng dù accuracy lúc train có đẹp đến đâu.
