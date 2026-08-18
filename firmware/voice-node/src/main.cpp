// Voice node — ESP32-S3 (env esp32s3/esp32s3_kws) hoặc ESP32-WROOM-32 (env esp32dev) + mic INMP441 (I2S)
// Env esp32s3_kws: mở stream bằng WAKEWORD "vừng ơi" (model microWakeWord chạy tflite-micro tại
// board, xem wakeword_features.{h,cpp}/wakeword_model.{h,cpp}) thay cho VAD năng lượng cũ.
// Env esp32dev/esp32s3 (không có esp32s3_kws): KHÔNG build wakeword — env đó là đường lui, giữ
// nguyên VAD năng lượng cũ (xem #ifdef WAKEWORD_GATE bên dưới).
// Sau khi mở stream (bằng wakeword hoặc VAD, tuỳ env): gửi binary PCM16 qua WebSocket tới backend
// ASR; im lặng một khoảng -> ngừng gửi (không đóng WS) để backend không phải nhận rác lúc không ai
// nói. Toàn bộ ASR nằm ở backend, board chỉ có nhiệm vụ stream audio sạch.
//
// Wiring thật (INMP441), xem docs/system-wiring.md. Số chân I2S khác nhau giữa
// hai board nên lấy từ build_flags, xem khối CFG_I2S_* bên dưới:
//               SCK (BCLK)   WS (LRCL)   SD (DOUT)
//   WROOM-32      GPIO26       GPIO25      GPIO34 (input-only)
//   ESP32-S3      GPIO5        GPIO6       GPIO7
// Chung cho cả hai:  L/R -> GND     VDD -> 3V3     GND -> GND
//
// Contract stream (đã chốt cùng backend Phase 2):
//   WS binary frame = PCM 16-bit 16kHz mono little-endian, gửi tới
//   ws://<backend>:8080/api/voice/stream — backend tự cắt utterance theo
//   khoảng lặng đọc được (read-deadline), node chỉ cần NGỪNG GỬI khi im lặng.

#include <Arduino.h>
#include <WiFi.h>
#include <ArduinoOTA.h>
#include <WebSocketsClient.h>
#include <MQTT.h>
#include <ir_Daikin.h>
#include <driver/i2s.h>
#include <driver/gpio.h>       // gpio_set_pull_mode() — pulldown chân SD của mic, xem setupI2S()
#include <math.h>
#include <esp_system.h>        // esp_reset_reason() — chẩn đoán lý do reset (9 = BROWNOUT)
#include <esp_heap_caps.h>     // heap_caps_malloc(MALLOC_CAP_SPIRAM) — buffer snore đặt PSRAM, xem bên dưới
#include <esp_timer.h>         // esp_timer_get_time() — đo gap giữa 2 frame gửi + thời lượng sendBIN (µs)
#include <atomic>              // std::atomic cho cờ handoff snoreEventPending/Confidence giữa 2 core

#include "config.h"

#ifdef ENABLE_WAKEWORD
#include "wakeword_features.h"
#include "wakeword_model.h"
#include "snore_features.h"
#include "snore_model.h"
#endif

// ---- Phần cứng ----
// Mặc định là số chân của WROOM-32; env S3 ghi đè qua build_flags. Bản đồ GPIO của
// ESP32-S3 khác hẳn ESP32 gốc: dải 22-25 KHÔNG tồn tại, 26-32 là bus SPI flash,
// 33-37 dành cho PSRAM octal. Cả ba chân I2S mặc định đều rơi vào vùng cấm đó.
#ifndef CFG_I2S_SCK
#define CFG_I2S_SCK 26
#endif
#ifndef CFG_I2S_WS
#define CFG_I2S_WS  25
#endif
#ifndef CFG_I2S_SD
#define CFG_I2S_SD  34
#endif
static const uint8_t PIN_I2S_SCK = CFG_I2S_SCK;  // BCLK, output từ ESP
static const uint8_t PIN_I2S_WS  = CFG_I2S_WS;   // LRCL/WS, output từ ESP
static const uint8_t PIN_I2S_SD  = CFG_I2S_SD;   // DOUT từ mic (trên WROOM-32 là chân input-only)

// ---- IR điều hoà Daikin ----
// KHÔNG dùng chân strapping: nó phải ở mức đúng lúc boot, mà đèn IR kéo chân xuống LOW là
// board không boot. (Strapping ESP32: GPIO0, 2, 5, 12, 15.  ESP32-S3: GPIO0, 3, 45, 46.)
// Mặc định GPIO4 — ngoài cả hai danh sách, dùng được cho cả hai board.
// env esp32s3 ghi đè sang GPIO8: trên board S3-CAM, GPIO4-7 nằm ở header camera với khoảng
// cách chân rất hẹp, hàn tay khó; GPIO8 ở hàng GPIO thường nên thoáng hơn. GPIO8 không phải
// strapping, không thuộc bus flash (26-32) hay PSRAM octal (33-37) của bản N16R8.
#ifndef CFG_IR_PIN
#define CFG_IR_PIN 4
#endif
static const uint16_t PIN_IR_SEND = CFG_IR_PIN;

// Daikin gửi TRỌN 35 byte trạng thái mỗi lần (kDaikinStateLength=35) — không có "lệnh bật"
// riêng lẻ. Nên khi tự bật phải set đủ nhiệt/chế độ/quạt, đây là mặc định hợp lý.
static const float   AC_DEFAULT_TEMP = 25.0f;
static const uint8_t AC_DEFAULT_MODE = kDaikinCool;
static const uint8_t AC_DEFAULT_FAN  = kDaikinFanAuto;

// Dải nhiệt độ Daikin chấp nhận. Kẹp ở firmware chứ không phó mặc cho thư viện: thư viện kẹp im
// lặng, còn ở đây kẹp xong còn log được để biết lệnh đã chạm trần.
static const float AC_TEMP_MIN = 16.0f;
static const float AC_TEMP_MAX = 30.0f;

static const char *TOPIC_AC_CMD   = "home/room/ac_cmd";
// PUBLISH — báo ngược trạng thái sau mỗi lần bắn IR. Backend không tự suy ra được nhiệt độ đang
// đặt vì lệnh chỉ nói "tăng/giảm", không nói đích.
static const char *TOPIC_AC_STATE = "home/room/ac_state";
// SUBSCRIBE (không publish) — nguồn presence duy nhất là radar-node.
static const char *TOPIC_PRESENCE = "home/room/presence";
// TOPIC_SNORE_EVENT khai báo cùng khối #ifdef ENABLE_WAKEWORD với phần state snore khác (bên dưới) —
// chỉ dùng trong loop() ở nhánh đó, khai riêng ở env esp32dev/esp32s3 (không wakeword) sẽ là biến chết.

// ---- Nguồn radar: radar-node publish home/room/presence ----
// voice-node chỉ NGHE topic này ({"ts","present"}); mọi lọc tinh (cự ly/năng lượng,
// chống báo giả xuyên tường) nằm ở radar-node / cấu hình LD2410. Không đọc SENSOR, không poll.
// Không nhận presence quá lâu -> coi link radar-node chết -> coi như KHÔNG có người (đừng
// để điều hoà chạy vĩnh viễn khi radar-node rớt). radar-node heartbeat presence mỗi 30s
// nên 90s là thừa an toàn.
static const uint32_t RADAR_LINK_TIMEOUT_MS = 90000;

// ---- Chính sách AC tại board (ESP32 là bộ não) ----
// Vào: presence giữ LIÊN TỤC đủ lâu -> bật AC. Ra: vắng đủ lâu -> tắt AC.
static const uint32_t ENTER_STABLE_MS = 800;    // thấy người liên tục 0.8s là occupied
static const uint32_t EXIT_TIMEOUT_MS = 60000;  // vắng 60s mới tắt (khớp EXIT_TIMEOUT_S=60)

// Khe hở tối thiểu giữa hai lần bắn IR. Một khung Daikin dài ~150ms và ac.send() CHẶN suốt thời
// gian đó, kéo dòng lên cao liên tục — đo thực địa 30/07: 5V tụt từ 4,6V xuống 4,0V khi bắn, và
// bắn dồn là kịch bản đã làm chết con WROOM. Nhiều nguồn có thể sinh lệnh sát nhau: một câu nói bị
// hai tầng VAD băm thành nhiều utterance giống nhau, trùng lặp do MQTT QoS 1 sau reconnect, nút
// trong app bấm liên tục, và fusion occupancy. Nhịp này là chốt cuối cho MỌI nguồn đó.
static const uint32_t IR_MIN_GAP_MS = 1500;

// Sau khi có lệnh tay (giọng nói / app), fusion occupancy KHÔNG được tự ghi đè trong khoảng này.
// Nếu không có: user nói "tắt điều hòa" trong lúc phòng vẫn có người, rồi presence chớp một nhịp
// là fusion bắn lại "bật" và phủ quyết ý người dùng. Backend statemachine đã có bảo vệ tương đương
// (xem prevOccupied trong internal/statemachine/machine.go); firmware trước đây thiếu.
static const uint32_t MANUAL_OVERRIDE_MS = 300000;  // 5 phút
static const uint32_t STATUS_HEARTBEAT_MS = 2000;

static const i2s_port_t I2S_PORT     = I2S_NUM_0;
static const uint32_t   SAMPLE_RATE  = 16000;   // đúng contract backend

// Kênh I2S để đọc INMP441. LƯU Ý QUAN TRỌNG: chân L/R của mic LUÔN nối GND và không bao giờ đổi —
// theo datasheet, nối GND là cách bảo mic đẩy dữ liệu vào nửa TRÁI của khung I2S. Hằng dưới đây chỉ
// chọn phía DRIVER đọc nửa nào, là chuyện hoàn toàn khác. Đổi cả dây lẫn hằng = đảo hai lần = vẫn sai.
//
// KHÔNG có giá trị đúng cho mọi board — lệch theo target và phiên bản IDF, phải thử. ONLY_RIGHT
// đúng cho CẢ HAI board đang dùng: đã thử ONLY_LEFT trên ESP32-S3 ngày 30/07 và đo RMS = 0.0
// tuyệt đối (mic không lái nửa trái). Kèm pulldown chân SD trong setupI2S(), số 0 đó là kết luận
// đáng tin chứ không phải "chưa có tín hiệu" — đó chính là lý do thêm pulldown.
#ifndef CFG_I2S_CHAN
#define CFG_I2S_CHAN I2S_CHANNEL_FMT_ONLY_RIGHT
#endif

// Mỗi lần đọc lấy 256 mẫu 32-bit (~16ms @16kHz) — đủ nhỏ để không tràn RAM,
// đủ lớn để không spam quá nhiều gói WS nhỏ.
static const size_t I2S_READ_SAMPLES = 256;

// VAD năng lượng, ngưỡng TƯƠNG ĐỐI theo nền nhiễu. Trước đây dùng hằng số tuyệt đối 2500 và nó
// hỏng: nền nhiễu trong phòng đo được nhảy từ ~250-1500 lên ~1500-2500 chỉ trong 40 phút, nên một
// con số cố định lúc thì bỏ sót tiếng nói, lúc thì mở utterance cho nhiễu. Nghiêm trọng hơn: hệ
// này sắp bật điều hòa bằng IR, tức TỰ tạo thêm tiếng ồn nền đúng lúc cần nghe lệnh "tắt điều hòa".
//
// Ngưỡng = max(nền × VAD_NOISE_MULT, VAD_THRESHOLD_MIN). Phòng yên thì ngưỡng tự hạ để bắt được
// câu nói nhỏ; phòng ồn thì tự nâng để khỏi mở cho nhiễu. Đổi MIC_SHIFT về sau KHÔNG cần tinh
// chỉnh lại, vì cả nền lẫn tiếng nói đều scale cùng hệ số — chỉ VAD_THRESHOLD_MIN phải scale theo.
static const float    VAD_NOISE_MULT     = 2.0f;
// Hệ số chỉ 2.0 (không phải 3-4) vì debounce VAD_ONSET_FRAMES đã lo phần gai nhiễu đơn lẻ; hệ số
// này chỉ cần lo mức duy trì. Đo thực địa: gai nhiễu đạt 2-3x nền nhưng gần như không bao giờ
// duy trì 3 frame liền, còn tiếng nói vượt 2x nền rất thoải mái.
// SÀN 150 -> 600 (31/07). Đo trên 66 utterance thu thật: nhiễu phòng RMS 90-250, giọng nói thật
// RMS 1200-3300 — hai dải cách nhau rất xa, mà sàn 150 (ngưỡng thực tế ~200 vì nền ~100) nằm ĐÚNG
// TRONG dải nhiễu. Hậu quả đo được: 45/66 utterance gửi lên whisper là nhiễu thuần, và whisper gặp
// nhiễu thì nhại lại initial_prompt. Một câu nhại THIẾU vế "tắt" ("Lệnh điều khiển điều hòa, bật
// máy lạnh.") chỉ chứa một động từ nên lớp loại-câu-mơ-hồ ở backend không bắt được -> đã publish
// cmd=on thật lúc 03:58:50 dù không ai nói gì.
// 600 nằm giữa hai dải, cách nhiễu ~2.4x và cách tiếng nói ~2x. Con số này gắn với MIC_SHIFT=13;
// đổi MIC_SHIFT thì phải scale sàn theo cùng hệ số.
static const float    VAD_THRESHOLD_MIN  = 600.0f;
static const float    NOISE_EMA_ALPHA    = 0.02f;   // ~50 frame (~0.8s) để nền theo kịp mà không giật
static const uint32_t SILENCE_MS         = 800;     // im đủ lâu mới coi hết câu, tránh cắt giữa câu

