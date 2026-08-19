// Nạp firmware qua WiFi: máy chủ HTTP nhỏ nhận POST /update rồi ghi thẳng vào phân vùng OTA.
//
// Vì sao không phải ArduinoOTA/espota như bản cũ: espota là giao thức của Arduino core (mời qua
// UDP 3232 rồi thiết bị quay ngược TCP về máy nạp), ESP-IDF thuần không có sẵn phía thiết bị.
// Một endpoint POST thì nạp bằng curl được, thử tay được, và không cần cổng UDP nào.
//
// Nạp:  pio run -e lolin_s2_mini_ota -t upload      (xem upload_command trong platformio.ini)
#pragma once

#include "esp_err.h"

// Dựng máy chủ nạp. password rỗng = không kiểm (ai cùng LAN cũng nạp được).
// Gọi được trước khi có IP: socket nghe trên mọi giao diện, có mạng là dùng được ngay.
esp_err_t ota_http_start(const char *password);
