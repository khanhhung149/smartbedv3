#pragma once
#include <stdint.h>
#include <stddef.h>

// ID thiết bị do pad trả về, dùng để đóng gói các khung gửi đi
extern char pad_device_id[11]; // 10 chars + null

// Dựng khung 0x7D theo chuẩn hãng và gửi qua SLEEPPAD_UART_NUM
void sp_send_frame(uint8_t type, const uint8_t* content, size_t n);
