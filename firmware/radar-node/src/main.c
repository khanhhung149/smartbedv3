// Radar node — Wemos S2 Mini (ESP32-S2) + radar LD2410C. ESP-IDF thuần.
//
// VAI TRÒ: đọc LD2410C ngay trên board (chân OUT + UART native), tự nối WiFi + MQTT,
// bắn dữ liệu presence lên broker theo HAI contract đã có trong hệ thống:
//
//   1) home/room/presence  {"ts":<epoch_ms>,"present":bool}   (retain, QoS1)
//        -> backend Go (internal/mqttclient) ăn topic này, chạy fusion + ghi lịch sử
//           rồi đẩy trạng thái vào app qua WebSocket /api/ws.
//
//   2) tele/<DEVICE_TOPIC>/SENSOR  (JSON khuôn tele/stat) + trả lời cmnd/<T>/STATUS 10
//        -> tab "Thiết bị" của app Flutter (MqttService) đọc THẲNG số liệu radar:
//           cự ly/năng lượng mục tiêu cử động & đứng yên.
//
// Wiring thật (xem docs/system-wiring.md):
//   LD2410 OUT -> GPIO16     LD2410 VCC -> 5V     LD2410 GND -> GND
//   LD2410 TX  -> GPIO33 (RX của S2)   LD2410 RX -> GPIO18 (TX của S2)
//   ⚠️ Nuôi radar bằng 5V và KHÔNG hàn module đè lên cổng USB-C (đã gây chập ở bản trước).
//
// Chân OUT cho 1 bit có/không người; UART cho thêm cự ly (cm) + năng lượng phản xạ của
// mục tiêu cử động/đứng yên. `present` lấy từ OUT HOẶC UART thấy mục tiêu, qua debounce
// chống nhiễu; UART hỏng thì vẫn chạy bằng OUT, chỉ mất phần số liệu chi tiết.

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mqtt_client.h"
#include "nvs.h"
#include "nvs_flash.h"

#include "config.h"
#include "ld2410.h"
#include "net.h"
#include "ota.h"

static const char *TAG = "radar";

// ---- Phần cứng ----
#define PIN_PRESENCE  GPIO_NUM_16   // LD2410 OUT (presence digital)
#define PIN_RADAR_RX  35            // LD2410 TX -> chân này (S2 nhận). Đổi từ GPIO33 sang GPIO35
                                    // (2026-08-25): GPIO33 hỏng vật lý (dây/module/code đều xác
                                    // nhận tốt qua đo thông mạch + test HLK-LD2410 BLE độc lập,
                                    // chỉ đổi chân là raw_bytes/2s từ 0 lên 460 ngay).
#define PIN_RADAR_TX  18            // LD2410 RX <- chân này (S2 gửi lệnh)
// 115200, KHÔNG PHẢI 256000 mặc định theo datasheet. Chẩn đoán thật 24/08 (uart_ok mãi false):
// (1) GND giữa LD2410 và S2 bị lỏng/đứt trước — raw_bytes/2s=0 tuyệt đối dù OUT pin/BLE app
//     vẫn báo bình thường (BLE không cần đường GND chung, UART thì cần — xem
//     docs/presence-ac/system-wiring.md Hazard #1). Nối lại GND: bắt đầu có byte, nhưng vẫn
//     0 khung hợp lệ.
// (2) Sau khi có byte, đo lại baud thật bằng app HLK-LD2410 (BLE, đọc trực tiếp từ module):
//     115200, không phải 256000. Đổi RADAR_BAUD khớp giá trị đo được → uart_ok=true,
//     moving_dist_cm/energy có số thật. Cả 2 lỗi cùng tồn tại độc lập, phải sửa cả hai.
#define RADAR_BAUD    115200
#define RADAR_UART    UART_NUM_1