// Cửa sổ TỐI THIỂU phải stream sau khi wakeword kích, trước khi cho phép cắt theo im lặng.
//
// Vì sao cần: luật cắt dựa vào lastVoiceMs, mà lastVoiceMs chỉ cập nhật khi RMS vượt vadThreshold.
// Đo 17/08 trong phòng thật: nền RMS 148, giọng người dùng p99 chỉ 265 — gấp 1,8 lần nền, khoảng
// 5dB. Ngưỡng (sàn 600, hoặc nền×2 = 296) không bao giờ bị vượt, nên lastVoiceMs đứng yên ở mốc
// lúc trigger và utterance luôn bị cắt đúng SILENCE_MS sau đó. Đo thực tế: câu "vừng ơi tăng 1
// nhiệt độ" dài ~2s nhưng utterance gửi lên chỉ 0,96-1,23s, ASR nhận thiếu chữ và trả về
// "ƠI TĂNG MỘT CẦU".
//
// Không sửa bằng cách hạ vadThreshold: cùng hằng số đó còn là đường TRIGGER của env
// esp32dev/esp32s3 (không có wakeword) và là điều kiện học nền nhiễu. Hạ xuống 250 sẽ khiến hai
// env kia tự kích liên tục vì nhiễu nền đã 148.
//
// 3000ms: câu lệnh dài nhất trong bộ ("vừng ơi, giảm hai nhiệt độ") đo được ~2s kể cả wakeword,
// nên đây là biên an toàn 50%. Dài hơn nữa thì tăng độ trễ phản hồi và kéo theo đuôi im lặng dài
// gửi cho ASR — mà đuôi im lặng chính là thứ làm model bịa chữ.
static const uint32_t MIN_STREAM_MS      = 3000;

// Cần VAD_ONSET_FRAMES frame LIÊN TIẾP vượt ngưỡng mới mở utterance. Nhiễu nền chạm sát ngưỡng nên
// một gai đơn lẻ đủ mở stream -> khoảng 3/4 utterance gửi lên whisper chỉ là nhiễu, mà whisper gặp
// nhiễu thì ảo giác (đã thấy nó phun ra câu chào cuối video YouTube). Tiếng nói thật kéo dài nhiều
// frame liền nhau, gai nhiễu thì không -> debounce tách được hai loại.
static const uint8_t  VAD_ONSET_FRAMES = 3;

// Lọc thông cao một cực (DC blocker) ~80Hz, chạy ngay sau khi hạ bit và TRƯỚC khi clamp.
// INMP441 nhạy hạ tần rất mạnh: đo được clip có dc=-1562 và zcr=0.0028 (tương đương ~45Hz — không
// phải giọng người mà là tiếng ục/va chạm bàn/hơi bật khi nói gần). Năng lượng hạ tần đó gây ba
// tai hại cùng lúc: ăn hết headroom nên tiếng nói đập rìa (peak=32768), bơm phồng RMS nên VAD mở
// utterance cho những thứ whisper không đọc được, và tạo lệch DC. Cắt dưới 80Hz sửa cả ba, mà
// không chạm F0 của giọng người (nam ~100-150Hz, nữ ~200Hz).
//   y[n] = x[n] - x[n-1] + R*y[n-1],  R = 1 - 2*pi*fc/fs = 1 - 2*pi*80/16000
static const float    HPF_R = 0.9686f;

// MIC_SHIFT: INMP441 để tín hiệu ~2% full-scale khi >>16 -> whisper đoán mò, nên phải khuếch đại.
// Nhưng >>11 (~64% full-scale, -4 dBFS) KHÔNG còn headroom: đo được RMS 28954/32767 = 88% full-scale,
// mà sóng sin biên độ tối đa chỉ đạt RMS 70.7% -> dạng sóng đã bị clamp chặt phẳng thành sóng vuông.
// Whisper nghe sóng vuông chỉ thấy tiếng rè và trả về text rỗng: 29/31 utterance rỗng, và đúng những
// câu TO mới rỗng còn câu nhỏ vẫn nhận đúng. >>13 cho ~16% full-scale (-16 dBFS) — mức chuẩn cho ASR,
// còn ~16 dB dự phòng cho đỉnh. Giảm shift = to hơn nhưng clip; tăng = nhỏ hơn, whisper đoán mò.
static const uint8_t  MIC_SHIFT     = 13;

WebSocketsClient webSocket;

WiFiClient  net;              // TCP riêng cho MQTT (WebSocket dùng client nội bộ của lib)
MQTTClient  mqtt(512);        // payload presence/ac_cmd đều nhỏ (<128B)

static int32_t i2sRawBuf[I2S_READ_SAMPLES];  // dữ liệu thô từ I2S (32-bit slot)
static int16_t pcmBuf[I2S_READ_SAMPLES];     // PCM16 sau khi hạ bit, gửi thẳng qua WS

// LISTENING: chưa mở stream, chỉ nghe (chờ wakeword hoặc VAD onset, tuỳ env).
// STREAMING: đang trong một utterance -> có gửi frame qua WS.
enum class VoiceState : uint8_t { LISTENING, STREAMING };
VoiceState voiceState = VoiceState::LISTENING;

uint32_t streamStartMs = 0;    // lúc vào STREAMING — mốc đo MIN_STREAM_MS
uint32_t lastVoiceMs = 0;      // lần cuối RMS vượt ngưỡng — vẫn dùng để cắt SILENCE_MS dù mở
                                // stream bằng wakeword hay VAD (xem comment SILENCE_MS ở loop()).
uint32_t lastLogMs   = 0;      // throttle log Serial, tránh spam mỗi ~16ms

// ---- Đo khi STREAMING (debug 17/08, SAU fix WS task) ----
// sendBIN giờ chạy trong wsSendTask (không block loop mic nữa — xem wsSendTask). Các số này dùng
// để xác minh fix:
//   wsSendMaxUs      = thời gian sendBIN lâu nhất trong câu (đo ở wsSendTask) — vẫn lộ ra TCP giật,
//                      nhưng giờ KHÔNG block mic nữa.
//   wsQueueDropped   = số frame bị thả vì queue đầy — chỉ xảy ra khi TCP block lâu hơn dung lượng
//                      queue; không được > 0 nhiều (khi đó câu vẫn bị rỗng một khúc, cần tăng queue).
//   streamI2STimeout = số lần i2s_read timeout/0-byte trong stream — sau fix phải về 0 (mic không
//                      bao giờ bị nghẽn).
//   gapMaxMs         = khoảng cách lớn nhất giữa 2 lần ĐẨY frame vào queue — đây mới là thước đo
//                      tính liên tục của mic (trước fix nó bằng thời gian sendBIN block: 1372/1979ms).
uint32_t streamI2STimeout = 0;  // số lần i2s_read timeout/0-byte trong stream hiện tại
uint32_t streamSendGapUsMax = 0; // khoảng cách lớn nhất giữa 2 lần đẩy frame (µs)
uint32_t streamSendLastUs = 0;   // mốc lần đẩy frame trước (0 = chưa có)
uint32_t streamSendCount = 0;    // số frame đã đẩy trong stream hiện tại
std::atomic<uint32_t> wsSendMaxUs{0};    // max thời gian 1 lần sendBIN trong stream (µs)
std::atomic<uint32_t> wsQueueDropped{0}; // frame bị thả vì queue đầy (tăng ở wsQueuePush)
#ifdef VOICE_RECORD_MODE
uint32_t lastRecordLogMs = 0;  // throttle log chế độ thu (5s/lần, đủ để biết còn sống)
#endif
float    noiseFloor  = 0.0f;   // EMA nền nhiễu; 0 = chưa học, seed bằng frame đầu tiên đọc được

#ifndef ENABLE_WAKEWORD
uint8_t  onsetFrames = 0;      // (chỉ đường lui VAD) số frame liên tiếp vượt ngưỡng, chờ đủ VAD_ONSET_FRAMES
#endif

// Trạng thái bộ lọc thông cao — phải giữ qua các lần gọi, nếu reset mỗi frame thì mỗi ranh giới
// frame thành một bước nhảy và tự sinh ra tiếng tách 62.5Hz (16000/256).
float    hpfPrevX = 0.0f;      // x[n-1] — mẫu VÀO trước đó (chưa lọc)
float    hpfPrevY = 0.0f;      // y[n-1] — mẫu RA trước đó (đã lọc)

// Ring buffer giữ ~512ms audio gần nhất, flush ngay khi mở stream để không mất đầu câu lệnh.
//
// Kích thước cũ ((VAD_ONSET_FRAMES-1) * 256 = 32ms) tính theo debounce của VAD năng lượng, KHÔNG
// đủ cho wakeword: model streaming chỉ chốt điểm sau khi đã nghe trọn "Vừng ơi" cộng độ trễ tích
// luỹ khung, nên lúc TRIGGER thì người dùng thường đã nói sang động từ. Đo 2026-08-14 trên 15 mẫu
// thật: 2 mẫu mất hẳn động từ — CẢ BA model ASR độc lập (Whisper-small, PhoWhisper, Zipformer)
// đều chỉ nghe được "máy lạnh", tức động từ không có trong file chứ không phải model nghe nhầm.
// Đó là trần cứng mà không model nào vượt qua được; phải sửa ở đây.
//
// 512ms dư sức bao trọn độ trễ đó. Gửi lố cả wakeword vào đầu utterance là vô hại: parser chỉ tìm
// động từ + danh từ AC, và đã xác nhận câu "ƠI BẬT MÁY LẠNH" vẫn khớp đúng.
//
// Ring buffer (ghi vòng) thay vì memmove trượt như bản cũ: 16KB memmove mỗi 16ms là lãng phí CPU
// vô ích khi chỉ cần dịch một chỉ số.
static const size_t PREROLL_FRAMES = 32;  // 32 x 256 mẫu = 8192 mẫu = 512ms @16kHz = 16KB DIRAM
static int16_t preRoll[PREROLL_FRAMES * I2S_READ_SAMPLES];
static size_t  preRollWrite = 0;  // chỉ số FRAME sẽ ghi tiếp theo (quay vòng)
static size_t  preRollCount = 0;  // số frame hợp lệ đang giữ (bão hoà tại PREROLL_FRAMES)

// ---- Đường gửi WS: task riêng + queue frame PCM ----
//
// LÝ DO: webSocket.sendBIN() gửi đồng bộ — WebSockets::write() lặp tcp->write() chờ hết byte tới
// timeout 5s. Khi TCP nghẽn (WiFi giật) nó block hàng giây NGAY TRONG loop(), nên i2s_read không
// được gọi và backend không nhận byte nào ≥800ms -> flushIfSilent cắt utterance làm đôi, sinh ra
// mảnh 48-160ms bị bỏ (đo 17/08: 2 stream có sendBIN block 1372ms và 1979ms, khớp đúng 2 mảnh
// backend tách ra). Chi tiết: plans/reports/debug-260817-1736-...-tach-cau-report.md.
//
// Thư viện links2004/WebSockets KHÔNG thread-safe (sendBIN và loop() đều chạm _client.tcp), nên
// wsSendTask sở hữu TRỌN VẸN webSocket: vừa gọi webSocket.loop() vừa gọi sendBIN. loop() chính chỉ
// đẩy frame vào queue và không bao giờ chờ mạng.
//
// Queue giữ CON TRỎ vào pool frame đặt ở PSRAM (128 frame x 512B = 64KB): để 64KB trong DRAM là
// tiếc chỗ, còn queue con trỏ chỉ tốn 512B DRAM. 128 frame = ~2s audio, phủ được cả lần block
// 1979ms nặng nhất đo được.
struct WsFrame {
  uint16_t samples;                 // số mẫu hợp lệ (i2s_read có thể trả về ít hơn)
  int16_t  pcm[I2S_READ_SAMPLES];
};
static const size_t WS_QUEUE_FRAMES = 128;
static WsFrame     *wsFramePool = nullptr;
static QueueHandle_t wsQueue     = nullptr;  // frame đã có dữ liệu, chờ gửi
static QueueHandle_t wsFreeQueue = nullptr;  // frame rỗng, chờ được ghi
static TaskHandle_t  wsSendTaskHandle = nullptr;

