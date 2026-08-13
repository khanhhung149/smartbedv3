// esp32cam-node — node thứ 6, thay cụm "Camera nhiệt / MLX90614" gốc của Phase 01.
// Quan sát hành vi lúc ngủ (OV2640) + khoảng cách người-camera (VL53L0X). Ghi cục bộ
// SD, KHÔNG stream WiFi cho luồng ghi chính thức. Quyết định đầy đủ + ranh giới riêng
// tư: plans/260813-0934-esp32cam-vl53l0x-camera-node/
//
// BENCH_TEST_MODE=1 (mặc định env esp32cam) bật toàn bộ đường WiFi/NTP + ghi SD dưới
// đây. Build production (env esp32cam_production_check, BENCH_TEST_MODE=0) KHÔNG
// link các hàm này vào — đúng 5 nguyên tắc riêng tư Phase 05
// (docs/safety/hazard-analysis.md H-25). Đừng gỡ #if này để "test cho tiện".

#include <cstring>
#include <ctime>

#include "esp_camera.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "nvs_flash.h"

#include "camera_config.h"
#include "vl53l0x.h"

#if BENCH_TEST_MODE
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "storage.h"
#include "config.h"  // "../include" đã có trong INCLUDE_DIRS (src/CMakeLists.txt)
#endif

namespace {
const char* TAG = "esp32cam-node";

constexpr int I2C_PORT_VL53L0X = 1;  // camera SCCB dùng I2C nội bộ riêng của esp32-camera
                                      // driver; VL53L0X đi qua port I2C thường (port 1)
                                      // trên CÙNG hai chân GPIO26/27. Nếu xung đột thật
                                      // (xem Risk Assessment phase-03), giảm tần suất
                                      // poll VL53L0X thay vì đổi bus.
constexpr int MAX_NIGHTS = 30;
constexpr int TARGET_FPS = 5;

#if BENCH_TEST_MODE
// Thật sự best-effort: KHÔNG dùng ESP_ERROR_CHECK ở đây — một lỗi driver WiFi/NVS
// thoáng qua không được phép reboot node giữa đêm ghi (mục tiêu Phase 4 là chạy ổn
// định 8 tiếng liên tục). Trả false nếu NTP không đồng bộ được; caller dùng
// esp_timer_get_time() làm epoch giả (trôi từ 1970, nhưng ít nhất đơn điệu tăng
// trong 1 lần chạy) thay vì crash.
bool sync_time_once_then_disable_wifi() {
    ESP_LOGI(TAG, "Bật WiFi CHỈ để NTP sync lúc boot (ranh giới đã chốt — không stream "
                  "trong lúc ghi chính thức)");

    esp_err_t err = esp_netif_init();
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "esp_netif_init lỗi (0x%x) — bỏ qua NTP, dùng epoch giả", err);
        return false;
    }
    esp_event_loop_create_default();  // ESP_ERR_INVALID_STATE nếu đã tạo — bỏ qua, không fatal
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t wifi_init_cfg = WIFI_INIT_CONFIG_DEFAULT();
    if (esp_wifi_init(&wifi_init_cfg) != ESP_OK) {
        ESP_LOGW(TAG, "esp_wifi_init lỗi — bỏ qua NTP, dùng epoch giả");
        return false;
    }

    wifi_config_t wifi_config = {};
    strncpy(reinterpret_cast<char*>(wifi_config.sta.ssid), WIFI_SSID,
             sizeof(wifi_config.sta.ssid) - 1);
    strncpy(reinterpret_cast<char*>(wifi_config.sta.password), WIFI_PASS,
             sizeof(wifi_config.sta.password) - 1);
    bool wifi_up = esp_wifi_set_mode(WIFI_MODE_STA) == ESP_OK &&
                   esp_wifi_set_config(WIFI_IF_STA, &wifi_config) == ESP_OK &&
                   esp_wifi_start() == ESP_OK;
    if (!wifi_up) {
        ESP_LOGW(TAG, "WiFi start lỗi — bỏ qua NTP, dùng epoch giả");
        return false;
    }
    esp_wifi_connect();

    // Chờ kết nối tối đa 10s — không chặn boot mãi nếu WiFi không tới, timestamp sẽ
    // trôi từ epoch build-time (chấp nhận được cho bench-test, xem Risk Assessment).
    bool connected = false;
    for (int i = 0; i < 100; ++i) {
        wifi_ap_record_t info;
        if (esp_wifi_sta_get_ap_info(&info) == ESP_OK) {
            connected = true;
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    bool synced = false;
    if (connected) {
        esp_sntp_config_t sntp_config = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
        esp_netif_sntp_init(&sntp_config);
        synced = esp_netif_sntp_sync_wait(pdMS_TO_TICKS(5000)) == ESP_OK;
        if (!synced) {
            ESP_LOGW(TAG, "SNTP sync timeout — dùng epoch giả");
        }
    } else {
        ESP_LOGW(TAG, "WiFi không kết nối được trong 10s — dùng epoch giả");
    }

    // Tắt WiFi hẳn — đúng ranh giới "chỉ NTP lúc boot, không stream lúc ghi".
    esp_wifi_stop();
    esp_wifi_deinit();
    ESP_LOGI(TAG, "Đã tắt WiFi, chuyển sang vòng ghi chính thức (time_synced=%d)", synced);
    return synced;
}
#endif  // BENCH_TEST_MODE
}  // namespace

