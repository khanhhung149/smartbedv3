// WiFi station + đồng hồ NTP + mDNS cho radar-node.
//
// Không treo boot: nối WiFi chạy nền, mất sóng thì tự thử lại, phần còn lại của firmware
// (đọc radar, phát log) vẫn chạy bình thường khi chưa có mạng.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

// IP tĩnh cho station. Chuỗi dạng "192.168.137.50" — DNS lấy luôn theo gateway.
typedef struct {
  const char *ip;
  const char *gw;
  const char *mask;
} net_static_ip_t;

// Khởi động WiFi STA + SNTP + mDNS. hostname dùng cho cả DHCP lẫn <hostname>.local.
// static_ip = NULL thì xin địa chỉ qua DHCP như bình thường.
esp_err_t net_start(const char *ssid, const char *pass, const char *hostname,
                    const net_static_ip_t *static_ip);

// Đã có IP hay chưa.
bool net_has_ip(void);

// Thời gian epoch (ms). Trả 0 khi NTP chưa đồng bộ — đừng ghi mốc 0 vào lịch sử.
uint64_t net_epoch_ms(void);

// NTP đã đồng bộ chưa.
static inline bool net_time_ready(void) { return net_epoch_ms() > 0; }
