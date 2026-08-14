// esp32cam-stream — khởi động camera, nối WiFi, phục vụ MJPEG stream. Hết.
//
// Không SD, không I2C, không NTP. Node này tồn tại để laptop chạy MediaPipe Pose
// nhìn thấy hình trực tiếp thay vì phải rút thẻ nhớ ra xem.
// Quyết định đầy đủ: plans/260814-1237-esp32cam-stream-mediapipe-poc/
//
// Chỉ dùng giai đoạn bench-test, không bao giờ chạy khi có người thật nằm trên giường
// (docs/safety/hazard-analysis.md H-25).

#include <string.h>

#include "esp_camera.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#include "camera_config.h"
#include "config.h"  // "../include" đã có trong INCLUDE_DIRS (src/CMakeLists.txt)
#include "stream_handler.h"

static const char *TAG = "esp32cam-stream";

// Số lần thử lại khi WiFi rớt lúc đang kết nối. Sau ngần này thì báo lỗi rõ ràng chứ
// không thử vô hạn im lặng — người đang bring-up cần biết là sai SSID/mật khẩu.
#define WIFI_MAX_RETRY 10

#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAILED_BIT BIT1

static EventGroupHandle_t s_wifi_events;
static int s_retry_count;

static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data) {
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
        return;
    }

    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        if (s_retry_count < WIFI_MAX_RETRY) {
            s_retry_count++;
            ESP_LOGW(TAG, "WiFi rớt, thử lại lần %d/%d", s_retry_count, WIFI_MAX_RETRY);
            esp_wifi_connect();
        } else {
            xEventGroupSetBits(s_wifi_events, WIFI_FAILED_BIT);
        }
        return;
    }

    if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        // Chờ tới ĐÚNG sự kiện này, không chỉ chờ "đã liên kết với AP" — liên kết
        // xong mà chưa có IP thì HTTP server chưa phục vụ được ai.
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
        ESP_LOGI(TAG, "======================================");
        ESP_LOGI(TAG, "  Đã có IP: " IPSTR, IP2STR(&event->ip_info.ip));
        ESP_LOGI(TAG, "  Trình duyệt : http://" IPSTR "/", IP2STR(&event->ip_info.ip));
        ESP_LOGI(TAG, "  PoC Python  : http://" IPSTR ":81/stream",
                 IP2STR(&event->ip_info.ip));
        ESP_LOGI(TAG, "======================================");
        s_retry_count = 0;
        xEventGroupSetBits(s_wifi_events, WIFI_CONNECTED_BIT);
    }
}

// Trả ESP_OK khi đã có IP. Cố ý KHÔNG dùng ESP_ERROR_CHECK cho đường WiFi: sai mật
// khẩu không được phép biến thành vòng lặp reboot, vì reboot loop che mất chính thông
// báo lỗi mà người bring-up cần đọc.
static esp_err_t wifi_init_sta(void) {
    s_wifi_events = xEventGroupCreate();
    if (s_wifi_events == NULL) {
        return ESP_ERR_NO_MEM;
    }

    esp_err_t err = esp_netif_init();
    if (err != ESP_OK) {
        return err;
    }
    err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;
    }
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t init_cfg = WIFI_INIT_CONFIG_DEFAULT();
    err = esp_wifi_init(&init_cfg);
    if (err != ESP_OK) {
        return err;
    }

    esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                        &wifi_event_handler, NULL, NULL);
    esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                        &wifi_event_handler, NULL, NULL);

    wifi_config_t wifi_config = {0};
    strncpy((char *)wifi_config.sta.ssid, WIFI_SSID,
            sizeof(wifi_config.sta.ssid) - 1);
    strncpy((char *)wifi_config.sta.password, WIFI_PASS,
            sizeof(wifi_config.sta.password) - 1);

    err = esp_wifi_set_mode(WIFI_MODE_STA);
    if (err != ESP_OK) {
        return err;
    }
    err = esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
    if (err != ESP_OK) {
        return err;
    }
    err = esp_wifi_start();
    if (err != ESP_OK) {
        return err;
    }

    // Tắt power-save: mặc định ESP32 ngủ giữa các beacon, gây khựng và trễ thấy rõ
    // trên stream liên tục. Node này cắm nguồn cố định, không cần tiết kiệm điện.
    esp_wifi_set_ps(WIFI_PS_NONE);

    EventBits_t bits = xEventGroupWaitBits(
        s_wifi_events, WIFI_CONNECTED_BIT | WIFI_FAILED_BIT, pdFALSE, pdFALSE,
        portMAX_DELAY);

    if (bits & WIFI_CONNECTED_BIT) {
        return ESP_OK;
    }
    ESP_LOGE(TAG, "Không nối được WiFi sau %d lần thử — kiểm tra WIFI_SSID/WIFI_PASS "
                  "trong include/config.h, và chắc chắn AP là băng tần 2.4GHz "
                  "(ESP32 không bắt được 5GHz)", WIFI_MAX_RETRY);
    return ESP_FAIL;
}

void app_main(void) {
    // Gotcha kinh điển ESP-IDF: lần đầu đổi partition table (hoặc NVS khác version)
    // trả ESP_ERR_NVS_NO_FREE_PAGES/NEW_VERSION_FOUND — phải erase rồi init lại,
    // không phải lỗi thật cần abort.
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    // Camera trước WiFi: nếu PSRAM chưa bật thì lỗi lộ ra ngay, không bị lẫn vào một
    // chuỗi log WiFi dài.
    camera_config_t cam_config = esp32cam_camera_config();
    err = esp_camera_init(&cam_config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_camera_init thất bại (0x%x)", err);
        if (err == ESP_ERR_NO_MEM) {
            ESP_LOGE(TAG, "ESP_ERR_NO_MEM — kiểm tra PSRAM TRƯỚC TIÊN: sdkconfig.defaults "
                          "phải có CONFIG_SPIRAM=y. VGA JPEG fb_count=2 không vừa SRAM nội.");
        }
        ESP_LOGE(TAG, "Dừng ở đây — không có camera thì stream vô nghĩa.");
        return;
    }
    ESP_LOGI(TAG, "Camera OK — VGA 640x480, JPEG quality 12, 2 frame buffer trong PSRAM");

    if (wifi_init_sta() != ESP_OK) {
        ESP_LOGE(TAG, "Dừng ở đây — không có mạng thì không ai xem được stream.");
        return;
    }

    if (start_webserver() != ESP_OK) {
        ESP_LOGE(TAG, "Dừng ở đây — HTTP server không lên được.");
        return;
    }

    // Không cần vòng lặp gì thêm: httpd chạy trong task riêng. app_main thoát là bình
    // thường trong ESP-IDF, task của nó bị xoá còn hệ thống vẫn chạy tiếp.
    ESP_LOGI(TAG, "Sẵn sàng. Mở URL in ở trên.");
}
