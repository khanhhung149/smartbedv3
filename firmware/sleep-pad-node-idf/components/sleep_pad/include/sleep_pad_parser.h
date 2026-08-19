#ifndef SLEEP_PAD_PARSER_H
#define SLEEP_PAD_PARSER_H

#include <stdint.h>

// Per-second data (0x85 frame, 12 bytes content)
typedef struct {
    uint8_t  serial;
    uint32_t timestamp;
    uint8_t  status;
    uint8_t  heart_rate;
    float    resp_rate;   // byte_value / 10.0
    uint16_t sdata;
    uint16_t pdata;
} SleepPadSecData;

// Per-minute data (0x86 frame, 15 bytes content)
typedef struct {
    uint8_t  serial;
    uint32_t timestamp;
    uint8_t  status;
    uint8_t  heart_rate;
    float    resp_rate;   // byte_value / 10.0
    uint8_t  movement;
    uint8_t  snore_count;
    uint8_t  resp_disorder;
    uint16_t pthd;
    uint16_t temp;
} SleepPadMinData;

// Frame parser states
typedef enum {
    PARSER_STATE_WAIT_HEADER,
    PARSER_STATE_READ_FRAME,
    PARSER_STATE_FRAME_COMPLETE
} ParserState;

typedef struct SleepPadParser SleepPadParser;

// Create a new parser instance
SleepPadParser* sleep_pad_parser_create(void);

// Destroy parser instance
void sleep_pad_parser_destroy(SleepPadParser* parser);

// Feed one byte at a time
void sleep_pad_parser_feed(SleepPadParser* parser, uint8_t byte);

// Set callbacks
void sleep_pad_parser_set_callbacks(SleepPadParser* parser,
                                   void (*on_sec_data)(const SleepPadSecData*),
                                   void (*on_min_data)(const SleepPadMinData*),
                                   void (*on_idle)(void));

// Map status byte to human-readable string
const char* sleep_pad_parser_status_to_string(uint8_t code);

#endif