// ---- MQTT topic ----
static const char *TOPIC_PRESENCE = "home/room/presence";  // contract backend Go
static const char *TOPIC_MOTION   = "home/door/motion";    // event cử động -> app Analytics
static const char *TOPIC_SAMPLE   = "home/room/sample";    // mẫu 10Hz Phase 01 -> backend samples

// Topic khuôn tele/stat dựng từ DEVICE_TOPIC lúc khởi động.
static char topic_tele_sensor[96];
static char topic_tele_lwt[96];
static char topic_stat_status10[96];
static char topic_cmnd_status[96];

// ---- Luật presence (nhịp/ngưỡng giữ nguyên từ bản đã nghiệm thu) ----
#define PRESENCE_HOLD_MS        300     // OUT phải HIGH liên tục ~0.3s mới báo có người
#define RADAR_DEBOUNCE_MS       30000   // giữ "còn người" tới 30s sau khi OUT rớt (chống mất khi ngồi yên)
#define POLL_MS                 100     // đọc chân OUT dày để bắt cả xung ngắn
#define PRESENCE_HEARTBEAT_MS   30000   // republish presence định kỳ (link còn sống + ghi đè retained cũ)
#define TELE_PERIOD_MS          3000    // nhịp đẩy tele/<T>/SENSOR cho app
#define MOTION_THROTTLE_MS      1000    // trần 1 event/s khi đang cử động (chống flood lịch sử)
#define LOOP_TICK_MS            20      // nhịp vòng chính; mọi việc bên trong đều tự canh mốc riêng

// ---- Trạng thái ----
static esp_mqtt_client_handle_t mqtt;
static volatile bool mqtt_connected;
static volatile bool need_hello;       // vừa nối lại: phải subscribe + báo Online
static volatile bool status10_request; // app vừa poll cmnd/<T>/STATUS 10

static uint32_t last_poll_ms;
static uint32_t last_tele_ms;
static uint32_t last_presence_pub_ms;
static uint32_t last_motion_pub_ms;
static uint32_t last_radar_high_ms;
static uint32_t radar_first_high_ms;
static bool     radar_ever_high;
static bool     present;
static bool     presence_published;  // đã publish presence lần nào chưa (ghi đè retained cũ sau khi có NTP)

