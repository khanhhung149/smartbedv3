// Driver tối giản cho VL53L0X qua bus I2C dùng CHUNG với SCCB của camera
// (GPIO26=SDA, GPIO27=SCL). Địa chỉ mặc định 0x29.
//
// CHƯA cắm chuỗi hiệu chuẩn đầy đủ của ST (SPAD calibration, VHV/phase calibration —
// hàng trăm dòng trong VL53L0X API gốc STSW-IMG005). Quyết định 13/08 (bench-test,
// VL53L0X chưa cắm dây): giữ bản tối giản này, chỉ nâng cấp nếu độ chính xác thực tế
// không đủ dùng cho "khoảng cách người-camera hỗ trợ pose" (không cần lab-grade).
//
// Nếu cần nâng cấp sau: https://github.com/benlazzero/Esp32S3-and-VL53L0X vendor sẵn
// bộ ST API đầy đủ (vl53l0x_api_calibration.c...) — NHƯNG platform.c của họ dùng API
// I2C cũ (driver/i2c.h), xung đột với espressif/esp32-camera bản mới (dùng i2c_master
// "driver_ng" cho SCCB, xem lịch sử fix trong main.cpp/CHANGELOG plan). Phải viết lại
// lớp glue I2C của họ bằng driver/i2c_master.h (theo mẫu i2c_master_transmit đã dùng
// trong vl53l0x.cpp này) trước khi vendor, không copy nguyên platform.c của họ.
#pragma once

#include <cstdint>
#include "esp_err.h"

#define VL53L0X_I2C_ADDR 0x29

// Port I2C dùng chung cho cả VL53L0X và camera SCCB (xem camera_config.h) — PHẢI
// khớp giá trị camera_config.h truyền vào sccb_i2c_port, nếu không sẽ tạo 2 bus
// khác nhau trên cùng GPIO26/27, gây "I2C bus id already acquired" hoặc lỗi bus.
#define SHARED_SCCB_I2C_PORT 1

// i2c_port phải TRÙNG với port camera SCCB nhả ra sau khi esp_camera_init() xong —
// xem ghi chú rủi ro chia sẻ bus trong main.cpp.
esp_err_t vl53l0x_init(int i2c_port, int sda_gpio, int scl_gpio);

// Trả về khoảng cách (mm), hoặc -1 nếu đọc lỗi/timeout (đánh dấu dropout — KHÔNG bịa số 0,
// đúng nguyên tắc "dropout đánh dấu, không bịa" của toàn dự án).
int32_t vl53l0x_read_distance_mm();