// Đẩy 1 frame PCM sang wsSendTask. Không bao giờ chờ mạng.
// samples == 0 là MARKER hết câu: wsSendTask sẽ gửi khung text "eou" đúng thứ tự sau frame cuối
// (xem wsSendTask).
// Trả về false khi chưa có queue (lỗi cấp phát lúc setup) — lúc đó loop() tự gửi như bản cũ, vì
// wsSendTask cũng không chạy nên không ai tranh webSocket.
static bool wsQueuePush(const int16_t *pcm, size_t samples) {
  if (!wsQueue || !wsFreeQueue) return false;

  WsFrame *f = nullptr;
  if (xQueueReceive(wsFreeQueue, &f, 0) != pdTRUE) {
    // Hết frame rỗng = WS đang block lâu hơn 2s dung lượng queue. Thả frame CŨ NHẤT đang chờ để
    // giữ phần MỚI NHẤT của câu (cùng nguyên tắc ô chờ IR 1 slot): người dùng nói lại thì phần
    // mới mới là phần đáng gửi.
    if (xQueueReceive(wsQueue, &f, 0) != pdTRUE) return true;  // task vừa lấy hết: bỏ frame này
    wsQueueDropped.fetch_add(1);
  }

  size_t n = samples > I2S_READ_SAMPLES ? I2S_READ_SAMPLES : samples;
  if (n > 0) memcpy(f->pcm, pcm, n * sizeof(int16_t));
  f->samples = (uint16_t)n;
  if (xQueueSend(wsQueue, &f, 0) != pdTRUE) {
    xQueueSend(wsFreeQueue, &f, 0);  // queue đầy đúng lúc chen ngang: trả frame về pool
    wsQueueDropped.fetch_add(1);
  }
  return true;
}

// Task sở hữu webSocket: bơm sự kiện lib + gửi hết frame đang chờ. Block bao lâu cũng không ảnh
// hưởng mic — loop() chính chỉ ghi vào queue.
static void wsSendTask(void *) {
  for (;;) {
    webSocket.loop();  // sự kiện + reconnect nội bộ lib (trước đây gọi trong loop() chính)

    WsFrame *f = nullptr;
    while (xQueueReceive(wsQueue, &f, 0) == pdTRUE) {
      if (webSocket.isConnected()) {
        uint32_t t0 = (uint32_t)esp_timer_get_time();
        if (f->samples == 0) {
          // Marker hết câu: khung TEXT. Backend coi MỌI khung text là tín hiệu cắt câu
          // (voice/stream.go), nội dung chỉ để đọc log cho người.
          webSocket.sendTXT("eou");
        } else {
          webSocket.sendBIN(reinterpret_cast<uint8_t *>(f->pcm), f->samples * sizeof(int16_t));
        }
        uint32_t us = (uint32_t)esp_timer_get_time() - t0;
        if (us > wsSendMaxUs.load()) wsSendMaxUs.store(us);
      }
      xQueueSend(wsFreeQueue, &f, portMAX_DELAY);  // pool có sẵn chỗ nên không thực sự chờ
    }
    vTaskDelay(pdMS_TO_TICKS(2));  // nhả CPU cho WiFi/LWIP cùng core 0
  }
}

// ---- Trạng thái presence (nhận từ MQTT home/room/presence) ----
// Ghi trong onMqtt (chạy đồng bộ trong mqtt.loop() ở loop()), đọc trong loop().
bool     radarPresent = false;
uint32_t lastRadarMs  = 0;   // millis() lần nhận presence cuối; 0 = chưa từng nhận
uint32_t lastRadarSeq = 0;

bool     present       = false;  // radar-node còn sống VÀ đang báo có người
bool     occupied      = false;  // kết luận chính sách AC (present ổn định đủ lâu)
uint32_t falseSinceMs  = 0;      // lúc present chuyển false (đếm EXIT_TIMEOUT)
uint32_t presenceSinceMs = 0;    // lúc present chuyển true (đếm ENTER_STABLE)

// ---- Hàng chờ IR: MỘT ô trạng thái duy nhất, gửi có nhịp trong loop() ----
// Một ô (không phải queue) là cố ý: khung IR Daikin mang TRỌN 35 byte trạng thái mỗi lần, nên chỉ
// trạng thái CUỐI có ý nghĩa. Ba lệnh dồn dập tự gộp thành một lần bắn — đúng ngữ nghĩa, không phải
// đánh đổi. Đồng thời đưa ac.send() (chặn ~150ms) ra khỏi callback MQTT: callback chạy đồng bộ
// trong mqtt.loop(), nên vài tin xếp hàng sau reconnect sẽ bắn liền nhau không khe hở.
bool     irPendingOn    = false;  // trạng thái mong muốn đang chờ gửi
float    irPendingTemp  = AC_DEFAULT_TEMP;  // nhiệt độ đi kèm ô chờ
bool     irHasPending   = false;  // có gì đang chờ hay không

// Nhiệt độ hệ đang đặt. Daikin gửi TRỌN 35 byte mỗi lần nên phải giữ giá trị này ở đây; không có
// cách nào hỏi ngược điều hoà xem nó đang ở bao nhiêu.
float    acTemp         = AC_DEFAULT_TEMP;
// Nguồn đang bật hay tắt theo ý hệ — cần để dựng lại khung đầy đủ khi chỉ đổi nhiệt độ.
bool     acPowerOn      = false;
bool     acStateDirty   = true;   // cần publish ac_state (true lúc boot để báo trạng thái đầu)
uint32_t lastIrSendMs   = 0;      // lần bắn IR cuối, để ép IR_MIN_GAP_MS
uint32_t lastManualMs   = 0;      // lần lệnh tay cuối (0 = chưa có), để fusion tôn trọng ý user

uint32_t lastHeartbeatMs = 0;

#ifdef ENABLE_WAKEWORD
// ---- Wakeword "Vừng ơi" (thay VAD năng lượng làm điều kiện mở stream, xem loop()) ----
WakewordFeatures wakewordFeatures;
WakewordModel    wakewordModel;
bool             wakewordReady   = false;  // false nếu begin() lỗi — loop() bỏ qua wakeword, KHÔNG
                                            // bao giờ tự mở stream (an toàn hơn là mở nhầm liên tục)
uint32_t         lastScoreLogMs  = 0;      // throttle log điểm số, cùng nhịp lastLogMs (500ms)

// Từ ROC thật đo kèm model (tflite_streaming_roc.txt, 10/08): ở ngưỡng 0.80, frr=17.65%
// (bỏ sót ~18% lần gọi), faph=0.75 (đạt mục tiêu <1 lần báo giả/giờ của plan). Đây là điểm khởi
// đầu tốt hơn placeholder 0.5 gốc trong plan Phase 3, nhưng VẪN LÀ SỐ ĐO OFFLINE (không phải đo
// tại vị trí lắp đặt thật) — Phase 4 phải tune lại từ số liệu thực địa, không coi đây là chốt cuối.
static const float WAKEWORD_THRESHOLD = 0.80f;

// Sau khi rời STREAMING (im lặng SILENCE_MS, xem loop()), score dư âm cuối câu vẫn có thể còn cao
// vài frame — nếu không có cooldown, LISTENING vừa quay lại đã trigger lại ngay, tách MỘT utterance
// thật thành nhiều TRIGGER giả. Đo thật 2026-08-11: 51 dòng TRIGGER cho ~31-32 lần nói "Vừng ơi"
// (script scripts/ghi-log-serial-wakeword.py, log tp-counted-0822.log) — log cho thấy rõ pattern
// STREAMING -> im lặng -> LISTENING -> TRIGGER mới chỉ vài trăm ms sau, score vẫn 0.99x liên tục.
static const uint32_t WAKEWORD_COOLDOWN_MS = 1200;
uint32_t wakewordCooldownUntilMs = 0;

// ---- Snore detection: scaffold kiến trúc B+ (CHƯA có model thật) ----
// Xem docs/voice-node-snore-wakeword-architecture.md mục 4.2 + plans/260812-1029-...-scaffold/.
// Buffer tích luỹ ~1s cùng cơ chế với preRoll ở trên, nhưng KHÔNG memmove trượt (snore không cần bù
// độ trễ trigger) — đầy thì cắt snapshot, reset, tích luỹ lại. Task riêng trên core khác chỉ tính
// "placeholder score" (RMS trung bình cửa sổ, dùng lại computeRms() có sẵn) — chỗ cắm model MFCC thật
// sau này chỉ cần thay nội dung snoreTask(), không đổi kiến trúc buffer/task xung quanh.
static const size_t SNORE_WINDOW_SAMPLES = 16000;  // ~1s @ 16kHz mono (SAMPLE_RATE)

// 2 buffer x 16000 x 2 byte = ~62.5KB — đáng kể so với SRAM (~512KB, đã chia sẻ WiFi stack + tensor
// arena wakeword), không đáng kể so với PSRAM (N16R8 có 8MB) -> đặt thẳng PSRAM, khỏi cần đo SRAM trước
// rồi mới quyết (xem Validation Log plan.md — PSRAM là lựa chọn rõ ràng, đo trước chỉ tổ mất 1 vòng
// build). Vẫn log free heap lúc boot để có số liệu thật, không suy đoán suông.
static int16_t *snoreAccumBuf    = nullptr;  // tích luỹ dần trong loop(), reset về đầu khi đầy
static int16_t *snoreSnapshotBuf = nullptr;  // snapshot cho snoreTask đọc — xem rào chắn notify dưới
static size_t   snoreAccumCount  = 0;

// Model thật (plans/260812-1401-...-snore-model-integration/) — thay placeholder computeRms() cũ,
// xem snoreTask(). SnoreFeatures/SnoreModel độc lập hoàn toàn với wakewordFeatures/wakewordModel
// (2 instance FrontendState/interpreter riêng, tham số khác nhau).
SnoreFeatures snoreFeatures;
SnoreModel    snoreModel;
bool          snoreModelReady = false;  // false nếu begin() lỗi — snoreTask() bỏ qua infer(), giữ
                                         // nguyên hành vi an toàn (không publish event nào cả) thay
                                         // vì publish confidence rác.

// Producer (loop(), core 1) chỉ ghi đè snoreSnapshotBuf SAU khi đã notify lần trước — xTaskNotifyGive/
// ulTaskNotifyTake làm hàng rào tuần tự, KHÔNG cần mutex vì đúng 1 producer + 1 consumer, không có ghi
// đồng thời từ 2 phía (xem Risk Assessment phase 1: nếu model thật sau này chạy chậm hơn 1s có thể mất
// dữ liệu — chấp nhận được với placeholder RMS tính rất nhanh).
TaskHandle_t snoreTaskHandle = nullptr;

// ---- Event Manager — debounce/hysteresis trước khi publish MQTT ----
// SNORE_SCORE_THRESHOLD thay SNORE_PLACEHOLDER_THRESHOLD (500.0f, đơn vị RMS — vô nghĩa với score
// model thật). SnoreModel::infer() dequantize output bằng scale/zero_point THẬT đọc từ tensor
// (snore_model.cpp), nên 0.5 là điểm giữa hợp lý cho phân loại nhị phân sigmoid/Logistic — khớp
// gần đúng ngưỡng 128/255≈0.502 mà recognize_commands.cc repo gốc dùng (họ so trực tiếp uint8 thô,
// ngầm định zero_point=0/scale=1/255). Số khởi điểm để test kiến trúc — tinh chỉnh khi test tay
// với âm thanh ngáy thật (xem plans/260812-1401-...-snore-model-integration/phase-02-*.md).
static const float    SNORE_SCORE_THRESHOLD       = 0.5f;
static const uint8_t  SNORE_CONSECUTIVE_WINDOWS   = 3;        // ~3s liên tục mới confirm — tránh 1
                                                               // tiếng động ngắn kích hoạt (temporal
                                                               // filtering, xem docs mục 6.3/13)
static const uint32_t SNORE_COOLDOWN_MS           = 5000;     // khác WAKEWORD_COOLDOWN_MS (1200) vì
                                                               // snore đặc trưng kéo dài hơn 1 utterance
uint8_t  snoreConsecutiveCount = 0;
uint32_t snoreCooldownUntilMs  = 0;

