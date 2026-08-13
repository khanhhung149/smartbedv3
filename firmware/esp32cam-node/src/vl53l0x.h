// Driver tối giản cho VL53L0X. Địa chỉ mặc định 0x29.
//
// KHÔNG dùng chung bus SCCB của camera (GPIO26/27) — quyết định gốc trong plan hoá ra
// SAI: GPIO26/27 trên AI-Thinker ESP32-CAM chỉ nối nội bộ tới đầu nối FPC của camera,
// không đưa ra header ngoài (xác nhận qua WebSearch 13/08, xem plan.md Bench Bring-up
// Log). VL53L0X đi bus I2C RIÊNG trên GPIO4 (SDA) + GPIO13 (SCL) — 2 chân trống khi SD
// chạy 1-bit mode. KHÔNG dùng GPIO12: là chân bootstrap (MTDI) chọn điện áp flash lúc
// boot, pull-up của VL53L0X có thể làm board không boot được. KHÔNG dùng GPIO16: đã bị
// PSRAM chiếm (CS pin).
//
// CHƯA cắm chuỗi hiệu chuẩn đầy đủ của ST (SPAD calibration, VHV/phase calibration —
// hàng trăm dòng trong VL53L0X API gốc STSW-IMG005). Quyết định 13/08 (bench-test,
// VL53L0X chưa cắm dây): giữ bản tối giản này, chỉ nâng cấp nếu độ chính xác thực tế
// không đủ dùng cho "khoảng cách người-camera hỗ trợ pose" (không cần lab-grade).
//
// Nếu cần nâng cấp sau: https://github.com/benlazzero/Esp32S3-and-VL53L0X vendor sẵn
// bộ ST API đầy đủ (vl53l0x_api_calibration.c...) — dùng ĐÚNG kiến trúc bus riêng như
// file main/events/device_init.c của họ (i2c_master_init() độc lập, không đụng bus
// camera) — khớp với hướng đã chốt ở đây. NHƯNG platform.c của họ dùng API I2C cũ
// (driver/i2c.h), xung đột với espressif/esp32-camera bản mới (driver_ng) nếu 2 driver
// cùng link vào 1 firmware dù khác bus/port — phải viết lại lớp glue bằng
// driver/i2c_master.h (theo mẫu i2c_master_transmit đã dùng trong vl53l0x.cpp này)
// trước khi vendor, không copy nguyên platform.c của họ.
#pragma once

#include <cstdint>
#include "esp_err.h"

#define VL53L0X_I2C_ADDR 0x29

// Port I2C RIÊNG cho VL53L0X — camera SCCB mặc định dùng port 1
// (SCCB_I2C_PORT_DEFAULT trong managed_components/espressif__esp32-camera, xác nhận
// qua log thật "sccb_i2c_port=1"). Dùng port 0 ở đây để không trùng.
#define VL53L0X_I2C_PORT 0
#define VL53L0X_SDA_GPIO 4
#define VL53L0X_SCL_GPIO 13

esp_err_t vl53l0x_init(int i2c_port, int sda_gpio, int scl_gpio);

// Trả về khoảng cách (mm), hoặc -1 nếu đọc lỗi/timeout (đánh dấu dropout — KHÔNG bịa số 0,
// đúng nguyên tắc "dropout đánh dấu, không bịa" của toàn dự án).
int32_t vl53l0x_read_distance_mm();
