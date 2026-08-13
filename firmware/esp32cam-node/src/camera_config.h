// Pin map + cấu hình OV2640 cho board AI-Thinker ESP32-CAM.
// SIOD/SIOC (GPIO26/27) là bus SCCB — VL53L0X (vl53l0x.cpp) dùng CHUNG hai chân này
// qua i2c driver riêng, xem ghi chú rủi ro trong plans/260813-0934-esp32cam-vl53l0x-camera-node/phase-03-firmware-node-camera.md.
#pragma once

#include "esp_camera.h"

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
    config.pin_sccb_sda = CAM_PIN_SIOD;
    config.pin_sccb_scl = CAM_PIN_SIOC;
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
