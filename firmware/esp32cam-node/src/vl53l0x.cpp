#include "vl53l0x.h"

#include "driver/gpio.h"
#include "driver/i2c.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

namespace {
const char* TAG = "vl53l0x";
int s_port = I2C_NUM_1;

// Thanh ghi dùng trong bản tối giản này — đúng theo datasheet VL53L0X (ST AN4907),
// KHÔNG phải chuỗi hiệu chuẩn đầy đủ (xem cảnh báo trong vl53l0x.h).
constexpr uint8_t REG_IDENTIFICATION_MODEL_ID = 0xC0;  // giá trị đúng phải đọc ra 0xEE
constexpr uint8_t REG_SYSRANGE_START = 0x00;
constexpr uint8_t REG_RESULT_INTERRUPT_STATUS = 0x13;
constexpr uint8_t REG_RESULT_RANGE_STATUS = 0x14;
constexpr uint8_t REG_SYSTEM_INTERRUPT_CLEAR = 0x0B;

esp_err_t write_reg8(uint8_t reg, uint8_t value) {
    uint8_t buf[2] = {reg, value};
    return i2c_master_write_to_device(static_cast<i2c_port_t>(s_port), VL53L0X_I2C_ADDR, buf,
                                       sizeof(buf), pdMS_TO_TICKS(50));
}

esp_err_t read_regn(uint8_t reg, uint8_t* out, size_t len) {
    esp_err_t err = i2c_master_write_to_device(static_cast<i2c_port_t>(s_port), VL53L0X_I2C_ADDR,
                                                &reg, 1, pdMS_TO_TICKS(50));
    if (err != ESP_OK) return err;
    return i2c_master_read_from_device(static_cast<i2c_port_t>(s_port), VL53L0X_I2C_ADDR, out,
                                        len, pdMS_TO_TICKS(50));
}
}  // namespace

esp_err_t vl53l0x_init(int i2c_port, int sda_gpio, int scl_gpio) {
    s_port = i2c_port;

    i2c_config_t conf = {};
    conf.mode = I2C_MODE_MASTER;
    conf.sda_io_num = sda_gpio;
    conf.scl_io_num = scl_gpio;
    conf.sda_pullup_en = GPIO_PULLUP_ENABLE;
    conf.scl_pullup_en = GPIO_PULLUP_ENABLE;
    conf.master.clk_speed = 100000;  // 100kHz — an toàn để chia sẻ bus với SCCB camera

    esp_err_t err = i2c_param_config(static_cast<i2c_port_t>(s_port), &conf);
    if (err != ESP_OK) return err;
    err = i2c_driver_install(static_cast<i2c_port_t>(s_port), conf.mode, 0, 0, 0);
    if (err != ESP_OK) return err;

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

    ESP_LOGI(TAG, "VL53L0X init xong (model_id=0x%02X, port=%d)", model_id, s_port);
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