// Hàng rào giữa snoreTask (core 0, producer) và loop() (core 1, consumer/publisher) — KHÔNG gọi
// mqtt.publish() trực tiếp từ snoreTask: lib 256dpi/MQTT (.pio/libdeps/.../MQTT/src/MQTTClient.h)
// không có mutex/lock nào trong toàn bộ source, không tài liệu nào xác nhận thread-safe. mqtt.loop()
// đã chạy trong loop() chính (core 1) — publish cũng phải chạy ở ĐÚNG task đó, tránh race condition
// không định kỳ trên state nội bộ của lib. snoreTask chỉ ĐẶT CỜ, loop() đọc cờ rồi tự publish.
//
// std::atomic thay vì volatile: volatile chỉ chặn compiler cache/reorder truy cập BIẾN ĐÓ, không phải
// bảo đảm chính thức của C++ memory model qua 2 core — không phát sinh lệnh hàng rào bộ nhớ (memw trên
// Xtensa) để đảm bảo core 1 thấy đúng thứ tự ghi snoreEventConfidence RỒI MỚI thấy snoreEventPending.
// release/acquire ở đây đúng vai trò: producer release SAU khi ghi xong payload, consumer acquire
// TRƯỚC khi đọc payload — loại bỏ hẳn phụ thuộc vào hành vi pipeline cụ thể của Xtensa LX7 (in-order,
// chưa chắc giữ nguyên nếu code xung quanh đổi hoặc core khác dùng sau này).
std::atomic<bool>  snoreEventPending{false};
std::atomic<float> snoreEventConfidence{0.0f};
static const char *TOPIC_SNORE_EVENT = "home/room/snore_event";

// Chỉ MỘT interpreter TFLite được chạy tại một thời điểm, dù có 2 core.
//
// Kernel esp_nn giữ scratch buffer trong biến TOÀN CỤC của thư viện (esp_nn_set_conv_scratch_buf,
// gọi ngay trong Eval của conv/softmax). Wakeword ở core 1 và snore ở core 0 đều có CONV_2D, nên
// khi hai Invoke() chồng nhau, core này ghi đè con trỏ scratch của core kia rồi ghi kết quả
// convolution vào arena của nó — user_data / registration->invoke bị zero hoá, lần Invoke() kế
// tiếp chết bằng abort() trong TFLITE_DCHECK. Đo trên board 13/08: 5/5 lần crash rơi đúng cửa sổ
// hai inference chồng nhau (~1 lần/14 phút khi chạy liên tục).
//
// Vì sao khoá thay vì bỏ esp_nn: đã thử reference kernel cho mọi op và ĐO được snore 105ms ->
// 4000ms (chiếm đứt core 0, task_wdt kêu mỗi 5s). Khoá rẻ hơn nhiều: snore giữ mutex ~105ms mỗi
// giây, và I2S DMA (16 buffer x 256 mẫu = 256ms) thừa sức đệm audio trong lúc loop() chờ nên
// KHÔNG mất mẫu, chỉ trễ xử lý.
SemaphoreHandle_t tfliteMutex = nullptr;
#endif

IRDaikin152 ac(PIN_IR_SEND);   // 152-bit: NGẮN NHẤT trong các biến thể còn setPower thật
                               // (64/128 chỉ có setPowerToggle -> không diễn tả được bật/tắt).
                               // Ngắn hơn Daikin2 (312-bit) >2x -> bắn nhanh hơn, chặn CPU ít hơn,
                               // đỡ làm i2s_read lỡ nhịp khi đang stream mic.

// ---- WiFi: kết nối + tự thử lại, không treo loop khi mất mạng ----
// Bug thật tìm thấy 10/08 lúc đo true-positive wakeword: bản cũ dùng while(...) { delay(250); } chờ
// tới 15000ms MỖI LẦN gọi — trái ngay với comment ở trên nó. loop() gọi hàm này vô điều kiện mỗi vòng
// khi chưa connect (xem chỗ gọi bên dưới), nên khi WiFi không connect được, board bị đứng hình audio/
// wakeword ~15000/15035ms mỗi chu kỳ (đo bằng log thật, xem plan phase-04). Sửa thành state machine
// không-block: bắn WiFi.begin() 1 lần rồi return ngay, các lần gọi sau chỉ poll status(), không delay().
void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;

  static bool     connecting    = false;
  static uint32_t attemptStart  = 0;
  uint32_t now = millis();

  if (!connecting) {
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    Serial.printf("WiFi: nối tới %s...\n", WIFI_SSID);
    connecting   = true;
    attemptStart = now;
    return;  // KHÔNG block — loop() chạy tiếp audio/wakeword ngay, poll kết quả ở lần gọi sau
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("WiFi: OK");
    connecting = false;
  } else if (now - attemptStart >= 15000) {
    Serial.println("WiFi: FAIL (thử lại sau)");
    // PHẢI disconnect trước khi cho phép begin() lại. Hết 15000ms chỉ là timeout của TA —
    // driver esp_wifi vẫn đang ở trạng thái connecting và từ chối mọi lần set config kế tiếp:
    //   E wifi:sta is connecting, cannot set config
    //   STA clear config failed! 0x3006: ESP_ERR_WIFI_STATE
    // (log board thật khi AP không nằm trong tầm). Thiếu dòng này thì mọi lần retry sau đều
    // rơi vào lỗi trên và KHÔNG bắn được yêu cầu kết nối mới — board chỉ hồi phục khi reset.
    // Giữ nguyên cấu hình AP đã lưu (eraseap=false) và không tắt radio (wifioff=false) để lần
    // begin() kế tiếp không phải khởi tạo lại toàn bộ stack.
    WiFi.disconnect(false, false);
    connecting = false;  // hết timeout -> lần gọi loop() kế tiếp bắn lại WiFi.begin()
  }
  // else: vẫn trong cửa sổ chờ connect, không in gì, không delay — trả quyền điều khiển ngay cho loop()
}

// ---- MQTT: kết nối broker, tự thử lại (không chặn quá lâu để không nghẽn audio) ----
// Bug thật tìm thấy 10/08 lúc đo true-positive wakeword (cùng dạng bug với connectWiFi() ở trên, xem
// comment tại đó): for-loop 3 lần retry, mỗi lần `mqtt.connect()` TỰ nó gọi net.connect(host,port) —
// WiFiClient::connect() mặc định KHÔNG có timeout ngắn, nếu broker không tồn tại trên mạng hiện tại
// (đổi WiFi khác LAN backend) thì mỗi lần connect() có thể treo nhiều giây, nhân 3 lần trong for-loop
// == y hệt kiểu đứng hình ~15s/chu kỳ đã đo được ở connectWiFi(). Fix: giới hạn timeout socket qua
// net.setTimeout() (setup(), gần mqtt.begin()) + đổi thành 1 lần thử/lần gọi + cooldown, không for-loop
// blocking nữa.
void connectMQTT() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (mqtt.connected()) return;

  static uint32_t lastAttemptMs = 0;
  uint32_t now = millis();
  if (now - lastAttemptMs < 5000) return;  // cooldown giữa 2 lần thử, tránh spam connect() liên tục
  lastAttemptMs = now;

  Serial.print("MQTT: nối broker");
  bool ok = mqtt.connect(MQTT_CLIENT_ID, MQTT_USER, MQTT_PASS);
  Serial.println(ok ? " OK" : " FAIL (thử lại sau)");
  // Subscribe PHẢI nằm trong hàm connect: subscription mất khi rớt kết nối, đặt ở setup()
  // thì sau reconnect đầu tiên là điếc vĩnh viễn.
  if (mqtt.connected()) {
    mqtt.subscribe(TOPIC_AC_CMD, 1);
    mqtt.subscribe(TOPIC_PRESENCE, 1);   // presence từ radar-node -> chính sách AC
    Serial.printf("MQTT: sub %s + %s\n", TOPIC_AC_CMD, TOPIC_PRESENCE);
  }
}

// Nhận home/room/presence từ radar-node: {"ts":..,"present":true|false}. Chạy trong loop()
// (mqtt.loop gọi đồng bộ). Chỉ cần cờ present + mốc thời gian nhận (phát hiện link chết).
// Payload cố định nên dò chuỗi như ac_cmd, khỏi kéo JSON lib.
void onPresence(const String &payload) {
  radarPresent = payload.indexOf("\"present\":true") >= 0;
  lastRadarSeq++;
  lastRadarMs = millis();
}

// Bắn lệnh điều hoà Daikin.
// Daikin gửi TRỌN 35 byte trạng thái mỗi lần (kDaikinStateLength=35) — không có "lệnh bật"
// riêng. Nên bật thì phải set đủ nhiệt/chế độ/quạt, không chỉ power.
void sendAC(bool on, float temp) {
  ac.setPower(on);
  // Set nhiệt/chế độ/quạt KỂ CẢ khi tắt: lệnh nhiệt độ lúc máy đang tắt phải mang được giá trị mới
  // sang khung gửi đi, nếu chỉ set khi bật thì "tăng nhiệt độ" lúc tắt máy sẽ mất trắng.
  ac.setMode(AC_DEFAULT_MODE);
  ac.setTemp(temp);
  ac.setFan(AC_DEFAULT_FAN);
  ac.send();
  acPowerOn = on;
  acTemp    = temp;
  acStateDirty = true;
  Serial.printf("[ir] Daikin %s (%.0fC)\n", on ? "ON" : "OFF", temp);
}

// requestAC — điểm vào DUY NHẤT để đổi trạng thái điều hoà. Không bắn IR ngay: chỉ ghi vào ô chờ,
// loop() gửi có nhịp. manual=true cho lệnh người dùng (giọng nói / app), false cho fusion tự động.
void requestAC(bool on, bool manual) {
  if (manual) lastManualMs = millis();
  irPendingOn   = on;
  irPendingTemp = acTemp;   // giữ nguyên nhiệt độ đang đặt, chỉ đổi nguồn
  irHasPending  = true;
}

// docSteps — lấy "steps" trong payload {"cmd":"temp_up","steps":2}. Thiếu field thì trả 1: backend
// luôn gửi kèm, nhưng lệnh gõ tay bằng mosquitto_pub thường bỏ qua, và 1 bậc là mặc định vô hại.
// Kẹp trần để một payload hỏng không kéo nhiệt độ chạy hết dải trong một lệnh.
int docSteps(const String &payload) {
  int i = payload.indexOf("\"steps\"");
  if (i < 0) return 1;
  int colon = payload.indexOf(':', i);
  if (colon < 0) return 1;
  int n = payload.substring(colon + 1).toInt();
  if (n < 1) return 1;
  if (n > 14) return 14;   // đúng bằng độ rộng dải 16-30, hơn nữa là vô nghĩa
  return n;
}

// requestACTemp — đổi nhiệt độ đi bao nhiêu BẬC, giữ nguyên trạng thái nguồn.
//
// Phải đi qua ô chờ như lệnh bật/tắt chứ không bắn thẳng: flushIR đang ép khe hở IR_MIN_GAP_MS
// giữa hai lần bắn, bỏ qua nó thì hai lệnh nói liền nhau bắn dính và Daikin bỏ khung.
//
// Ô chờ mang theo CẢ nhiệt độ (irPendingTemp) chứ không chỉ irPendingOn. Thiếu điều đó thì một
// lệnh bật/tắt tới ngay sau sẽ ghi đè ô chờ và lệnh nhiệt độ biến mất — không lỗi, không log, chỉ
// là thỉnh thoảng không ăn.
void requestACTemp(int steps, bool manual) {
  if (manual) lastManualMs = millis();

  // Cộng dồn lên ô chờ nếu có lệnh nhiệt độ chưa kịp bắn, để "tăng 1 độ" nói hai lần liên tiếp ra
  // đúng 2 bậc thay vì 1.
  float base = irHasPending ? irPendingTemp : acTemp;
  float want = base + (float)steps;
  if (want < AC_TEMP_MIN) want = AC_TEMP_MIN;
  if (want > AC_TEMP_MAX) want = AC_TEMP_MAX;

  if (want == base) {
    Serial.printf("[ir] nhiệt độ đã chạm biên %.0fC, bỏ qua\n", base);
    return;
  }
  irPendingOn   = irHasPending ? irPendingOn : acPowerOn;  // không đụng nguồn
  irPendingTemp = want;
  irHasPending  = true;
}

// flushIR — bắn ô chờ khi đã đủ khe hở. Gọi từ loop().
void flushIR(uint32_t now) {
  if (!irHasPending) return;
  if (lastIrSendMs != 0 && now - lastIrSendMs < IR_MIN_GAP_MS) return;  // chưa đủ khe, chờ vòng sau
  irHasPending = false;
  lastIrSendMs = now;
  sendAC(irPendingOn, irPendingTemp);
}

// Lệnh tay từ app (/api/ac) và voice (whisper -> ParseVietCommand) đều tới qua topic này.
void onMqtt(String &topic, String &payload) {
  if (topic == TOPIC_AC_CMD) {
    // Dò chuỗi thay vì parse JSON, giống presence — payload cố định và nhỏ, khỏi kéo thêm lib.
    // Kiểm temp_up/temp_down TRƯỚC "on": chuỗi "temp_up" không chứa "\"on\"" nên thực ra không
    // đụng nhau, nhưng thứ tự này khiến ý định rõ ràng khi đọc lại.
    if (payload.indexOf("temp_up") >= 0) {
      requestACTemp(+docSteps(payload), true);
    } else if (payload.indexOf("temp_down") >= 0) {
      requestACTemp(-docSteps(payload), true);
    } else if (payload.indexOf("\"on\"") >= 0) {
      requestAC(true, true);    // lệnh tay: vào ô chờ, và khoá fusion khỏi ghi đè
    } else if (payload.indexOf("\"off\"") >= 0) {
      requestAC(false, true);
    } else {
      Serial.printf("[ir] ac_cmd không hiểu: %s\n", payload.c_str());
    }
    return;
  }
  if (topic == TOPIC_PRESENCE) {
    onPresence(payload);
  }
}

