#pragma once
#include <stdint.h>
#include <stddef.h>

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
    PARSER_WAIT_HEADER,
    PARSER_READ_FRAME,
} ParserState;

#define UART_PARSER_MAX_BUF 64
#define UART_PARSER_TAOS_HIST 200
#define UART_PARSER_TAOS_KEEP 80

typedef struct SleepPadParser {
    // Feed one byte at a time from sleep pad UART (khung 0x7D).
    // Callbacks — set trước khi gọi feed()/feedTaos().
    void (*onSecData)(const SleepPadSecData*);
    void (*onMinData)(const SleepPadMinData*);
    // 0x84 (mode confirmed) — pad tự phát khi lệnh 0x04 áp dụng xong.
    void (*onModeConfirmed)(uint8_t mode);
    // 0x87 — pad tự phát báo idle/trạng thái (async, KHÔNG phải reply cho lệnh 0x07 —
    // xem plan 260824-1109: pad không bao giờ trả lời kiểu request/reply).
    void (*onStatusQuery)(uint8_t mode);

    ParserState _state;
    uint8_t     _buf[UART_PARSER_MAX_BUF];
    size_t      _len;

    // Lịch sử byte cho feedTaos: cần 57 byte TRƯỚC tag [Bdata] để lấy pdata/sdata,
    // cộng 5 byte tag và 4 byte kết quả.
    uint8_t _hist[UART_PARSER_TAOS_HIST];
    size_t  _histLen;
} SleepPadParser;

void sleeppad_parser_init(SleepPadParser* p);
void sleeppad_parser_feed(SleepPadParser* p, uint8_t byte);

// Đường LSM-800-T: pad không dùng khung 0x7D mà phát khối 66 byte
//   [Odata] + 25×int16 áp điện + 2 byte áp lực + [Bdata] + 4 byte kết quả
// sau khi nhận lệnh ASCII "TAOSG". Quét tag [Bdata] ở vị trí bất kỳ trong dòng byte
// thay vì bám tổng độ dài, nên không vỡ khi UART cắt/ghép gói. Chạy song song với
// sleeppad_parser_feed(): hai giao thức không đụng nhau vì máy trạng thái 0x7D bỏ qua
// mọi byte không phải header.
void sleeppad_parser_feed_taos(SleepPadParser* p, uint8_t byte);

// Map status byte to human-readable string
const char* sleeppad_status_to_string(uint8_t code);
