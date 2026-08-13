// Pin map + cấu hình OV2640 cho board AI-Thinker ESP32-CAM.
// SIOD/SIOC (GPIO26/27) là bus SCCB — VL53L0X (vl53l0x.cpp) dùng CHUNG bus này.
//
// QUAN TRỌNG: 2 driver I2C (esp32-camera SCCB + VL53L0X) KHÔNG thể mỗi bên tự tạo
// bus riêng trên cùng GPIO26/27 — bắt được lỗi thật "I2C bus id(1) has already been
// acquired" khi flash lên phần cứng (13/08). Kiến trúc đúng: vl53l0x_init() tạo bus
// i2c_master TRƯỚC (main.cpp gọi trước esp_camera_init), rồi camera dùng LẠI đúng
// bus đó qua SCCB_Use_Port() của esp32-camera — kích hoạt bằng cách đặt
// pin_sccb_sda=-1 (thay vì gán chân) và điền sccb_i2c_port. Xem
// driver/esp_camera.c:185-190 và driver/sccb-ng.c:187 trong managed_components.
#pragma once

#include "esp_camera.h"
#include "vl53l0x.h"  // SHARED_SCCB_I2C_PORT

// AI-Thinker ESP32-CAM — pin map chuẩn, không đổi trừ khi board khác.
#define CAM_PIN_PWDN 32
#define CAM_PIN_RESET -1  // không dùng chân reset phần cứng
#define CAM_PIN_XCLK 0
#define CAM_PIN_SIOD 26
#define CAM_PIN_SIOC 27
#define CAM_PIN_D7 35
#define CAM_PIN_D6 34
#define CAM_PIN_D5 39
#define CAM_PIN_D4 36
#define CAM_PIN_D3 21
#define CAM_PIN_D2 19
#define CAM_PIN_D1 18
#define CAM_PIN_D0 5
#define CAM_PIN_VSYNC 25
#define CAM_PIN_HREF 23
#define CAM_PIN_PCLK 22

// SVGA 800x600 — quyết định đã chốt khi lập plan (giữ rotating 30 đêm, xem plan.md
// Quyết định #4). ~35KB/frame JPEG chất lượng vừa, ~5fps mục tiêu -> ~5GB/đêm.
inline camera_config_t esp32cam_camera_config() {
    camera_config_t config = {};
    config.pin_pwdn = CAM_PIN_PWDN;
    config.pin_reset = CAM_PIN_RESET;
    config.pin_xclk = CAM_PIN_XCLK;
    // -1 = KHÔNG tự tạo bus SCCB riêng — dùng lại bus i2c_master đã tạo sẵn ở
    // SHARED_SCCB_I2C_PORT (vl53l0x_init() phải chạy TRƯỚC esp_camera_init(), xem
    // main.cpp). Đặt pin_sccb_sda/scl thật (CAM_PIN_SIOD/SIOC) sẽ khiến camera tự
    // tạo bus riêng, xung đột với bus VL53L0X đã tạo — bug thật đã bắt được 13/08.
    config.pin_sccb_sda = -1;
    config.pin_sccb_scl = -1;
    config.sccb_i2c_port = SHARED_SCCB_I2C_PORT;
    config.pin_d7 = CAM_PIN_D7;
    config.pin_d6 = CAM_PIN_D6;
    config.pin_d5 = CAM_PIN_D5;
    config.pin_d4 = CAM_PIN_D4;
    config.pin_d3 = CAM_PIN_D3;
    config.pin_d2 = CAM_PIN_D2;
    config.pin_d1 = CAM_PIN_D1;
    config.pin_d0 = CAM_PIN_D0;
    config.pin_vsync = CAM_PIN_VSYNC;
    config.pin_href = CAM_PIN_HREF;
    config.pin_pclk = CAM_PIN_PCLK;

    config.xclk_freq_hz = 20000000;
    config.ledc_timer = LEDC_TIMER_0;
    config.ledc_channel = LEDC_CHANNEL_0;

    config.pixel_format = PIXFORMAT_JPEG;
    config.frame_size = FRAMESIZE_SVGA;  // 800x600 — xem quyết định plan §4
    config.jpeg_quality = 12;            // 0-63, thấp hơn = chất lượng cao hơn/nặng hơn
    config.fb_count = 2;                 // double-buffer, cần PSRAM (AI-Thinker có sẵn)
    config.fb_location = CAMERA_FB_IN_PSRAM;
    config.grab_mode = CAMERA_GRAB_LATEST;

    return config;
}
