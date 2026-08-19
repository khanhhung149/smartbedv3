#include "sleep_pad_parser.h"
#include <string.h>
#include <esp_log.h>

#define TAG "SLEEP_PAD_PARSER"
#define FRAME_HEADER 0x7D
#define FRAME_END    0x0D
#define MAX_BUF      256

struct SleepPadParser {
    ParserState state;
    uint8_t buf[MAX_BUF];
    size_t len;
    void (*on_sec_data)(const SleepPadSecData*);
    void (*on_min_data)(const SleepPadMinData*);
    void (*on_idle)(void);
};

SleepPadParser* sleep_pad_parser_create(void) {
    SleepPadParser* parser = (SleepPadParser*)malloc(sizeof(SleepPadParser));
    if (parser == NULL) {
        ESP_LOGE(TAG, "Failed to allocate parser");
        return NULL;
    }
    memset(parser, 0, sizeof(SleepPadParser));
    parser->state = PARSER_STATE_WAIT_HEADER;
    return parser;
}

void sleep_pad_parser_destroy(SleepPadParser* parser) {
    if (parser != NULL) {
        free(parser);
    }
}

void sleep_pad_parser_set_callbacks(SleepPadParser* parser,
                                   void (*on_sec_data)(const SleepPadSecData*),
                                   void (*on_min_data)(const SleepPadMinData*),
                                   void (*on_idle)(void)) {
    if (parser == NULL) return;
    parser->on_sec_data = on_sec_data;
    parser->on_min_data = on_min_data;
    parser->on_idle = on_idle;
}

static void process_frame(SleepPadParser* parser) {
    // Minimum frame: header(1) + type(1) + length(2) + id(10) + content(>=1) + end(1) = 16
    if (parser->len < 16) {
        ESP_LOGW(TAG, "Frame too short: %u bytes", parser->len);
        return;
    }
    if (parser->buf[0] != FRAME_HEADER || parser->buf[parser->len - 1] != FRAME_END) {
        ESP_LOGW(TAG, "Invalid frame boundaries");
        return;
    }

    uint8_t frame_type = parser->buf[1];

    // Content starts at byte index 14 (header+type+length(2)+id(10)) and ends before 0x0D
    const uint8_t* content     = &parser->buf[14];
    size_t         content_len = parser->len - 14 - 1; // subtract trailing 0x0D

    if (frame_type == 0x85) {
        if (content_len != 12) {
            ESP_LOGW(TAG, "0x85 bad content len: %u (expected 12)", content_len);
            return;
        }
        SleepPadSecData d;
        d.serial     = content[0];
        d.timestamp  = (uint32_t)content[1] | ((uint32_t)content[2] << 8) | ((uint32_t)content[3] << 16) | ((uint32_t)content[4] << 24);
        d.status     = content[5];
        d.heart_rate = content[6];
        d.resp_rate  = content[7] / 10.0f;
        d.sdata      = (uint16_t)content[8] | ((uint16_t)content[9] << 8);
        d.pdata      = (uint16_t)content[10] | ((uint16_t)content[11] << 8);

        if (parser->on_sec_data) parser->on_sec_data(&d);
    } else if (frame_type == 0x86) {
        if (content_len != 15) {
            ESP_LOGW(TAG, "0x86 bad content len: %u (expected 15)", content_len);
            return;
        }
        SleepPadMinData d;
        d.serial        = content[0];
        d.timestamp     = (uint32_t)content[1] | ((uint32_t)content[2] << 8) | ((uint32_t)content[3] << 16) | ((uint32_t)content[4] << 24);
        d.status        = content[5];
        d.heart_rate    = content[6];
        d.resp_rate     = content[7] / 10.0f;
        d.movement      = content[8];
        d.snore_count   = content[9];
        d.resp_disorder = content[10];
        d.pthd          = (uint16_t)content[11] | ((uint16_t)content[12] << 8);
        d.temp          = (uint16_t)content[13] | ((uint16_t)content[14] << 8);

        if (parser->on_min_data) parser->on_min_data(&d);
    } else if (frame_type == 0x87) {
        // Device idle — requesting server commands (time cal, work mode, etc.)
        ESP_LOGI(TAG, "0x87 device idle, requesting commands");
        if (parser->on_idle) parser->on_idle();
    } else {
        ESP_LOGI(TAG, "Frame type: 0x%02X", frame_type);
    }
}

void sleep_pad_parser_feed(SleepPadParser* parser, uint8_t byte) {
    if (parser == NULL) return;

    switch (parser->state) {
        case PARSER_STATE_WAIT_HEADER:
            if (byte == FRAME_HEADER) {
                parser->buf[0] = byte;
                parser->len = 1;
                parser->state = PARSER_STATE_READ_FRAME;
            }
            break;

        case PARSER_STATE_READ_FRAME: {
            if (parser->len >= MAX_BUF) {
                parser->len = 0;
                parser->state = PARSER_STATE_WAIT_HEADER;
                return;
            }
            parser->buf[parser->len++] = byte;

            // CRITICAL: use the 2-byte length field (bytes 2-3) as the
            // authoritative frame boundary, NOT the 0x0D tail byte.  Any
            // content byte can legitimately equal 0x0D (e.g. sdata=13,
            // movement=13) — terminating on it mis-parses valid frames.
            if (parser->len >= 4) {
                const uint16_t expected_total =
                    (uint16_t)parser->buf[2] | ((uint16_t)parser->buf[3] << 8);
                if (expected_total < 16 || expected_total > MAX_BUF) {
                    // Bad length — resync.
                    parser->len = 0;
                    parser->state = PARSER_STATE_WAIT_HEADER;
                    return;
                }
                if (parser->len == expected_total) {
                    process_frame(parser);
                    parser->len = 0;
                    parser->state = PARSER_STATE_WAIT_HEADER;
                }
            }
            break;
        }

        default:
            parser->state = PARSER_STATE_WAIT_HEADER;
            break;
    }
}

const char* sleep_pad_parser_status_to_string(uint8_t code) {
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
