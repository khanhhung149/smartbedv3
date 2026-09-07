#include "sleep-pad-frame.h"
#include "config.h"
#include "driver/uart.h"
#include <string.h>
#include <stdlib.h>

char pad_device_id[11] = "UNCONFIGED";

void sp_send_frame(uint8_t type, const uint8_t* content, size_t n) {
    size_t frame_len = 15 + n;
    uint8_t* buf = (uint8_t*)malloc(frame_len);
    if (!buf) return;

    buf[0] = 0x7D;
    buf[1] = type;
    buf[2] = frame_len & 0xFF;        // Độ dài little-endian
    buf[3] = (frame_len >> 8) & 0xFF;

    // Sao chép ID (10 byte ASCII)
    for (int i = 0; i < 10; ++i) {
        buf[4 + i] = pad_device_id[i] != '\0' ? (uint8_t)pad_device_id[i] : ' ';
    }

    if (content != NULL && n > 0) {
        memcpy(&buf[14], content, n);
    }

    buf[frame_len - 1] = 0x0D;

    uart_write_bytes(SLEEPPAD_UART_NUM, (const char*)buf, frame_len);

    free(buf);
}
