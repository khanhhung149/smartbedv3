#include "uart-parser.h"
#include "sleep-pad-frame.h"
#include <string.h>
#include "esp_log.h"

static const char* TAG = "uart-parser";

void sleeppad_parser_init(SleepPadParser* p) {
    memset(p, 0, sizeof(*p));
    p->_state = PARSER_WAIT_HEADER;
}

static void decode0x85(SleepPadParser* p, const uint8_t* c, size_t len);
static void decode0x86(SleepPadParser* p, const uint8_t* c, size_t len);
static void process_frame(SleepPadParser* p);

void sleeppad_parser_feed(SleepPadParser* p, uint8_t byte) {
    switch (p->_state) {
        case PARSER_WAIT_HEADER:
            if (byte == 0x7D) {
                p->_buf[0] = byte;
                p->_len = 1;
                p->_state = PARSER_READ_FRAME;
            }
            break;

        case PARSER_READ_FRAME: {
            if (p->_len >= UART_PARSER_MAX_BUF) {
                p->_len = 0;
                p->_state = PARSER_WAIT_HEADER;
                return;
            }
            p->_buf[p->_len++] = byte;

            // CRITICAL: dùng trường độ dài 2-byte (byte 2-3) làm ranh giới khung THẬT SỰ,
            // KHÔNG dùng byte kết 0x0D. Bất kỳ byte nội dung nào cũng có thể bằng 0x0D
            // (vd sdata=13, movement=13) — kết thúc theo nó sẽ đọc sai khung hợp lệ.
            if (p->_len >= 4) {
                const uint16_t expected_total =
                    (uint16_t)p->_buf[2] | ((uint16_t)p->_buf[3] << 8);
                if (expected_total < 16 || expected_total > UART_PARSER_MAX_BUF) {
                    p->_len = 0;
                    p->_state = PARSER_WAIT_HEADER;
                    return;
                }
                if (p->_len == expected_total) {
                    process_frame(p);
                    p->_len = 0;
                    p->_state = PARSER_WAIT_HEADER;
                }
            }
            break;
        }
    }
}

static void process_frame(SleepPadParser* p) {
    // Minimum frame: header(1)+type(1)+length(2)+id(10)+content(>=1)+end(1) = 16
    if (p->_len < 16) {
        ESP_LOGW(TAG, "Frame too short: %u bytes", (unsigned)p->_len);
        return;
    }
    if (p->_buf[0] != 0x7D || p->_buf[p->_len - 1] != 0x0D) {
        ESP_LOGW(TAG, "Invalid frame boundaries");
        return;
    }

    uint8_t frame_type = p->_buf[1];

    // Lưu ID thật của pad (byte 4-13) nếu nó khác "UNCONFIGED"
    if (strncmp((const char*)&p->_buf[4], "UNCONFIGED", 10) != 0) {
        memcpy(pad_device_id, &p->_buf[4], 10);
        pad_device_id[10] = '\0';
    }

    // Content starts at byte index 14 (header+type+length(2)+id(10)) and ends before 0x0D
    const uint8_t* content     = &p->_buf[14];
    size_t         content_len = p->_len - 14 - 1; // subtract trailing 0x0D

    if (frame_type == 0x85) {
        decode0x85(p, content, content_len);
    } else if (frame_type == 0x86) {
        decode0x86(p, content, content_len);
    } else if (frame_type == 0x84) {
        if (content_len >= 1 && p->onModeConfirmed) p->onModeConfirmed(content[0]);
    } else if (frame_type == 0x87) {
        // Khung tự phát của pad báo idle/trạng thái (async — KHÔNG phải reply request/
        // reply cho 0x07, xem plan 260824-1109). content[0] = mode hiện tại nếu >=6 byte.
        if (p->onStatusQuery) {
            p->onStatusQuery(content_len >= 6 ? content[0] : 0xFF);
        }
    } else {
        ESP_LOGD(TAG, "Frame type: 0x%02X", frame_type);
    }
}

static void decode0x85(SleepPadParser* p, const uint8_t* c, size_t len) {
    if (len != 12) {
        ESP_LOGW(TAG, "0x85 bad content len: %u (expected 12)", (unsigned)len);
        return;
    }
    SleepPadSecData d = {0};
    d.serial     = c[0];
    d.timestamp  = (uint32_t)c[1] | ((uint32_t)c[2] << 8) | ((uint32_t)c[3] << 16) | ((uint32_t)c[4] << 24);
    d.status     = c[5];
    d.heart_rate = c[6];
    d.resp_rate  = c[7] / 10.0f;
    d.sdata      = (uint16_t)c[8] | ((uint16_t)c[9] << 8);
    d.pdata      = (uint16_t)c[10] | ((uint16_t)c[11] << 8);

    if (p->onSecData) p->onSecData(&d);
}