static uint32_t millis(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

// Payload MQTT không kết thúc bằng NUL nên không dùng được strstr.
static bool payload_contains(const char *data, int len, const char *needle) {
  const int n = (int)strlen(needle);
  for (int i = 0; i + n <= len; i++) {
    if (memcmp(data + i, needle, n) == 0) return true;
  }
  return false;
}

// Ghép khối JSON LD2410 khuôn tele/stat vào buf.
static void build_ld2410_json(char *buf, size_t n, const ld2410_data_t *d) {
  snprintf(buf, n,
           "{\"LD2410\":{\"Detect\":%d,"
           "\"Moving\":{\"Distance\":%u,\"Energy\":%u},"
           "\"Static\":{\"Distance\":%u,\"Energy\":%u}}}",
           present ? 1 : 0,
           (unsigned)d->moving_dist_cm, (unsigned)d->moving_energy,
           (unsigned)d->still_dist_cm,  (unsigned)d->still_energy);
}

// tele/<T>/SENSOR — app đọc thẳng số liệu radar (tab "Thiết bị").
static void publish_sensor(const ld2410_data_t *d) {
  if (!mqtt_connected) return;
  char payload[192];
  build_ld2410_json(payload, sizeof(payload), d);
  esp_mqtt_client_publish(mqtt, topic_tele_sensor, payload, 0, 0 /*qos*/, 0 /*retain*/);
}

// stat/<T>/STATUS10 — trả lời poll STATUS 10 của app (bọc trong StatusSNS).
static void publish_status10(const ld2410_data_t *d) {
  if (!mqtt_connected) return;
  char inner[192];
  build_ld2410_json(inner, sizeof(inner), d);
  char payload[224];
  snprintf(payload, sizeof(payload), "{\"StatusSNS\":%s}", inner);
  esp_mqtt_client_publish(mqtt, topic_stat_status10, payload, 0, 0, 0);
}

// home/room/presence — contract backend Go. Retain để backend restart đọc lại được trạng thái
// hiện tại. Hoãn khi NTP chưa sẵn: đừng ghi ts=0 vào lịch sử vĩnh viễn.
static void publish_presence(void) {
  if (!mqtt_connected || !net_time_ready()) return;
  char payload[64];
  snprintf(payload, sizeof(payload), "{\"ts\":%" PRIu64 ",\"present\":%s}",
           net_epoch_ms(), present ? "true" : "false");
  const int id = esp_mqtt_client_publish(mqtt, TOPIC_PRESENCE, payload, 0, 1 /*qos*/, 1 /*retain*/);
  ESP_LOGI(TAG, "PUB %s %s -> %s", TOPIC_PRESENCE, payload, id >= 0 ? "ok" : "fail");
  if (id >= 0) {
    presence_published = true;
    last_presence_pub_ms = millis();
  }
}

// home/door/motion — event cử động cho backend lưu (Event.kindMotion) -> app Analytics.
static void publish_motion(void) {
  if (!mqtt_connected || !net_time_ready()) return;  // ts=0 làm bẩn lịch sử vĩnh viễn
  char payload[64];
  snprintf(payload, sizeof(payload), "{\"ts\":%" PRIu64 ",\"motion\":true}", net_epoch_ms());
  esp_mqtt_client_publish(mqtt, TOPIC_MOTION, payload, 0, 1 /*qos*/, 0 /*retain*/);
}

// ---- Mẫu 10Hz Phase 01 (schema CSV take-home) ----
//
// home/room/sample  {"t":<epoch_ms MCU>,"presence":bool,"hr_bpm":0,"resp_amplitude":0,
//   "motion":0|1,"weight_kg":0,"spo2":0,"temp_c":0,"humidity":0,
//   "moving_dist_cm":u,"moving_energy":u,"still_dist_cm":u,"still_energy":u,"uart_ok":bool,
//   "seq":u32,"boot":u32}
//
// - t gắn tại MCU (net_epoch_ms) — KHÔNG gắn ở Linux.
// - seq/boot cho phép truy NGUYÊN NHÂN mất mẫu, không chỉ tỷ lệ. Xem chú thích ở khai báo
//   sample_seq bên dưới.
// - Kênh radar không đo được (nhịp tim, hơi thở, cân nặng, SpO2, nhiệt độ, độ ẩm) ghi 0
//   kèm cờ uart_ok; KHÔNG bịa số. presence vẫn đáng tin từ chân OUT dù UART chết.
// - Ring buffer: mẫu bị nhốt khi MQTT chưa nối/bận được xếp hàng, đẩy lại khi thông
//   (chống mất mẫu — yêu cầu framework, không drop im lặng).
#define SAMPLE_TOPIC    TOPIC_SAMPLE
#define SAMPLE_TICK_MS  100        // 10Hz cố định, không jitter
#define SAMPLE_RB_CAP   64         // ~6.4s khi MQTT nghẽn; đầy thì drop cũ nhất (giữ mẫu mới)
// Payload xấu nhất (mọi trường ở giá trị dài nhất, energy là uint8 trần 100, dist là uint16):
//   224B  +  ,"seq":4294967295 (17B)  +  ,"boot":4294967295 (18B)  =  259B, cộng NUL là 260.
// Vượt 256 thì snprintf cắt cụt IM LẶNG -> JSON hỏng -> backend drop mẫu, và triệu chứng là
// "mất mẫu ngẫu nhiên khi giá trị radar lớn" — đúng loại lỗi bộ đếm này sinh ra để diệt.
#define SAMPLE_RB_LEN   288

typedef struct {
  char  buf[SAMPLE_RB_CAP][SAMPLE_RB_LEN];
  int   head;   // chỗ ghi kế tiếp
  int   count;
} sample_rb_t;

static sample_rb_t sample_rb;
static uint32_t last_sample_ms;

// seq tăng 1 mỗi mẫu ĐƯỢC DỰNG; boot tăng 1 mỗi lần khởi động (lưu NVS).
// Chỉ có seq là không đủ: MCU reset làm seq quay về 0 và sinh số trùng, không phân biệt
// được reset với mất mẫu. Có cả hai thì ba nguyên nhân tách bạch hẳn:
//   seq thủng lỗ + t liền mạch  -> mất trên đường (WiFi/MQTT/broker)
//   seq liền     + t nhảy quãng -> MCU trượt nhịp (vòng lặp, UART radar)
//   boot tăng                   -> MCU reset (nguồn, brownout, watchdog)
static uint32_t sample_seq;
static uint32_t boot_count;

// boot_count_bump đọc bộ đếm khởi động từ NVS, tăng 1, ghi lại. Gọi ĐÚNG MỘT LẦN lúc boot —
// ghi trong vòng lặp sẽ mòn flash. Khoá chưa tồn tại thì bắt đầu từ 0.
static uint32_t boot_count_bump(void) {
  nvs_handle_t h;
  if (nvs_open("radar", NVS_READWRITE, &h) != ESP_OK) {
    ESP_LOGW(TAG, "NVS mở lỗi — boot_count không đếm được, sẽ luôn báo 0");
    return 0;
  }
  uint32_t n = 0;
  nvs_get_u32(h, "boot_count", &n);  // không tìm thấy -> n giữ 0
  n++;
  if (nvs_set_u32(h, "boot_count", n) != ESP_OK || nvs_commit(h) != ESP_OK) {
    ESP_LOGW(TAG, "NVS ghi boot_count lỗi — lần khởi động sau sẽ lặp lại số %" PRIu32, n);
  }
  nvs_close(h);
  return n;
}

static bool sample_rb_full(const sample_rb_t *rb) { return rb->count == SAMPLE_RB_CAP; }

static void sample_rb_push(sample_rb_t *rb, const char *payload) {
  if (sample_rb_full(rb)) {
    // đầy: bỏ cũ nhất (head đang trỏ vào ô cũ nhất khi đầy) rồi ghi đè -> luôn giữ mẫu mới nhất
    rb->head = (rb->head + 1) % SAMPLE_RB_CAP;
    rb->count--;
  }
  const int idx = (rb->head + rb->count) % SAMPLE_RB_CAP;
  strncpy(rb->buf[idx], payload, SAMPLE_RB_LEN - 1);
  rb->buf[idx][SAMPLE_RB_LEN - 1] = '\0';
  rb->count++;
}

static bool sample_rb_pop(sample_rb_t *rb, char *out, size_t n) {
  if (rb->count == 0) return false;
  strncpy(out, rb->buf[rb->head], n - 1);
  out[n - 1] = '\0';
  rb->head = (rb->head + 1) % SAMPLE_RB_CAP;
  rb->count--;
  return true;
}

static void build_sample_json(char *buf, size_t n, const ld2410_data_t *d) {
  // motion: 1 khi radar thấy mục tiêu CỬ ĐỘNG (kênh CSV); presence từ bộ lọc present.
  snprintf(buf, n,
           "{\"t\":%" PRIu64
           ",\"presence\":%s"
           ",\"hr_bpm\":0,\"resp_amplitude\":0"
           ",\"motion\":%d"
           ",\"weight_kg\":0,\"spo2\":0,\"temp_c\":0,\"humidity\":0"
           ",\"moving_dist_cm\":%u,\"moving_energy\":%u"
           ",\"still_dist_cm\":%u,\"still_energy\":%u"
           ",\"uart_ok\":%s"
           ",\"seq\":%" PRIu32 ",\"boot\":%" PRIu32 "}",
           net_epoch_ms(),
           present ? "true" : "false",
           d->moving ? 1 : 0,
           (unsigned)d->moving_dist_cm, (unsigned)d->moving_energy,
           (unsigned)d->still_dist_cm, (unsigned)d->still_energy,
           d->uart_ok ? "true" : "false",
           sample_seq++, boot_count);
}

// Đẩy 1 mẫu: nối được thì publish, chưa nối thì xếp hàng (ring buffer).
// Chưa có NTP thì bỏ qua (t=0 làm bẩn dữ liệu vĩnh viễn — chờ đồng hồ xong hãy bắt đầu).
static void publish_sample(const ld2410_data_t *d) {
  if (!net_time_ready()) return;
  char payload[SAMPLE_RB_LEN];
  build_sample_json(payload, sizeof(payload), d);
  if (mqtt_connected) {
    // QoS0 để không chặn vòng chính khi broker bận; mẫu 10Hz là dữ liệu xu hướng, mất 1-2
    // mẫu là chấp nhận được — nhưng KHÔNG im lặng drop: mất vì QoS0 là đặc tính, mất vì nghẽn
    // hàng đợi là do ring buffer xử lý (mẫu được giữ rồi đẩy bù khi thông).
    esp_mqtt_client_publish(mqtt, SAMPLE_TOPIC, payload, 0, 0 /*qos*/, 0 /*retain*/);
  } else {
    sample_rb_push(&sample_rb, payload);
  }
}

// Vòng chính gọi mỗi tick: rút mẫu tồn đọng ra publish khi MQTT đã thông.
static void sample_drain(void) {
  if (!mqtt_connected) return;
  char payload[SAMPLE_RB_LEN];
  while (sample_rb_pop(&sample_rb, payload, sizeof(payload))) {
    if (!mqtt_connected) {  // rớt giữa chừng: bỏ lại hàng đợi cho lần sau
      sample_rb_push(&sample_rb, payload);
      return;
    }
    esp_mqtt_client_publish(mqtt, SAMPLE_TOPIC, payload, 0, 0, 0);
  }
}

// Gộp OUT + UART -> present, qua hold/debounce.
static void update_presence(uint32_t now, const ld2410_data_t *d) {
  const bool raw = gpio_get_level(PIN_PRESENCE) == 1 || (d->uart_ok && (d->moving || d->still));

  // Mục tiêu CỬ ĐỘNG (UART) -> bắn event motion cho Analytics, throttle 1/s. Chỉ dùng d->moving
  // (không dùng d->still) vì "chuyển động" khác "có người đứng yên".
  if (d->moving && net_time_ready() && now - last_motion_pub_ms >= MOTION_THROTTLE_MS) {
    last_motion_pub_ms = now;
    publish_motion();
  }

  if (raw) {
    last_radar_high_ms = now;
    radar_ever_high = true;
    if (radar_first_high_ms == 0) radar_first_high_ms = now;
  } else {
    radar_first_high_ms = 0;
  }

  const bool before = present;
  if (!present) {
    // Vào: radar giữ tín hiệu liên tục đủ lâu (chống nhiễu bật/tắt).
    if (raw && radar_first_high_ms != 0 && now - radar_first_high_ms >= PRESENCE_HOLD_MS) {
      present = true;
    }
  } else {
    // Ra: radar im đủ lâu. Debounce vì LD2410 rớt chớp nhoáng khi người ngồi yên.
    const bool recent = raw || (radar_ever_high && now - last_radar_high_ms < RADAR_DEBOUNCE_MS);
    if (!recent) present = false;
  }

  if (present != before) {
    ESP_LOGI(TAG, "present -> %d", present);
    publish_presence();
    publish_sensor(d);  // đẩy số liệu tươi kèm luôn cho app
  }
}

// Handler chạy trên task của esp-mqtt: CHỈ dựng cờ, mọi publish/subscribe để vòng chính làm.
// esp-mqtt cấm gọi publish/subscribe QoS>0 từ trong handler (chờ ack ngay trong task đang xử lý
// ack = tự khoá mình).
static void on_mqtt_event(void *arg, esp_event_base_t base, int32_t id, void *data) {
  const esp_mqtt_event_handle_t e = (esp_mqtt_event_handle_t)data;
  switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED:
      ESP_LOGI(TAG, "MQTT: nối broker OK");
      mqtt_connected = true;
      need_hello = true;
      break;
    case MQTT_EVENT_DISCONNECTED:
      ESP_LOGW(TAG, "MQTT: mất kết nối — client tự nối lại");
      mqtt_connected = false;
      break;
    case MQTT_EVENT_DATA:
      // App poll cmnd/<T>/STATUS payload "10" mỗi 2s.
      if ((size_t)e->topic_len == strlen(topic_cmnd_status) &&
          strncmp(e->topic, topic_cmnd_status, e->topic_len) == 0 &&
          payload_contains(e->data, e->data_len, "10")) {
        status10_request = true;
      }
      break;
    default:
      break;
  }
}