// ---- Init I2S RX: 16kHz, slot 32-bit, mono kênh trái (INMP441 L/R->GND) ----
void setupI2S() {
  i2s_config_t i2sConfig = {
      .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
      .sample_rate = SAMPLE_RATE,
      .bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT,  // INMP441 xuất 24-bit trong khung 32-bit
      .channel_format = CFG_I2S_CHAN,                // xem chú thích ở khối CFG_I2S_CHAN
      .communication_format = I2S_COMM_FORMAT_STAND_I2S,
      .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
      // 16 x 256 mẫu = 4096 mẫu = 256ms đệm @16kHz. Tăng từ 8 (128ms) vì loop() nay có thể phải
      // chờ tfliteMutex trong lúc snore inference giữ khoá (~105ms) — 128ms là quá sát, chỉ cần
      // một nhịp jitter là DMA tràn và mất mẫu audio giữa câu. 256ms cho biên gấp đôi.
      // Giá: 16 x 256 x 4 byte = 16KB DIRAM (slot 32-bit), lấy từ ~150KB heap còn trống.
      .dma_buf_count = 16,
      .dma_buf_len = 256,
      .use_apll = false,
      .tx_desc_auto_clear = false,
      .fixed_mclk = 0,
  };
  i2s_pin_config_t pinConfig = {
      .bck_io_num = PIN_I2S_SCK,
      .ws_io_num = PIN_I2S_WS,
      .data_out_num = I2S_PIN_NO_CHANGE,  // chỉ RX, không dùng chân data_out
      .data_in_num = PIN_I2S_SD,
  };

  esp_err_t err = i2s_driver_install(I2S_PORT, &i2sConfig, 0, nullptr);
  if (err != ESP_OK) {
    Serial.printf("I2S: cài driver lỗi (%d)\n", err);
    return;
  }
  err = i2s_set_pin(I2S_PORT, &pinConfig);
  if (err != ESP_OK) {
    Serial.printf("I2S: set pin lỗi (%d)\n", err);
    return;
  }
  i2s_zero_dma_buffer(I2S_PORT);

  // Pulldown chân SD, BẮT BUỘC sau i2s_set_pin (đặt trước sẽ bị ma trận I2S ghi đè). Không có nó,
  // chân SD hở hoặc đọc sai nửa khung (mic tri-state SD ở đó) sẽ hứng nhiễu/crosstalk và cho RMS
  // khác 0 bám theo giọng nói — trông y như đang chạy đúng, nhưng whisper không nghe ra chữ nào.
  // Có pulldown thì hai lỗi đó ra RMS = 0 và chẩn đoán được ngay. Dây dupont trong vỏ hộp tuột
  // cũng thành im lặng an toàn thay vì mở utterance cho nhiễu.
  gpio_set_pull_mode((gpio_num_t)PIN_I2S_SD, GPIO_PULLDOWN_ONLY);

  Serial.printf("I2S: sẵn sàng đọc INMP441 (16kHz, mono %s, slot 32-bit)\n",
                CFG_I2S_CHAN == I2S_CHANNEL_FMT_ONLY_LEFT ? "trái" : "phải");
}

// ---- Tính RMS trên buffer PCM16 để làm VAD năng lượng ----
float computeRms(const int16_t *buf, size_t n) {
  if (n == 0) return 0.0f;
  double sumSq = 0.0;
  for (size_t i = 0; i < n; i++) {
    sumSq += (double)buf[i] * (double)buf[i];
  }
  return (float)sqrt(sumSq / (double)n);
}

#ifdef ENABLE_WAKEWORD
// ---- Task snore (core 0) — model thật (plans/260812-1401-...-snore-model-integration/) ----
// Chờ notify từ loop() (core 1) mỗi khi snoreSnapshotBuf có 1 cửa sổ ~1s (16000 mẫu) mới, chạy
// SnoreFeatures::pushSamples() + SnoreModel::infer() thật (thay computeRms() placeholder cũ), log
// ra Serial để verify task chạy đúng core + đo latency thật + không ảnh hưởng nhịp wakeword.
void snoreTask(void *) {
  uint8_t features[SnoreFeatures::kFeatureSliceCount][SnoreFeatures::kNumChannels];
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

    if (!snoreModelReady) continue;  // begin() lỗi -> không infer, không publish (an toàn hơn là
                                      // publish confidence rác — cùng triết lý wakewordReady)

    if (!snoreFeatures.pushSamples(snoreSnapshotBuf, SNORE_WINDOW_SAMPLES, features)) {
      // Không đủ đúng 61 slice trong lần gọi này (lệch pha hop hiếm gặp, xem comment
      // SnoreFeatures::pushSamples) -> bỏ qua cửa sổ này, FrontendState giữ lịch sử hop nội bộ nên
      // cửa sổ kế tiếp sẽ bù đủ, không mất dữ liệu vĩnh viễn.
      continue;
    }

    // Thống kê đặc trưng ĐƯA VÀO model — phân biệt "model không nhận ra tiếng ngáy" với "đặc trưng
    // vào model đã sai từ đầu". Đo 2026-08-14: mic thu rõ tiếng ngáy phát từ loa (RMS nền 40 vọt lên
    // 894 theo đúng nhịp thở) mà score vẫn 0.000 — nếu min/max/mean ở đây dồn hết về ~0 thì lỗi nằm ở
    // frontend/rescale chứ không phải model, và đó là hai hướng sửa hoàn toàn khác nhau.
    uint32_t fSum = 0;
    uint8_t  fMin = 255, fMax = 0;
    for (int s = 0; s < SnoreFeatures::kFeatureSliceCount; s++) {
      for (int c = 0; c < SnoreFeatures::kNumChannels; c++) {
        uint8_t v = features[s][c];
        fSum += v;
        if (v < fMin) fMin = v;
        if (v > fMax) fMax = v;
      }
    }
    uint32_t fMean = fSum / (SnoreFeatures::kFeatureSliceCount * SnoreFeatures::kNumChannels);

    uint32_t inferStartMs = millis();
    xSemaphoreTake(tfliteMutex, portMAX_DELAY);  // xem tfliteMutex: esp_nn scratch dùng chung
    float score = snoreModel.infer(features);
    xSemaphoreGive(tfliteMutex);
    uint32_t inferMs = millis() - inferStartMs;
    Serial.printf("[snore][feat] min=%u max=%u mean=%u\n", (unsigned)fMin, (unsigned)fMax,
                  (unsigned)fMean);
    Serial.printf("[snore] score=%.3f infer=%lums core=%d\n", score, (unsigned long)inferMs,
                  xPortGetCoreID());

    // Event Manager (giữ nguyên 100% kiến trúc scaffold trước) — chỉ đổi biến đầu vào từ rms
    // placeholder sang score model thật: N cửa sổ liên tiếp vượt ngưỡng mới confirm (temporal
    // filtering), rồi cooldown trước khi confirm event kế tiếp — cùng nguyên tắc WAKEWORD_COOLDOWN_MS.
    uint32_t now = millis();
    if (score > SNORE_SCORE_THRESHOLD) {
      if (snoreConsecutiveCount < 255) snoreConsecutiveCount++;
    } else {
      snoreConsecutiveCount = 0;
    }

    if (snoreConsecutiveCount >= SNORE_CONSECUTIVE_WINDOWS && now >= snoreCooldownUntilMs) {
      // release: ghi confidence PHẢI thấy được trên core 1 TRƯỚC KHI core 1 thấy pending=true bên dưới.
      snoreEventConfidence.store(score, std::memory_order_relaxed);
      snoreEventPending.store(true, std::memory_order_release);
      snoreCooldownUntilMs = now + SNORE_COOLDOWN_MS;
      snoreConsecutiveCount = 0;
      Serial.printf("[snore] EVENT confidence=%.3f -> chờ loop() publish\n", score);
    }
  }
}
#endif

// ---- Log trạng thái WS (không gọi logic nghiệp vụ ở đây, chỉ debug) ----
void onWsEvent(WStype_t type, uint8_t *payload, size_t length) {
  switch (type) {
    case WStype_CONNECTED:
      Serial.println("WS: đã kết nối backend /api/voice/stream");
      break;
    case WStype_DISCONNECTED:
      Serial.println("WS: mất kết nối backend, tự thử lại theo reconnect interval");
      break;
    case WStype_ERROR:
      Serial.println("WS: lỗi kết nối");
      break;
    default:
      break;  // không quan tâm TEXT/PING/PONG — node chỉ gửi BIN
  }
}

// Nạp firmware qua WiFi — bỏ hẳn cảnh usbipd attach + port nhảy + (khi 2 board dùng
// chung nguồn) phải tháo dây 5V mỗi lần nạp. USB vẫn là đường lui: bản nào làm chết
// WiFi thì OTA bó tay.
//
// Bảng partition có sẵn otadata + app0/app1, không phải tự chế:
//   WROOM-32 (esp32dev)  default.csv        -> mỗi slot 1.25MB
//   ESP32-S3 (esp32s3)   default_16MB.csv   -> mỗi slot 6.5MB
void setupOTA() {
  ArduinoOTA.setHostname(OTA_HOSTNAME);
  ArduinoOTA.setPassword(OTA_PASSWORD);  // không để bất kỳ ai cùng LAN nạp firmware vào nhà

  // I2S và WebSocket phải nhả TRƯỚC khi ghi flash: i2s_read đang chạy sẽ tranh CPU với
  // tác vụ ghi, còn WS giữ socket mở dễ làm timeout giữa chừng -> bản nạp hỏng.
  ArduinoOTA.onStart([]() {
    Serial.println("\n[ota] bắt đầu — dừng I2S + WS");
    voiceState = VoiceState::LISTENING;
    // Dừng wsSendTask TRƯỚC khi chạm webSocket: lib không thread-safe, task đang có thể ở giữa một
    // sendBIN. Sau OTA board reboot nên không cần chạy lại task.
    if (wsSendTaskHandle) vTaskSuspend(wsSendTaskHandle);
    webSocket.disconnect();
    i2s_stop(I2S_PORT);
    i2s_driver_uninstall(I2S_PORT);
  });
  ArduinoOTA.onEnd([]() { Serial.println("\n[ota] xong — khởi động lại"); });
  ArduinoOTA.onProgress([](unsigned int cur, unsigned int total) {
    Serial.printf("[ota] %u%%\r", (cur * 100) / total);
  });
  ArduinoOTA.onError([](ota_error_t err) {
    // Nạp hỏng giữa chừng: bản cũ ở slot kia vẫn nguyên, board reboot về bản cũ.
    Serial.printf("\n[ota] LỖI %u — giữ nguyên firmware cũ, nạp lại qua USB nếu cần\n", err);
  });

  ArduinoOTA.begin();
  Serial.printf("[ota] sẵn sàng: %s @ %s\n", OTA_HOSTNAME, WiFi.localIP().toString().c_str());
}

