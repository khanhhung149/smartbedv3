#include "uart-parser.h"
#include <string.h>

SleepPadParser::SleepPadParser()
    : onSecData(nullptr), onMinData(nullptr), onIdle(nullptr),
      _state(ParserState::WAIT_HEADER), _len(0), _histLen(0) {}

void SleepPadParser::feed(uint8_t byte) {
    switch (_state) {
        case ParserState::WAIT_HEADER:
            if (byte == FRAME_HEADER) {
                _buf[0] = byte;
                _len = 1;
                _state = ParserState::READ_FRAME;
            }
            break;

        case ParserState::READ_FRAME: {
            if (_len >= MAX_BUF) {
                _len = 0;
                _state = ParserState::WAIT_HEADER;
                return;
            }
            _buf[_len++] = byte;

            // CRITICAL: use the 2-byte length field (bytes 2-3) as the
            // authoritative frame boundary, NOT the 0x0D tail byte.  Any
            // content byte can legitimately equal 0x0D (e.g. sdata=13,
            // movement=13) — terminating on it mis-parses valid frames.
            if (_len >= 4) {
                const uint16_t expected_total =
                    (uint16_t)_buf[2] | ((uint16_t)_buf[3] << 8);
                if (expected_total < 16 || expected_total > MAX_BUF) {
                    // Bad length — resync.
                    _len = 0;
                    _state = ParserState::WAIT_HEADER;
                    return;
                }
                if (_len == expected_total) {
                    processFrame();
                    _len = 0;
                    _state = ParserState::WAIT_HEADER;
                }
            }
            break;
        }

        default:
            _state = ParserState::WAIT_HEADER;
            break;
    }
}

void SleepPadParser::processFrame() {
    // Minimum frame: header(1) + type(1) + length(2) + id(10) + content(>=1) + end(1) = 16
    if (_len < 16) {
        Serial.printf("[Parser] Frame too short: %u bytes\n", _len);
        return;
    }
    if (_buf[0] != FRAME_HEADER || _buf[_len - 1] != FRAME_END) {
        Serial.println("[Parser] Invalid frame boundaries");
        return;
    }

    uint8_t frame_type = _buf[1];

    // Content starts at byte index 14 (header+type+length(2)+id(10)) and ends before 0x0D
    const uint8_t* content     = &_buf[14];
    size_t         content_len = _len - 14 - 1; // subtract trailing 0x0D

    if (frame_type == 0x85) {
        decode0x85(content, content_len);
    } else if (frame_type == 0x86) {
        decode0x86(content, content_len);
    } else if (frame_type == 0x87) {
        // Device idle — requesting server commands (time cal, work mode, etc.)
        Serial.println("[Parser] 0x87 device idle, requesting commands");
        if (onIdle) onIdle();
    } else {
        Serial.printf("[Parser] Frame type: 0x%02X\n", frame_type);
    }
}

void SleepPadParser::decode0x85(const uint8_t* c, size_t len) {
    if (len != 12) {
        Serial.printf("[Parser] 0x85 bad content len: %u (expected 12)\n", len);
        return;
    }
    SleepPadSecData d;
    d.serial     = c[0];
    d.timestamp  = (uint32_t)c[1] | ((uint32_t)c[2] << 8) | ((uint32_t)c[3] << 16) | ((uint32_t)c[4] << 24);
    d.status     = c[5];
    d.heart_rate = c[6];
    d.resp_rate  = c[7] / 10.0f;
    d.sdata      = (uint16_t)c[8] | ((uint16_t)c[9] << 8);
    d.pdata      = (uint16_t)c[10] | ((uint16_t)c[11] << 8);

    if (onSecData) onSecData(d);
}

void SleepPadParser::decode0x86(const uint8_t* c, size_t len) {
    if (len != 15) {
        Serial.printf("[Parser] 0x86 bad content len: %u (expected 15)\n", len);
        return;
    }
    SleepPadMinData d;
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

    if (onMinData) onMinData(d);
}

const char* SleepPadParser::statusToString(uint8_t code) {
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
void SleepPadParser::feedTaos(uint8_t byte) {
    static const uint8_t TAG[5] = {0x42, 0x64, 0x61, 0x74, 0x61}; // "Bdata"

    if (_histLen >= TAOS_HIST) {
        memmove(_hist, _hist + _histLen - TAOS_KEEP, TAOS_KEEP);
        _histLen = TAOS_KEEP;
    }
    _hist[_histLen++] = byte;
    if (_histLen < 9) return;

    const size_t p = _histLen - 9;              // vị trí byte 'B' nếu đây là khung
    if (memcmp(&_hist[p], TAG, 5) != 0) return;

    SleepPadSecData d = {};
    const uint8_t* v = &_hist[p + 5];
    d.serial      = v[0];
    d.status      = v[1];
    d.heart_rate  = v[2];
    d.resp_rate   = v[3] / 10.0f;
    d.timestamp   = 0;   // chế độ TAOSG không gửi epoch; ts thật do MCU gắn lúc publish

    if (p >= 57) {   // đủ [Odata]+áp điện+áp lực phía trước => khung đầy đủ
        const size_t press = p - 2;
        d.pdata = (uint16_t)(_hist[press] | (_hist[press + 1] << 8));

        const size_t piezo = p - 52;
        int16_t peak = 0;
        for (int i = 0; i < 25; i++) {
            const int16_t sample =
                (int16_t)(_hist[piezo + i * 2] | (_hist[piezo + i * 2 + 1] << 8));
            const int16_t mag = sample < 0 ? (int16_t)-sample : sample;
            if (mag > peak) peak = mag;
        }
        d.sdata = (uint16_t)peak;
    }

    if (onSecData) onSecData(d);
    _histLen = 0;
}