static void decode0x86(SleepPadParser* p, const uint8_t* c, size_t len) {
    if (len != 15) {
        ESP_LOGW(TAG, "0x86 bad content len: %u (expected 15)", (unsigned)len);
        return;
    }
    SleepPadMinData d = {0};
    d.serial        = c[0];
    d.timestamp     = (uint32_t)c[1] | ((uint32_t)c[2] << 8) | ((uint32_t)c[3] << 16) | ((uint32_t)c[4] << 24);
    d.status        = c[5];
    d.heart_rate    = c[6];
    d.resp_rate     = c[7] / 10.0f;
    d.movement      = c[8];
    d.snore_count   = c[9];
    d.resp_disorder = c[10];
    d.pthd          = (uint16_t)c[11] | ((uint16_t)c[12] << 8);
    d.temp          = (uint16_t)c[13] | ((uint16_t)c[14] << 8);

    if (p->onMinData) p->onMinData(&d);
}

const char* sleeppad_status_to_string(uint8_t code) {
    switch (code) {
        case 0x01: return "GET_OUT_OF_BED";
        case 0x02: return "MOVEMENT";
        case 0x03: return "SIT_UP";
        case 0x04: return "SLEEP";
        case 0x05: return "WAKE_UP";
        case 0x06: return "HEAVY_OBJECT";
        case 0x07: return "SNORE";
        case 0x08: return "WEAK_BREATHING";
        default:   return "UNKNOWN";
    }
}

// ---------------------------------------------------------------------------
// Đường LSM-800-T (lệnh ASCII TAOSG). Khối 66 byte, 1 Hz:
//   [Odata](5) + 25×int16 áp điện (50) + áp lực int16 (2) + [Bdata](5) + 4 byte
// Bốn byte sau [Bdata]: serial(0-59), trạng thái, nhịp tim, nhịp thở/10.
// LƯU Ý theo tài liệu, không suy đoán:
//   - trạng thái 0 = ĐANG NẰM trên giường; 1 = đã rời giường.
//   - nhịp tim/nhịp thở chỉ có giá trị sau 25 giây nằm yên liên tục, nên bằng 0
//     trong 25 giây đầu là đúng chứ không phải lỗi đọc.
//   - sdata: tài liệu không định nghĩa một giá trị đơn, đây là 25 mẫu áp điện.
//     Lấy biên độ tuyệt đối lớn nhất trong 25 mẫu làm đại diện mức dao động —
//     đây là DIỄN GIẢI, không phải định nghĩa của hãng.
void sleeppad_parser_feed_taos(SleepPadParser* p, uint8_t byte) {
    static const uint8_t TAG_BDATA[5] = {0x42, 0x64, 0x61, 0x74, 0x61}; // "Bdata"

    if (p->_histLen >= UART_PARSER_TAOS_HIST) {
        memmove(p->_hist, p->_hist + p->_histLen - UART_PARSER_TAOS_KEEP, UART_PARSER_TAOS_KEEP);
        p->_histLen = UART_PARSER_TAOS_KEEP;
    }
    p->_hist[p->_histLen++] = byte;
    if (p->_histLen < 9) return;

    const size_t pos = p->_histLen - 9; // vị trí byte 'B' nếu đây là khung
    if (memcmp(&p->_hist[pos], TAG_BDATA, 5) != 0) return;

    SleepPadSecData d = {0};
    const uint8_t* v = &p->_hist[pos + 5];
    d.serial      = v[0];
    d.status      = v[1];
    d.heart_rate  = v[2];
    d.resp_rate   = v[3] / 10.0f;
    d.timestamp   = 0; // chế độ TAOSG không gửi epoch; ts thật do MCU gắn lúc publish

    if (pos >= 57) { // đủ [Odata]+áp điện+áp lực phía trước => khung đầy đủ
        const size_t press = pos - 2;
        d.pdata = (uint16_t)(p->_hist[press] | (p->_hist[press + 1] << 8));

        const size_t piezo = pos - 52;
        int16_t peak = 0;
        for (int i = 0; i < 25; i++) {
            const int16_t sample =
                (int16_t)(p->_hist[piezo + i * 2] | (p->_hist[piezo + i * 2 + 1] << 8));
            const int16_t mag = sample < 0 ? (int16_t)-sample : sample;
            if (mag > peak) peak = mag;
        }
        d.sdata = (uint16_t)peak;
    }

    if (p->onSecData) p->onSecData(&d);
    p->_histLen = 0;
}