void setup() {
  Serial.begin(115200);
  delay(500);
  // Lý do reset lần TRƯỚC: 1=POWERON 3=SW 4=PANIC 5=INT_WDT 6=TASK_WDT 9=BROWNOUT.
  // Giữ dòng này: brownout lặp lại là triệu chứng nguồn yếu, và nó chỉ lộ ra ở đây.
  // Trên WROOM-32 từng brownout ngay tại WiFi.mode() do inrush lúc calibrate radio —
  // hạ CPU/TX power KHÔNG cứu được, fix duy nhất là tụ 470-1000µF ở 5V-GND.
  Serial.printf("\n[boot] reset reason = %d\n", (int)esp_reset_reason());

  connectWiFi();
  setupOTA();     // sau connectWiFi (cần IP), trước I2S để lỡ I2S treo vẫn OTA cứu được
  ac.begin();     // IR Daikin (chân theo CFG_IR_PIN: WROOM=4, S3=8)
  setupI2S();

#ifdef VOICE_RECORD_MODE
  // Đường thu dữ liệu ghi WAV thẳng xuống đĩa, KHÁC đường ASR — nhãn trong query đi vào tên file
  // để lúc gán nhãn khỏi phải đoán đoạn nào là gì. Đổi nhãn bằng -DVOICE_RECORD_LABEL=...
  webSocket.begin(BACKEND_WS_HOST, BACKEND_WS_PORT, "/api/voice/record?label=" VOICE_RECORD_LABEL);
  Serial.println("[record] CHẾ ĐỘ THU DỮ LIỆU — stream liên tục, wakeword không dùng tới");
#else
  webSocket.begin(BACKEND_WS_HOST, BACKEND_WS_PORT, BACKEND_WS_PATH);
#endif
  webSocket.onEvent(onWsEvent);
  webSocket.setReconnectInterval(3000);  // tự thử lại mỗi 3s nếu rớt kết nối

  // Tách đường gửi WS sang task riêng (xem khai báo WsFrame): sendBIN block khi TCP nghẽn, để nó
  // trong loop() là nghẽn luôn mic. Cấp phát lỗi thì KHÔNG chặn boot — loop() quay về gửi đồng bộ
  // như bản cũ (còn bug tách câu, nhưng vẫn nghe được lệnh), và cũng không ai tranh webSocket vì
  // task không chạy.
  wsFramePool = (WsFrame *)heap_caps_malloc(WS_QUEUE_FRAMES * sizeof(WsFrame), MALLOC_CAP_SPIRAM);
  wsQueue     = xQueueCreate(WS_QUEUE_FRAMES, sizeof(WsFrame *));
  wsFreeQueue = xQueueCreate(WS_QUEUE_FRAMES, sizeof(WsFrame *));
  if (wsFramePool && wsQueue && wsFreeQueue) {
    for (size_t i = 0; i < WS_QUEUE_FRAMES; i++) {
      WsFrame *f = &wsFramePool[i];
      xQueueSend(wsFreeQueue, &f, 0);
    }
    // Core 0 (cùng WiFi/LWIP — nơi công việc mạng vốn thuộc về), priority 2 > loopTask (1): task này
    // gần như luôn ngủ trong tcp->write, ưu tiên cao chỉ để nó gửi ngay khi có frame, không phải
    // chờ hết một vòng loop mic.
    // Stack 6144: task chạy cả WebSockets loop (parse frame, gọi onWsEvent có Serial.printf — printf
    // ngốn stack) lẫn sendBIN. 4096 là sát quá cho đường có printf trong callback.
    xTaskCreatePinnedToCore(wsSendTask, "wsSend", 6144, nullptr, 2, &wsSendTaskHandle, 0);
    Serial.printf("[ws] send task tạo xong: queue=%u frame (~%ums audio), pool PSRAM %uKB\n",
                  (unsigned)WS_QUEUE_FRAMES,
                  (unsigned)(WS_QUEUE_FRAMES * I2S_READ_SAMPLES * 1000 / SAMPLE_RATE),
                  (unsigned)(WS_QUEUE_FRAMES * sizeof(WsFrame) / 1024));
  } else {
    if (wsFramePool) { heap_caps_free(wsFramePool); wsFramePool = nullptr; }
    if (wsQueue)     { vQueueDelete(wsQueue);     wsQueue = nullptr; }
    if (wsFreeQueue) { vQueueDelete(wsFreeQueue); wsFreeQueue = nullptr; }
    Serial.println("[ws] LỖI cấp phát queue gửi -> gửi đồng bộ trong loop() (còn bug tách câu)");
  }

  net.setTimeout(1000);  // giới hạn TCP connect() bên trong mqtt.connect() — xem comment connectMQTT()
  mqtt.begin(MQTT_HOST, MQTT_PORT, net);
  mqtt.onMessage(onMqtt);
  connectMQTT();

#ifdef ENABLE_WAKEWORD
  // Sau I2S (cần SAMPLE_RATE đã cấu hình) — lỗi ở đây chỉ tắt wakeword, KHÔNG chặn boot: board vẫn
  // lên WiFi/MQTT/OTA/fusion bình thường, chỉ không bao giờ tự mở stream (an toàn, không phải im
  // lặng-báo-lỗi: log rõ để thấy ngay lúc cắm Serial).
  // Tạo TRƯỚC mọi infer() — cả loop() lẫn snoreTask đều lấy khoá này trước khi Invoke().
  // Không có nó thì xSemaphoreTake(nullptr) là hành vi không xác định, nên dựng ngay đầu setup().
  tfliteMutex = xSemaphoreCreateMutex();
  if (!tfliteMutex) {
    // Hết heap ở đây gần như không xảy ra (mutex vài chục byte, cấp lúc heap còn ~150KB), nhưng
    // chạy tiếp mà thiếu khoá là quay lại đúng bug tranh scratch — thà tắt hẳn hai model.
    Serial.println("[tflite] LỖI tạo mutex -> wakeword+snore TẮT (không chạy khi thiếu khoá)");
  }

  bool featOk  = wakewordFeatures.begin(SAMPLE_RATE);
  bool modelOk = featOk && wakewordModel.begin();
  wakewordReady = tfliteMutex && featOk && modelOk;
  Serial.printf("[wakeword] init: features=%s model=%s -> %s\n", featOk ? "OK" : "LỖI",
               modelOk ? "OK" : "LỖI", wakewordReady ? "sẵn sàng" : "TẮT");

  // Model snore thật — cùng triết lý an toàn với wakewordReady ở trên: lỗi begin() chỉ tắt riêng
  // đường snore (snoreModelReady=false), KHÔNG chặn boot/wakeword/fusion.
  bool snoreFeatOk  = snoreFeatures.begin(SAMPLE_RATE);
  bool snoreModelOk = snoreFeatOk && snoreModel.begin();
  snoreModelReady = tfliteMutex && snoreFeatOk && snoreModelOk;
  Serial.printf("[snore] model init: features=%s model=%s -> %s\n", snoreFeatOk ? "OK" : "LỖI",
               snoreModelOk ? "OK" : "LỖI", snoreModelReady ? "sẵn sàng" : "TẮT");

  // Snore scaffold (xem khai báo buffer/task phía trên) — log heap TRƯỚC/SAU cấp phát PSRAM để có
  // số liệu thật (không suy đoán), lỗi cấp phát chỉ tắt snore task, KHÔNG chặn boot (cùng triết lý
  // với wakewordReady ở trên: an toàn hơn là tự bật nhầm mà không log rõ).
  Serial.printf("[snore] heap trước cấp phát: free=%u psram=%u\n",
                (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getFreePsram());
  snoreAccumBuf = (int16_t *)heap_caps_malloc(SNORE_WINDOW_SAMPLES * sizeof(int16_t), MALLOC_CAP_SPIRAM);
  snoreSnapshotBuf = (int16_t *)heap_caps_malloc(SNORE_WINDOW_SAMPLES * sizeof(int16_t), MALLOC_CAP_SPIRAM);
  Serial.printf("[snore] heap sau cấp phát: free=%u psram=%u\n",
                (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getFreePsram());

  if (snoreAccumBuf && snoreSnapshotBuf) {
    // Priority 1 = mặc định loopTask Arduino (tskIDLE_PRIORITY + 1) — snoreTask CÙNG priority nhưng
    // KHÁC core (0, xem Risk Assessment plan phase 1: WiFi/LWIP task cũng ở core 0, chấp nhận rủi ro
    // tranh chấp nhẹ, đã xác nhận qua Validation Session 1). Không hạ priority thêm vì không tranh
    // CPU với loopTask (khác core) — chỉ tranh với WiFi task nếu có, vốn chủ yếu interrupt-driven.
    //
    // Stack 8192 byte (tăng từ 4096 của placeholder RMS cũ, code-review 2026-08-12): từ khi thêm
    // model thật, task này còn giữ local `features[61][30]` (~1830 byte) + gọi Invoke() thật
    // (Conv2D/MaxPool2D/ResizeBilinear, arena 100KB) — nặng hơn hẳn RMS cũ. WakewordModel::infer()
    // (Invoke() nặng tương đương) chạy trong loopTask Arduino, mặc định 8192 byte — dùng cùng số đó
    // làm điểm khởi đầu có căn cứ thay vì đoán. CHƯA đo `uxTaskGetStackHighWaterMark()` thật trên
    // board (cần hardware, xem docs/voice-node-snore-wakeword-architecture.md mục 6a).
    xTaskCreatePinnedToCore(snoreTask, "snore", 8192, nullptr, 1, &snoreTaskHandle, 0);
    Serial.printf("[snore] task tạo xong, core loop()=%d\n", xPortGetCoreID());
  } else {
    Serial.println("[snore] LỖI cấp phát PSRAM -> snore task TẮT (wakeword không ảnh hưởng)");
  }
#endif
}

// Chính sách AC: presence (từ radar-node qua MQTT) ổn định đủ lâu -> bật; vắng đủ lâu -> tắt.
// Lọc tinh (cự ly/năng lượng, chống báo giả xuyên tường) đã nằm ở radar-node/cấu hình LD2410.
void updateFusion(uint32_t now) {
  // Link chết -> coi như KHÔNG có người. Không có timeout này, radar-node chết lúc đang
  // "có người" sẽ làm điều hoà chạy vĩnh viễn.
  uint32_t lastMs = lastRadarMs;
  bool radarAlive = lastMs != 0 && (now - lastMs) < RADAR_LINK_TIMEOUT_MS;
  bool p = radarAlive && radarPresent;

  if (p != present) {
    present = p;
    if (present) presenceSinceMs = now; else falseSinceMs = now;
  }

  bool before = occupied;
  // Vào: presence giữ LIÊN TỤC đủ lâu mới bật (chống báo giả thoáng qua).
  if (present && !occupied) {
    if (presenceSinceMs != 0 && now - presenceSinceMs >= ENTER_STABLE_MS) {
      occupied = true;
    }
  }
  // Ra: vắng đủ lâu.
  if (occupied && !present && falseSinceMs != 0) {
    if (now - falseSinceMs >= EXIT_TIMEOUT_MS) occupied = false;
  }

  if (occupied != before) {
    Serial.printf("[fusion] occupied -> %d\n", occupied);
    // Tôn trọng lệnh tay: người dùng vừa bảo tắt thì presence chớp một nhịp cũng không được bật lại.
    // Trạng thái occupied vẫn cập nhật (heartbeat/app đọc đúng), chỉ bỏ phần tự bắn IR.
    if (lastManualMs != 0 && now - lastManualMs < MANUAL_OVERRIDE_MS) {
      Serial.printf("[fusion] bỏ auto-send: có lệnh tay %lus trước\n",
                    (unsigned long)((now - lastManualMs) / 1000));
    } else {
      requestAC(occupied, false);
    }
  }
}

void loop() {
  uint32_t now = millis();

  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  ArduinoOTA.handle();  // rẻ khi rảnh (chỉ ngó gói UDP); chỉ chặn lúc đang nạp thật
  // webSocket.loop() chạy trong wsSendTask (lib không thread-safe: chỉ MỘT task được chạm
  // webSocket). Chỉ gọi ở đây khi task không tạo được — xem setup().
  if (!wsSendTaskHandle) webSocket.loop();

  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();  // keepalive MQTT (i2s_read timeout 200ms đảm bảo gọi đủ thường)

  // Báo ngược trạng thái điều hoà. Publish ở loop() chứ không trong sendAC(): sendAC có thể được
  // gọi từ nhánh fusion lẫn nhánh MQTT callback, còn ở đây thì chắc chắn cùng task với mqtt.loop().
  // retain=true để backend khởi động lại là biết ngay nhiệt độ đang đặt, khỏi chờ lệnh kế tiếp.
  if (acStateDirty && mqtt.connected()) {
    char payload[64];
    snprintf(payload, sizeof(payload), "{\"power\":%s,\"temp\":%d}",
             acPowerOn ? "true" : "false", (int)acTemp);
    if (mqtt.publish(TOPIC_AC_STATE, payload, true, 1)) {
      acStateDirty = false;
      Serial.printf("[ir] ac_state -> %s\n", payload);
    }
  }

#ifdef ENABLE_WAKEWORD
  // snoreTask (core 0) chỉ đặt cờ — publish LUÔN chạy ở đây (core 1, cùng task với mqtt.loop() ở trên)
  // vì lib 256dpi/MQTT không có mutex nội bộ nào (xem khai báo snoreEventPending phía trên).
  // acquire: nếu thấy pending=true, đảm bảo thấy đúng giá trị confidence mà core 0 đã ghi TRƯỚC đó.
  if (snoreEventPending.load(std::memory_order_acquire)) {
    snoreEventPending.store(false, std::memory_order_relaxed);  // xoá cờ TRƯỚC khi publish — event kế
                                 // tiếp từ snoreTask không bị mất dù publish() bên dưới có chặn một lúc.
    char payload[96];
    // ts = millis() (uptime), KHÔNG phải unix epoch — voice-node chưa có NTP sync. Khác "ts=0 chưa
    // sync" của các node khác (giá trị đó CÓ epoch thật khi sync xong); ở đây millis() luôn có ý nghĩa
    // tương đối (thứ tự/khoảng cách giữa các event), ts=0 cứng sẽ không phân biệt được event nào.
    snprintf(payload, sizeof(payload), "{\"ts\":%lu,\"confidence\":%.3f,\"duration_ms\":%u}",
             (unsigned long)millis(), snoreEventConfidence.load(std::memory_order_relaxed),
             (unsigned)SNORE_CONSECUTIVE_WINDOWS * 1000);
    bool ok = mqtt.publish(TOPIC_SNORE_EVENT, payload, false, 1);
    Serial.printf("[snore] publish %s -> %s\n", payload, ok ? "OK" : "LỖI");
  }
#endif

  updateFusion(now);
  flushIR(now);   // sau updateFusion: gộp được cả lệnh MQTT lẫn quyết định fusion trong cùng vòng

  if (STATUS_HEARTBEAT_MS && now - lastHeartbeatMs >= STATUS_HEARTBEAT_MS) {
    lastHeartbeatMs = now;
    uint32_t lastMs = lastRadarMs;
    Serial.printf("[hb] presence=%d link=%s present=%d occupied=%d seq=%lu wifi=%d mqtt=%d\n",
                  radarPresent ? 1 : 0,
                  (lastMs != 0 && now - lastMs < RADAR_LINK_TIMEOUT_MS) ? "up" : "DOWN",
                  present, occupied, (unsigned long)lastRadarSeq,
                  WiFi.status() == WL_CONNECTED, mqtt.connected());

#ifdef ENABLE_WAKEWORD
    // Đo thật thay suy đoán: latency Invoke() của wakeword arena (DIRAM, xem wakeword_model.cpp —
    // từng thử PSRAM 12/08, revert 13/08 do esp-nn DepthwiseConv2D ghi ngoài vùng cấp phát gây
    // crash-loop khi arena ở PSRAM), và stack high-water-mark thật của loopTask/snoreTask (trước đây
    // chỉ đặt theo suy luận, xem lịch sử comment ở khai báo snoreTask()). uxTaskGetStackHighWaterMark trả số ĐÃ
    // là byte trên port này — portSTACK_TYPE (Xtensa, freertos/portmacro.h) là uint8_t, KHÁC
    // FreeRTOS chuẩn (StackType_t=uint32_t, trả word) — không nhân 4 ở đây (bug từng mắc: nhân 4
    // làm số bị thổi phồng gấp 4 lần, phát hiện khi đối chiếu số đo thật với kích thước stack
    // khai báo 8192 byte thấy vô lý — free đo được lớn hơn cả tổng stack).
    WakewordLatencyStats wwStats = wakewordModel.getAndResetLatencyStats();
    uint32_t loopStackFreeBytes = uxTaskGetStackHighWaterMark(nullptr);
    uint32_t snoreStackFreeBytes =
        snoreTaskHandle ? uxTaskGetStackHighWaterMark(snoreTaskHandle) : 0;
    // wsSendTask khai báo 6144 byte theo suy luận (WebSockets loop + sendBIN + Serial.printf trong
    // onWsEvent) — đo cùng chỗ với hai task kia để biết con số thật thay vì tin phỏng đoán.
    uint32_t wsStackFreeBytes =
        wsSendTaskHandle ? uxTaskGetStackHighWaterMark(wsSendTaskHandle) : 0;
    Serial.printf("[hb][perf] wakewordInvokeUs min=%u avg=%u max=%u n=%u heapFree=%u psramFree=%u "
                 "loopStackFree=%u snoreStackFree=%u wsStackFree=%u\n",
                 (unsigned)wwStats.minUs, (unsigned)wwStats.avgUs, (unsigned)wwStats.maxUs,
                 (unsigned)wwStats.count, (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getFreePsram(),
                 (unsigned)loopStackFreeBytes, (unsigned)snoreStackFreeBytes,
                 (unsigned)wsStackFreeBytes);
#endif
  }

  // Đọc I2S có timeout — không dùng portMAX_DELAY để tránh treo loop nếu
  // mic/driver có vấn đề; timeout hết thì bỏ qua vòng này, thử lại vòng sau.
  size_t bytesRead = 0;
  esp_err_t err = i2s_read(I2S_PORT, i2sRawBuf, sizeof(i2sRawBuf), &bytesRead, pdMS_TO_TICKS(200));
  if (err != ESP_OK || bytesRead == 0) {
    // Timeout/0 byte: loop() không xử lý frame này nên không gửi — nếu đang STREAMING thì đó là
    // một khe hở trong chuỗi PCM tới backend. Đếm để đối chiếu với mảnh utterance backend tách ra.
    if (voiceState == VoiceState::STREAMING) streamI2STimeout++;
    return;
  }

  size_t samples = bytesRead / sizeof(int32_t);
  // INMP441 xuất dữ liệu MSB-aligned trong khung 32-bit -> lấy 16-bit cao
  // là cách đơn giản nhất để có PCM16 hợp lệ (tune lại nếu âm lượng sai lệch
  // thực địa — xem risk trong plan).
  for (size_t i = 0; i < samples; i++) {
    float x = (float)(i2sRawBuf[i] >> MIC_SHIFT);  // khuếch đại so với >>16 để whisper nghe rõ

    // Thông cao TRƯỚC clamp: mục đích là bỏ hạ tần để nó khỏi chiếm headroom, nên phải lọc lúc
    // giá trị còn ở dải rộng. Lọc sau clamp thì tiếng nói đã bị chặt mất rồi, không cứu lại được.
    float y = x - hpfPrevX + HPF_R * hpfPrevY;
    hpfPrevX = x;
    hpfPrevY = y;

    int32_t s = (int32_t)y;
    if (s > 32767) s = 32767;                // clamp chống tràn int16 khi tiếng to
    else if (s < -32768) s = -32768;
    pcmBuf[i] = (int16_t)s;
  }

  float rms = computeRms(pcmBuf, samples);
  if (noiseFloor <= 0.0f) noiseFloor = rms;  // seed, khỏi chờ EMA bò lên từ 0 mất mấy giây

  // Ngưỡng tính TRƯỚC khi cập nhật nền, để một frame to không tự nâng ngưỡng của chính nó.
  float vadThreshold = noiseFloor * VAD_NOISE_MULT;
  if (vadThreshold < VAD_THRESHOLD_MIN) vadThreshold = VAD_THRESHOLD_MIN;

  // lastVoiceMs dùng để cắt SILENCE_MS khi ĐANG STREAMING — cần trong CẢ HAI env dù mở stream
  // bằng wakeword hay VAD, vì kết thúc utterance luôn dựa vào "hết năng lượng tiếng nói".
  if (rms > vadThreshold) {
    lastVoiceMs = now;
  }

#if defined(ENABLE_WAKEWORD) && !defined(VOICE_RECORD_MODE)
  // KHÔNG chạy trong VOICE_RECORD_MODE: chế độ thu gửi mọi frame thẳng lên backend, không dùng
  // wakeword để làm gì cả. Mà inference đo được 6,3-12,9ms mỗi frame trong khi frame I2S về mỗi
  // 16ms — chiếm 40-80% ngân sách vòng lặp, cộng snore trên core 0 và WS gửi 32KB/s. Vượt ngân
  // sách thì I2S DMA tràn và mẫu rơi ÂM THẦM.
  //
  // Hậu quả đo được 17/08: mỗi file chứa đúng 60s audio nhưng hai lần lưu cách nhau 64-90s, tức
  // mất trung bình 15s (~20%) giữa mỗi đoạn, và tỉ lệ tăng dần theo thời gian chạy. Bộ mẫu snore
  // thu hôm đó có lỗ hổng rải rác mà không có dấu hiệu gì trong log.
  //
  // Trích đặc trưng + inference MỖI frame I2S (quyết định Validation Session 1 câu 3 trong plan —
  // chưa tối ưu sớm khi chưa có số đo CPU thật). Chạy VÔ ĐIỀU KIỆN kể cả khi đã STREAMING để state
  // nội bộ của frontend (noise/PCAN) và model không bị cold-start mỗi lần quay về LISTENING; điểm
  // số trong lúc STREAMING bị bỏ qua ở switch dưới (không đánh giá lại wakeword giữa một utterance).
  if (wakewordReady) {
    uint16_t wwFeatures[WakewordFeatures::kFramesPerInference][WakewordFeatures::kNumChannels];
    if (wakewordFeatures.pushSamples(pcmBuf, samples, wwFeatures)) {
      uint32_t inferStartMs = millis();
      xSemaphoreTake(tfliteMutex, portMAX_DELAY);  // xem tfliteMutex: esp_nn scratch dùng chung
      float score = wakewordModel.infer(wwFeatures);
      xSemaphoreGive(tfliteMutex);
      uint32_t inferMs = millis() - inferStartMs;
      if (now - lastScoreLogMs >= 500) {
        lastScoreLogMs = now;
        // infer=Xms: latency Invoke() thô đo bằng millis() (độ phân giải 1ms, đủ cho log runtime
        // định kỳ — số chính xác hơn dùng esp_timer_get_time() xem getAndResetLatencyStats()).
        Serial.printf("[wakeword] score=%.3f infer=%lums state=%s\n", score, (unsigned long)inferMs,
                      voiceState == VoiceState::LISTENING ? "LISTENING" : "STREAMING");
      }
      // Cho phép kích lại NGAY CẢ KHI đang STREAMING: người dùng nói "Vừng ơi" lần nữa giữa câu
      // (thường vì lệnh trước không ăn) thì phải bỏ câu cũ và bắt đầu câu mới. Không có nhánh này
      // thì board điếc suốt MIN_STREAM_MS + SILENCE_MS — đúng lúc người dùng đang bực và nói lại.
      //
      // Điều kiện chống dư âm khác nhau theo trạng thái:
      //  - LISTENING: cooldown như cũ (dư âm cuối câu trước).
      //  - STREAMING: đòi cách lúc bắt đầu stream ít nhất WAKEWORD_COOLDOWN_MS, để chính tiếng
      //    "Vừng ơi" vừa mở stream này không tự kích lại lần nữa.
      // GỠ nhánh kích-lại-khi-đang-STREAMING (thử 17/08, đo xong thì bỏ).
      //
      // Ý tưởng: nói "Vừng ơi" lần nữa giữa câu thì bỏ câu cũ, bắt đầu câu mới. Cài đặt xong đo
      // thật thì nó BĂM VỤN chính câu người dùng đang nói: điều kiện chống dư âm 1,2s kể từ lúc
      // bắt đầu stream quá ngắn so với câu lệnh dài 2-3s, nên từ giây 1,2 trở đi mọi điểm wakeword
      // cao giả đều cắt câu. Đo được ba utterance (1024ms, 512ms, 1232ms) trong đúng 3 giây, và
      // lệnh bật/tắt tụt từ 4/7 xuống 1/14.
      //
      // Nới điều kiện lên ~2,8s thì gần chạm MIN_STREAM_MS (3s), tính năng còn lại gần như vô
      // nghĩa. Mà giá trị thực tế của nó vốn mỏng: chỉ giúp khi muốn huỷ câu giữa chừng, tình
      // huống hiếm. Đánh đổi tồi, nên bỏ.
      //
      // Khung text "eou" giờ dùng cho việc KHÁC: báo hết câu ở cuối utterance (xem chỗ kết thúc
      // stream bên dưới), không phải ngắt câu giữa chừng. Nếu sau này có cách chống dư âm đáng tin
      // hơn (đòi điểm cao hơn hẳn ngưỡng, hoặc dùng chính model wakeword phân biệt tiếng vọng) thì
      // đường ngắt-giữa-chừng vẫn dựng lại được trên cùng khung tín hiệu đó.
      bool duDieuKienKich =
          (voiceState == VoiceState::LISTENING && now >= wakewordCooldownUntilMs);
      if (duDieuKienKich && score > WAKEWORD_THRESHOLD) {
        voiceState  = VoiceState::STREAMING;
        streamStartMs = now;
        lastVoiceMs = now;  // seed SILENCE_MS ngay lúc trigger, tránh cắt sớm nếu frame này RMS thấp
        // Bắt đầu stream mới: reset bộ đếm send-gap (tránh lẫn với stream cũ nếu kết thúc không chạy
        // nhánh reset — ví dụ đang chạy env VOICE_RECORD_MODE không reset ở chỗ kết thúc utterance).
        streamSendGapUsMax = 0;
        streamSendCount = 0;
        streamI2STimeout = 0;
        streamSendLastUs = 0;
        wsSendMaxUs.store(0);
        wsQueueDropped.store(0);
        Serial.printf("[wakeword] TRIGGER score=%.3f -> STREAMING\n", score);
        // Gửi bù phần đã giữ TRƯỚC frame hiện tại để chuỗi PCM liền mạch, không mất âm đầu.
        // Ring buffer nên frame cũ nhất KHÔNG nằm ở đầu mảng: đi ngược preRollCount frame từ chỗ
        // ghi tiếp theo. Nếu đoạn đó vắt qua cuối mảng thì gửi làm hai lần — backend nối byte thô
        // theo thứ tự nhận nên hai message liền nhau vẫn ra đúng một chuỗi PCM liên tục.
        //
        // Đẩy preRoll vào queue theo TỪNG frame (không một cục 16KB như trước): queue vốn giữ frame
        // rời, và 32 frame liên tiếp trong queue vẫn ra đúng một chuỗi PCM liền mạch ở backend.
        if (preRollCount > 0) {
          size_t oldest = (preRollWrite + PREROLL_FRAMES - preRollCount) % PREROLL_FRAMES;
          for (size_t i = 0; i < preRollCount; i++) {
            size_t idx = (oldest + i) % PREROLL_FRAMES;
            if (!wsQueuePush(&preRoll[idx * I2S_READ_SAMPLES], I2S_READ_SAMPLES) &&
                webSocket.isConnected()) {
              // Đường lui (không có queue): gửi đồng bộ như bản cũ.
              webSocket.sendBIN(reinterpret_cast<uint8_t *>(&preRoll[idx * I2S_READ_SAMPLES]),
                                I2S_READ_SAMPLES * sizeof(int16_t));
            }
          }
          streamSendCount += preRollCount;
        }
        // Mốc đo gap bắt đầu từ đây: khoảng cách preRoll -> frame STREAMING đầu tiên cũng phải nhỏ.
        streamSendLastUs = (uint32_t)esp_timer_get_time();
        preRollCount = 0;  // đã flush; bắt đầu tích luỹ lại từ đầu cho lần kế tiếp
      }
    }
  }

  // preRoll: ghi vòng liên tục trong lúc LISTENING, luôn giữ PREROLL_FRAMES khung gần nhất.
  // Flush lúc TRIGGER ở trên để bù độ trễ phát hiện của model streaming (xem khai báo preRoll).
  if (voiceState == VoiceState::LISTENING && samples == I2S_READ_SAMPLES) {
    memcpy(&preRoll[preRollWrite * I2S_READ_SAMPLES], pcmBuf, samples * sizeof(int16_t));
    preRollWrite = (preRollWrite + 1) % PREROLL_FRAMES;
    if (preRollCount < PREROLL_FRAMES) preRollCount++;
  }

  // Snore scaffold: tích luỹ liên tục (không quantize theo khung như preRoll ở trên — chỉ cộng dồn
  // thẳng, cửa sổ không cần liền mạch tuyệt đối vì placeholder RMS không nhạy với vài mẫu thiếu).
  // Chạy CẢ HAI trạng thái LISTENING/STREAMING (khác wakeword/preRoll chỉ chạy lúc LISTENING) — snore
  // không có khái niệm "utterance" để tạm dừng khi voice-node đang stream giọng nói qua wakeword.
  if (snoreAccumBuf && snoreSnapshotBuf) {
    size_t toCopy = samples;
    if (snoreAccumCount + toCopy > SNORE_WINDOW_SAMPLES) {
      toCopy = SNORE_WINDOW_SAMPLES - snoreAccumCount;  // cắt bớt phần dư, không quan trọng ở placeholder
    }
    memcpy(&snoreAccumBuf[snoreAccumCount], pcmBuf, toCopy * sizeof(int16_t));
    snoreAccumCount += toCopy;
    if (snoreAccumCount >= SNORE_WINDOW_SAMPLES) {
      memcpy(snoreSnapshotBuf, snoreAccumBuf, SNORE_WINDOW_SAMPLES * sizeof(int16_t));
      snoreAccumCount = 0;
      if (snoreTaskHandle) xTaskNotifyGive(snoreTaskHandle);
    }
  }
#else
  // Đường lui VAD năng lượng (env esp32dev/esp32s3, không có wakeword) — logic gốc, chỉ đổi tên
  // biến trạng thái streaming -> voiceState.
  if (voiceState == VoiceState::LISTENING) {
    if (rms > vadThreshold) {
      if (++onsetFrames >= VAD_ONSET_FRAMES) {
        voiceState  = VoiceState::STREAMING;
        streamStartMs = now;
        onsetFrames = 0;
        Serial.println("VAD: phát hiện tiếng nói -> bắt đầu stream");
        // Đường VAD chỉ cần bù đúng số frame bị debounce giữ lại, nên dùng preRollCount như bộ đếm
        // TUYẾN TÍNH từ đầu mảng (không quay vòng như đường wakeword) — mảng thừa sức chứa.
        for (size_t i = 0; i < preRollCount; i++) {
          if (!wsQueuePush(&preRoll[i * I2S_READ_SAMPLES], I2S_READ_SAMPLES) &&
              webSocket.isConnected()) {
            webSocket.sendBIN(reinterpret_cast<uint8_t *>(&preRoll[i * I2S_READ_SAMPLES]),
                              I2S_READ_SAMPLES * sizeof(int16_t));
          }
        }
        preRollCount = 0;
      }
    } else {
      // Chuỗi đứt -> gai nhiễu đơn lẻ, quên hẳn. Không tích lũy qua các lần rời rạc.
      onsetFrames  = 0;
      preRollCount = 0;
    }
  }

  // Đang chờ xác nhận onset: giữ frame lại. Chỉ giữ frame đủ độ dài để bước nhảy trong preRoll
  // luôn đúng I2S_READ_SAMPLES (i2s_read có thể trả về ít hơn khi timeout dở).
  if (voiceState == VoiceState::LISTENING && onsetFrames > 0 &&
      preRollCount < (size_t)(VAD_ONSET_FRAMES - 1) && samples == I2S_READ_SAMPLES) {
    memcpy(&preRoll[preRollCount * I2S_READ_SAMPLES], pcmBuf, samples * sizeof(int16_t));
    preRollCount++;
  }
#endif  // ENABLE_WAKEWORD

  // Học nền nhiễu CHỈ từ frame dưới ngưỡng và CHỈ khi đang LISTENING. Hai điều kiện đều cần: học
  // lúc STREAMING sẽ để tiếng nói kéo nền lên rồi tự tắt chính nó, còn học frame trên ngưỡng sẽ để
  // một tiếng động dài nâng nền lên và bỏ sót câu nói ngay sau đó. Vẫn giữ trong env wakeword dù
  // không còn dùng để trigger — vadThreshold vẫn quyết định lastVoiceMs (cắt SILENCE_MS) và log debug.
  if (voiceState == VoiceState::LISTENING && rms <= vadThreshold) {
    noiseFloor += NOISE_EMA_ALPHA * (rms - noiseFloor);
  }

#ifdef VOICE_RECORD_MODE
  // Chế độ THU DỮ LIỆU: gửi mọi frame, không qua wakeword, không cắt theo im lặng. Backend ghi
  // thẳng xuống WAV (/api/voice/record) để có bộ mẫu thu qua ĐÚNG mic và ĐÚNG vị trí thật —
  // model snore train trên dataset thu gần bị lệch miền, xem plans/reports/...snore...
  // Chỉ env esp32s3_record định nghĩa cờ này; đường chạy thật không bao giờ vào nhánh dưới.
  if (!wsQueuePush(pcmBuf, samples) && webSocket.isConnected()) {
    webSocket.sendBIN(reinterpret_cast<uint8_t *>(pcmBuf), samples * sizeof(int16_t));
  }
  if (now - lastRecordLogMs >= 5000) {
    lastRecordLogMs = now;
    Serial.printf("[record] đang thu, RMS=%.0f nen=%.0f ws=%s\n", rms, noiseFloor,
                  webSocket.isConnected() ? "up" : "down");
  }
#else
  if (voiceState == VoiceState::STREAMING) {
    // Đo khoảng cách giữa 2 lần ĐẨY frame: đây là tính liên tục của chuỗi PCM tới backend, và giờ
    // nó chỉ phụ thuộc nhịp i2s_read (~16ms), không còn phụ thuộc TCP (xem khai báo WsFrame).
    uint32_t pushUs = (uint32_t)esp_timer_get_time();
    if (streamSendLastUs != 0) {
      uint32_t gapUs = pushUs - streamSendLastUs;
      if (gapUs > streamSendGapUsMax) streamSendGapUsMax = gapUs;
    }
    streamSendLastUs = pushUs;
    streamSendCount++;

    if (!wsQueuePush(pcmBuf, samples) && webSocket.isConnected()) {
      webSocket.sendBIN(reinterpret_cast<uint8_t *>(pcmBuf), samples * sizeof(int16_t));
    }
    // Cửa sổ tối thiểu tính từ lúc VÀO STREAMING, không từ lastVoiceMs: lastVoiceMs có thể được
    // nhiễu nền đẩy lên bất chợt và làm cửa sổ trượt đi.
    bool duCuaSoToiThieu = (now - streamStartMs) >= MIN_STREAM_MS;
    if (duCuaSoToiThieu && now - lastVoiceMs > SILENCE_MS) {
      // Kết thúc utterance: NGỪNG gửi frame, KHÔNG đóng WS — giữ kết nối để
      // câu tiếp theo gửi ngay, không tốn thời gian bắt tay lại.
      voiceState = VoiceState::LISTENING;
      // Báo hết câu CHỦ ĐỘNG (marker samples=0 -> wsSendTask gửi khung text "eou").
      //
      // Vì sao cần: backend cắt câu khi KHÔNG nhận byte nào trong ASR_SILENCE_MS. Queue giữ mic
      // chạy khi TCP tắc, nhưng phía backend vẫn im đúng bằng thời gian tắc — đo 18/08 thấy một
      // lần sendBIN block 1,23s cắt đôi câu "BẬT ĐIỀU HÒA" (1504ms) + "Ừ" (1968ms) dù gapMaxMs chỉ
      // 240ms. Node mới là chỗ BIẾT câu đã hết, nên nói thẳng ra thay để backend đoán theo im lặng.
      // Marker đi qua ĐÚNG queue của audio nên luôn tới sau frame cuối, kể cả khi TCP đang tắc.
      if (!wsQueuePush(nullptr, 0) && webSocket.isConnected()) {
        webSocket.sendTXT("eou");
      }
#ifdef ENABLE_WAKEWORD
      // Cooldown tính từ lúc BẮT ĐẦU stream, không phải lúc kết thúc.
      //
      // Cooldown sinh ra để chặn dư âm cuối câu "Vừng ơi" trigger lại ngay khi vừa quay về
      // LISTENING (đo 11/08: 51 TRIGGER cho ~31 lần nói). Dư âm đó xảy ra vài trăm ms SAU trigger,
      // nên mốc đúng để đếm là lúc trigger, không phải lúc utterance kết thúc.
      //
      // Tính từ lúc kết thúc làm board điếc thêm 1,2s vô ích sau MỖI lệnh. Cộng với MIN_STREAM_MS
      // (3000) + SILENCE_MS (800) thì cửa sổ điếc lên ~4,6s — đo 17/08 thấy nói 6 câu cách nhau
      // 4,2s thì mất 3 câu, vì câu sau rơi đúng lúc board đang stream câu trước. Đổi mốc kéo cửa
      // sổ đó xuống ~3,8s.
      //
      // An toàn vì stream tối thiểu đã 3s, dài hơn cooldown 1,2s rất nhiều: lúc utterance kết thúc
      // thì cooldown chắc chắn đã hết hạn, và dư âm của "Vừng ơi" từ 3s trước cũng đã tắt từ lâu.
      wakewordCooldownUntilMs = streamStartMs + WAKEWORD_COOLDOWN_MS;
#endif
      // Tổng kết stream vừa xong (xem khai báo ở đầu file): gapMaxMs phải ≤ ~50ms sau fix; wsSendMax
      // vẫn có thể hàng giây khi TCP giật nhưng KHÔNG còn kéo gap theo; dropped>0 = block lâu hơn
      // dung lượng queue (~2s), lúc đó câu vẫn rỗng một khúc và cần tăng WS_QUEUE_FRAMES.
      if (streamSendCount > 0) {
        Serial.printf("[stream] end sends=%lu gapMaxMs=%lu wsSendMaxUs=%lu dropped=%lu "
                      "i2sTimeout=%lu\n",
                      (unsigned long)streamSendCount, (unsigned long)(streamSendGapUsMax / 1000),
                      (unsigned long)wsSendMaxUs.load(), (unsigned long)wsQueueDropped.load(),
                      (unsigned long)streamI2STimeout);
      }
      // Reset bộ đếm cho stream kế tiếp.
      streamSendGapUsMax = 0;
      streamSendCount = 0;
      streamI2STimeout = 0;
      streamSendLastUs = 0;
      wsSendMaxUs.store(0);
      wsQueueDropped.store(0);
      Serial.println("[stream] im lặng -> kết thúc utterance (ngừng gửi, giữ WS mở)");
    }
  }
#endif  // VOICE_RECORD_MODE

  // Log định kỳ (không phải mỗi vòng ~16ms) để debug RMS/streaming qua Serial.
  if (now - lastLogMs >= 500) {
    lastLogMs = now;
    // In cả ngưỡng động + nền: không có hai số này thì không cách nào biết VAD đang so với cái gì.
    Serial.printf("RMS=%.1f nen=%.0f nguong=%.0f state=%s ws=%s\n", rms, noiseFloor,
                  vadThreshold, voiceState == VoiceState::STREAMING ? "STREAMING" : "LISTENING",
                  webSocket.isConnected() ? "up" : "down");
  }
}