static void mqtt_start(void) {
  const esp_mqtt_client_config_t cfg = {
      .broker.address.hostname  = MQTT_HOST,
      .broker.address.port      = MQTT_PORT,
      .broker.address.transport = MQTT_TRANSPORT_OVER_TCP,
      .credentials.username                = MQTT_USER,
      .credentials.client_id               = MQTT_CLIENT_ID,
      .credentials.authentication.password = MQTT_PASS,
      // Will = home/room/presence {"present":false} (retain, QoS1). MQTT chỉ cho 1 will/kết nối:
      // ưu tiên presence thay vì tele/LWT vì presence là cái backend+app dựa vào để biết "có
      // người". Khi board rớt TCP (mất điện/mất WiFi) broker tự bắn present:false -> Home thôi
      // "thấy người" ngay, không giữ present:true retained vĩnh viễn. Payload cố định (không có
      // ts động vì will đặt lúc connect); backend coi ts=0 là hợp lệ cho trạng thái vắng.
      .session.last_will.topic  = TOPIC_PRESENCE,
      .session.last_will.msg    = "{\"present\":false}",
      .session.last_will.qos    = 1,
      .session.last_will.retain = 1,
      // Keepalive ngắn là ĐIỀU KIỆN để cái will ở trên có tác dụng thật: broker chỉ bắn will sau
      // 1.5 x keepalive im lặng. Mặc định của esp-mqtt là 120s -> mất điện board thì phải 3 phút
      // app mới thôi "thấy người", trong khi bản Arduino cũ (mặc định 10s) chỉ mất ~15s. 15s giữ
      // đúng độ nhạy đó; phí tổn là một gói PINGREQ mỗi 15s trong LAN.
      .session.keepalive = 15,
  };
  mqtt = esp_mqtt_client_init(&cfg);
  ESP_ERROR_CHECK(esp_mqtt_client_register_event(mqtt, ESP_EVENT_ANY_ID, on_mqtt_event, NULL));
  ESP_ERROR_CHECK(esp_mqtt_client_start(mqtt));
}

