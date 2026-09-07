#include "sleep-pad-frame.h"

char pad_device_id[11] = "UNCONFIGED";

void sp_send_frame(uint8_t type, const uint8_t* content, size_t n) {
    size_t frame_len = 15 + n;
    uint8_t* buf = new uint8_t[frame_len];
    
    buf[0] = 0x7D;
    buf[1] = type;
    buf[2] = frame_len & 0xFF;        // Độ dài little-endian
    buf[3] = (frame_len >> 8) & 0xFF;
    
    // Sao chép ID (10 byte ASCII)
    for (int i = 0; i < 10; ++i) {
        if (pad_device_id[i] != '\0') {
            buf[4 + i] = pad_device_id[i];
        } else {
            buf[4 + i] = ' '; // Pad bằng khoảng trắng nếu chuỗi ngắn
        }
    }
    
    // Sao chép nội dung
    if (content != nullptr && n > 0) {
        memcpy(&buf[14], content, n);
    }
    
    // Kết thúc khung
    buf[frame_len - 1] = 0x0D;
    
    // Gửi qua Serial1
    Serial1.write(buf, frame_len);
    
    delete[] buf;
}
