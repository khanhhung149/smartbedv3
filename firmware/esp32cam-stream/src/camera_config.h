// Pin map + cấu hình OV2640 cho board AI-Thinker ESP32-CAM.
//
// SIOD/SIOC (GPIO26/27) là bus SCCB nội bộ của camera, chỉ nối tới đầu FPC, KHÔNG đưa
// ra header ngoài (xác nhận khi bring-up thật 13/08). Không hàn thêm thiết bị I2C vào
// đó được — và node này cũng không có thiết bị I2C nào.
#pragma once

#include "esp_camera.h"

// AI-Thinker ESP32-CAM — pin map chuẩn, không đổi trừ khi dùng board khác.
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

// VGA 640x480 thay vì SVGA của node cũ: MediaPipe Pose resize ảnh về 256x256 trước khi
// suy luận, nên độ phân giải cao hơn không cho landmark chính xác hơn — chỉ tốn thêm
// băng thông WiFi và làm fps tụt. Xem plan §5.
static inline camera_config_t esp32cam_camera_config(void) {
    camera_config_t config = {0};
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
    config.frame_size = FRAMESIZE_VGA;  // 640x480
    config.jpeg_quality = 12;           // 0-63, thấp hơn = nét hơn/nặng hơn
    config.fb_count = 2;                // double-buffer, BẮT BUỘC có PSRAM
    config.fb_location = CAMERA_FB_IN_PSRAM;
    // GRAB_LATEST: khi WiFi nghẽn, thà bỏ frame cũ còn hơn tích luỹ độ trễ. Người xem
    // stream cần thấy hiện tại, không cần thấy đủ mọi frame.
    config.grab_mode = CAMERA_GRAB_LATEST;

    return config;
}