extern "C" void app_main() {
    // Gotcha kinh điển ESP-IDF: lần đầu đổi partition table (hoặc NVS khác version)
    // trả ESP_ERR_NVS_NO_FREE_PAGES/NEW_VERSION_FOUND — phải erase rồi init lại,
    // không phải lỗi thật cần ESP_ERROR_CHECK abort.
    esp_err_t nvs_err = nvs_flash_init();
    if (nvs_err == ESP_ERR_NVS_NO_FREE_PAGES || nvs_err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        nvs_err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(nvs_err);

    camera_config_t cam_config = esp32cam_camera_config();
    esp_err_t err = esp_camera_init(&cam_config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Camera init thất bại (0x%x)", err);
        return;
    }

    err = vl53l0x_init(I2C_PORT_VL53L0X, CAM_PIN_SIOD, CAM_PIN_SIOC);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "VL53L0X init thất bại (0x%x) — tiếp tục chạy, khoảng cách sẽ là dropout",
                 err);
    }

#if BENCH_TEST_MODE
    bool time_synced = sync_time_once_then_disable_wifi();
    if (!time_synced) {
        ESP_LOGW(TAG, "Chạy KHÔNG có giờ thật — thư mục đêm sẽ nhóm theo epoch giả "
                      "(1970-01-01 + số giây từ boot), không phải ngày thật. Chấp nhận "
                      "được cho bench-test đơn lẻ, nhưng đừng suy ra ngày thật từ tên "
                      "thư mục nếu thấy dòng log này.");
    }

    if (storage_init() != ESP_OK) {
        ESP_LOGE(TAG, "SD init thất bại — dừng, không ghi được gì thì chạy vô nghĩa");
        return;
    }

    const int64_t frame_interval_ms = 1000 / TARGET_FPS;
    char night_dir[64] = {};

    while (true) {
        const int64_t loop_start_ms = esp_timer_get_time() / 1000;
        // epoch giây thật (đã đồng bộ NTP) nếu time_synced; nếu không, time(nullptr)
        // vẫn trả một giá trị đơn điệu tăng từ 1970 + uptime — đủ để KHÔNG bị timestamp
        // đứng yên như esp_timer_get_time() dùng sai trước đây (bug đã sửa).
        time_t epoch_s = time(nullptr);
        int64_t t_ms = static_cast<int64_t>(epoch_s) * 1000;

        storage_open_night(epoch_s, night_dir, sizeof(night_dir));

        camera_fb_t* fb = esp_camera_fb_get();
        int32_t distance_mm = vl53l0x_read_distance_mm();  // -1 nếu dropout — ghi nguyên,
                                                              // không bịa số (nguyên tắc dự án)
        if (fb) {
            storage_write_frame(night_dir, fb->buf, fb->len, distance_mm, t_ms);
            esp_camera_fb_return(fb);
        } else {
            ESP_LOGW(TAG, "Bỏ 1 frame — esp_camera_fb_get() trả NULL");
        }

        storage_rotate(MAX_NIGHTS);

        // Deadline-based delay: trừ đi thời gian đã tốn cho chụp+đo+ghi ở trên, thay vì
        // luôn ngủ đủ frame_interval_ms (bug cũ khiến fps thực < TARGET_FPS).
        const int64_t elapsed_ms = (esp_timer_get_time() / 1000) - loop_start_ms;
        const int64_t remaining_ms = frame_interval_ms - elapsed_ms;
        if (remaining_ms > 0) {
            vTaskDelay(pdMS_TO_TICKS(remaining_ms));
        } else {
            ESP_LOGW(TAG, "Vòng lặp chậm hơn target (%lld ms > %lld ms) — fps thực sẽ thấp "
                          "hơn TARGET_FPS, không ngủ thêm",
                     static_cast<long long>(elapsed_ms), static_cast<long long>(frame_interval_ms));
        }
    }
#else
    // Build production: KHÔNG WiFi, KHÔNG SD, KHÔNG vòng ghi. Camera+VL53L0X init xong
    // rồi dừng — không có code path nào ghi ảnh ra đĩa (verify ở Phase 4 Success Criteria).
    ESP_LOGI(TAG, "BENCH_TEST_MODE=0 — không có đường ghi SD/WiFi trong build này");
#endif
}
