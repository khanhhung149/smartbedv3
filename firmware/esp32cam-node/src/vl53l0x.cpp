#include "vl53l0x.h"

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

// Dùng driver/i2c_master.h ("driver_ng") — KHÔNG dùng driver/i2c.h (API cũ). ESP-IDF
// 5.x không cho phép 2 driver I2C tồn tại chung 1 firmware; espressif/esp32-camera
// (SCCB nội bộ) đã dùng driver_ng, dùng API cũ ở đây gây abort() thật lúc boot
// ("CONFLICT! driver_ng is not allowed to be used with this old driver") — bug đã
// bắt được khi flash lên phần cứng thật lần đầu (13/08).

namespace {
const char* TAG = "vl53l0x";
i2c_master_bus_handle_t s_bus = nullptr;
i2c_master_dev_handle_t s_dev = nullptr;

// Thanh ghi dùng trong bản tối giản này — đúng theo datasheet VL53L0X (ST AN4907),
// KHÔNG phải chuỗi hiệu chuẩn đầy đủ (xem cảnh báo trong vl53l0x.h).
constexpr uint8_t REG_IDENTIFICATION_MODEL_ID = 0xC0;  // giá trị đúng phải đọc ra 0xEE
constexpr uint8_t REG_SYSRANGE_START = 0x00;
constexpr uint8_t REG_RESULT_INTERRUPT_STATUS = 0x13;
constexpr uint8_t REG_RESULT_RANGE_STATUS = 0x14;
constexpr uint8_t REG_SYSTEM_INTERRUPT_CLEAR = 0x0B;

esp_err_t write_reg8(uint8_t reg, uint8_t value) {
    uint8_t buf[2] = {reg, value};
    return i2c_master_transmit(s_dev, buf, sizeof(buf), 50);
}

esp_err_t read_regn(uint8_t reg, uint8_t* out, size_t len) {
    return i2c_master_transmit_receive(s_dev, &reg, 1, out, len, 50);
}

// int32_t đọc/ghi 1 lệnh máy là atomic trên Xtensa — 1 task ghi (background), 1 task
// đọc (vòng lặp camera), không cần mutex cho use-case đơn giản này (KISS).
volatile int32_t s_latest_distance_mm = -1;

void vl53l0x_poll_task(void*) {
    while (true) {
        s_latest_distance_mm = vl53l0x_read_distance_mm();
        // Đo xong (hoặc timeout ~850ms) thì nghỉ ngắn rồi đo tiếp — không cần đo dồn
        // dập, ToF không phải nguồn dữ liệu chính. Không có công việc nào khác trên
        // task này nên không cần tự giới hạn tần suất chặt hơn.
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}
}  // namespace

void vl53l0x_start_background_task() {
    xTaskCreate(vl53l0x_poll_task, "vl53l0x_poll", 3072, nullptr, 1, nullptr);
    ESP_LOGI(TAG, "Task đo ToF nền đã khởi động — không còn chặn vòng lặp camera");
}

int32_t vl53l0x_get_latest_distance_mm() { return s_latest_distance_mm; }

esp_err_t vl53l0x_init(int i2c_port, int sda_gpio, int scl_gpio) {
    i2c_master_bus_config_t bus_config = {};
    bus_config.i2c_port = static_cast<i2c_port_t>(i2c_port);
    bus_config.sda_io_num = static_cast<gpio_num_t>(sda_gpio);
    bus_config.scl_io_num = static_cast<gpio_num_t>(scl_gpio);
    bus_config.clk_source = I2C_CLK_SRC_DEFAULT;
    bus_config.glitch_ignore_cnt = 7;
    bus_config.flags.enable_internal_pullup = true;

    esp_err_t err = i2c_new_master_bus(&bus_config, &s_bus);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "i2c_new_master_bus lỗi (0x%x)", err);
        return err;
    }

    i2c_device_config_t dev_config = {};
    dev_config.dev_addr_length = I2C_ADDR_BIT_LEN_7;
    dev_config.device_address = VL53L0X_I2C_ADDR;
    // Bus RIÊNG (không còn chia sẻ SCCB camera từ 13/08) — VL53L0X hỗ trợ Fast Mode
    // 400kHz theo datasheet, không có lý do gì giữ 100kHz nữa.
    dev_config.scl_speed_hz = 400000;

    err = i2c_master_bus_add_device(s_bus, &dev_config, &s_dev);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "i2c_master_bus_add_device lỗi (0x%x)", err);
        return err;
    }

    uint8_t model_id = 0;
    err = read_regn(REG_IDENTIFICATION_MODEL_ID, &model_id, 1);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Không đọc được bus I2C tại 0x%02X — kiểm tra dây/địa chỉ", VL53L0X_I2C_ADDR);
        return err;
    }
    if (model_id != 0xEE) {
        ESP_LOGW(TAG, "Model ID đọc được 0x%02X, kỳ vọng 0xEE — có thể không phải VL53L0X thật",
                 model_id);
    }

    // TODO (Phase 3, Implementation Step 3): cắm chuỗi khởi tạo/hiệu chuẩn đầy đủ của
    // ST (SPAD, VHV, phase cal — VL53L0X API STSW-IMG005 hoặc port ESP-IDF tương đương).
    // Không có bước này, cảm biến vẫn đo được (single-shot polling dưới đây) nhưng độ
    // chính xác thấp hơn số liệu datasheet.

    ESP_LOGI(TAG, "VL53L0X init xong (model_id=0x%02X, port=%d)", model_id, i2c_port);
    return ESP_OK;
}

int32_t vl53l0x_read_distance_mm() {
    if (write_reg8(REG_SYSRANGE_START, 0x01) != ESP_OK) return -1;

    uint8_t status = 0;
    const int max_polls = 50;  // ~50ms timeout ở 1ms/poll
    for (int i = 0; i < max_polls; ++i) {
        if (read_regn(REG_RESULT_INTERRUPT_STATUS, &status, 1) != ESP_OK) return -1;
        if ((status & 0x07) != 0) break;
        vTaskDelay(pdMS_TO_TICKS(1));
    }
    if ((status & 0x07) == 0) {
        ESP_LOGW(TAG, "Timeout chờ kết quả đo — trả dropout");
        return -1;
    }

    uint8_t range_buf[12] = {};
    if (read_regn(REG_RESULT_RANGE_STATUS, range_buf, sizeof(range_buf)) != ESP_OK) return -1;
    write_reg8(REG_SYSTEM_INTERRUPT_CLEAR, 0x01);

    // Offset +10/+11 trong khối RESULT_RANGE_STATUS là range value (mm), big-endian —
    // theo datasheet VL53L0X (AN4907).
    uint16_t mm = (static_cast<uint16_t>(range_buf[10]) << 8) | range_buf[11];
    return mm;
}