void app_main(void) {
  esp_err_t err = nvs_flash_init();  // WiFi cần NVS để lưu hiệu chỉnh RF
  if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());
    ESP_ERROR_CHECK(nvs_flash_init());
  }

  boot_count = boot_count_bump();

  // S2 dùng USB CDC gốc: chờ host mở cổng một nhịp để không mất log boot.
  vTaskDelay(pdMS_TO_TICKS(500));
  ESP_LOGI(TAG, "[boot] radar-node (S2 Mini + LD2410C) start, boot_count=%" PRIu32, boot_count);

  // Pulldown: radar hở/chết thì chân OUT thả nổi nhặt nhiễu -> với ngưỡng nhạy 300ms dễ đẻ
  // presence GIẢ. Pulldown ghì về 0 khi radar không driving; OUT là push-pull nên khi phát hiện
  // thật vẫn kéo HIGH thắng.
  const gpio_config_t out_pin = {
      .pin_bit_mask = 1ULL << PIN_PRESENCE,
      .mode         = GPIO_MODE_INPUT,
      .pull_down_en = GPIO_PULLDOWN_ENABLE,
      .pull_up_en   = GPIO_PULLUP_DISABLE,
      .intr_type    = GPIO_INTR_DISABLE,
  };
  ESP_ERROR_CHECK(gpio_config(&out_pin));

  ESP_ERROR_CHECK(ld2410_start(RADAR_UART, PIN_RADAR_RX, PIN_RADAR_TX, RADAR_BAUD));

  snprintf(topic_tele_sensor,   sizeof(topic_tele_sensor),   "tele/%s/SENSOR",    DEVICE_TOPIC);
  snprintf(topic_tele_lwt,      sizeof(topic_tele_lwt),      "tele/%s/LWT",       DEVICE_TOPIC);
  snprintf(topic_stat_status10, sizeof(topic_stat_status10), "stat/%s/STATUS10",  DEVICE_TOPIC);
  snprintf(topic_cmnd_status,   sizeof(topic_cmnd_status),   "cmnd/%s/STATUS",    DEVICE_TOPIC);

