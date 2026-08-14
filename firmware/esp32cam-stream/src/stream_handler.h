// Tầng HTTP của node. main.c chỉ cần một hàm này sau khi camera + WiFi đã sẵn sàng.
#pragma once

#include "esp_err.h"

// Khởi động HTTP server và đăng ký hai route:
//   GET /        trang HTML tối giản để kiểm tra bằng mắt
//   GET /stream  MJPEG multipart, chạy tới khi client ngắt
// Trả ESP_OK nếu server lên được. Camera phải init xong TRƯỚC khi gọi.
esp_err_t start_webserver(void);
