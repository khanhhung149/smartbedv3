#pragma once
#include "driver/uart.h"

// Cấu hình phần cứng cố định — không đụng WiFi/MQTT (đến từ BLE provisioning + NVS,
// xem nvs-config.h). Chân UART giữ NGUYÊN như bản Arduino cũ (đã xác định bằng thực
// nghiệm trên board thật, xem lịch sử file này trước khi port).

// UART pins for sleep pad (Legact Pro V2 / LSM-800-T).
// C3 Super Mini: đợt dây 24/08 đấu D- -> IO5, D+ -> IO6 (ngược lại đợt trước —
// D+ -> IO5, D- -> IO6 — nên RX=6/TX=5 cũ nhận toàn im lặng). Đảo lại RX=5/TX=6 khớp
// dây thật đang cắm. Nếu đổi dây lần nữa mà lại câm hoàn toàn >30s, kiểm lại thứ tự
// D+/D- trước khi nghi ngờ code. Tránh USB D± (18/19) và strapping (2/8/9) của C3.
#define UART_RX_PIN         5
#define UART_TX_PIN         6
#define UART_BAUD           115200
#define SLEEPPAD_UART_NUM   UART_NUM_1