#ifdef WIFI_STATIC_IP
  const net_static_ip_t static_ip = {WIFI_STATIC_IP, WIFI_STATIC_GW, WIFI_STATIC_MASK};
  ESP_ERROR_CHECK(net_start(WIFI_SSID, WIFI_PASS, OTA_HOSTNAME, &static_ip));
#else
  ESP_ERROR_CHECK(net_start(WIFI_SSID, WIFI_PASS, OTA_HOSTNAME, NULL));
#endif
  ESP_ERROR_CHECK(ota_http_start(OTA_PASSWORD));
  mqtt_start();

  while (true) {
    const uint32_t now = millis();
    ld2410_data_t  d;
    ld2410_snapshot(&d);

    // Vừa nối (lại) broker: báo Online + đăng ký nhận poll STATUS. Subscription mất khi rớt kết
    // nối nên phải đăng ký lại mỗi lần.
    if (mqtt_connected && need_hello) {
      need_hello = false;
      esp_mqtt_client_publish(mqtt, topic_tele_lwt, "Online", 0, 1, 1 /*retain*/);
      esp_mqtt_client_subscribe(mqtt, topic_cmnd_status, 1);
      presence_published = false;  // ép publish lại presence hiện tại sau reconnect
      sample_drain();              // đẩy nốt mẫu tồn đọng khi broker nghẽn
    }

    if (status10_request) {
      status10_request = false;
      publish_status10(&d);
    }

    if (now - last_poll_ms >= POLL_MS) {
      last_poll_ms = now;
      update_presence(now, &d);
    }

    // Republish presence đúng lần đầu sau khi NTP sẵn sàng (ghi đè retained cũ), và định kỳ để
    // backend biết link còn sống.
    if (mqtt_connected && net_time_ready() &&
        (!presence_published || now - last_presence_pub_ms >= PRESENCE_HEARTBEAT_MS)) {
      publish_presence();
    }

    // Nhịp SENSOR cho app — có số liệu tươi dù không đổi present.
    if (now - last_tele_ms >= TELE_PERIOD_MS) {
      last_tele_ms = now;
      publish_sensor(&d);
    }

    // Mẫu 10Hz Phase 01: tick cố định theo millis (không đếm tick) để không lệch nhịp.
    if (now - last_sample_ms >= SAMPLE_TICK_MS) {
      last_sample_ms = now;
      publish_sample(&d);
      sample_drain();
    }

    vTaskDelay(pdMS_TO_TICKS(LOOP_TICK_MS));
  }
}
