// Driver tối giản cho VL53L0X qua bus I2C dùng CHUNG với SCCB của camera
// (GPIO26=SDA, GPIO27=SCL). Địa chỉ mặc định 0x29.
//
// CHƯA cắm chuỗi hiệu chuẩn đầy đủ của ST (SPAD calibration, VHV/phase calibration —
// hàng trăm dòng trong VL53L0X API gốc STSW-IMG005). Tự chép lại chuỗi đó từ trí nhớ
// rủi ro sai số đo mà khó phát hiện trên phần cứng thật. Việc phải làm trước khi dùng
// thật (xem phase-03 Implementation Step 3): vendor component chính thức của ST hoặc
// một port ESP-IDF đã kiểm chứng, cắm vào vl53l0x_init()/vl53l0x_read_distance_mm().
#pragma once

#include <cstdint>
#include "esp_err.h"

#define VL53L0X_I2C_ADDR 0x29

// i2c_port phải TRÙNG với port camera SCCB nhả ra sau khi esp_camera_init() xong —
// xem ghi chú rủi ro chia sẻ bus trong main.cpp.
esp_err_t vl53l0x_init(int i2c_port, int sda_gpio, int scl_gpio);

// Trả về khoảng cách (mm), hoặc -1 nếu đọc lỗi/timeout (đánh dấu dropout — KHÔNG bịa số 0,
// đúng nguyên tắc "dropout đánh dấu, không bịa" của toàn dự án).
int32_t vl53l0x_read_distance_mm();
