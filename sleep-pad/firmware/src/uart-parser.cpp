#include "uart-parser.h"

SleepPadParser::SleepPadParser()
    : onSecData(nullptr), onMinData(nullptr), onIdle(nullptr),
      _state(ParserState::WAIT_HEADER), _len(0) {}

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
