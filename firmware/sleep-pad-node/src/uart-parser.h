#pragma once
#include <Arduino.h>
// Per-second data (0x85 frame, 12 bytes content)
struct SleepPadSecData {
    uint8_t  serial;
    uint32_t timestamp;
    uint8_t  status;
    uint8_t  heart_rate;
    float    resp_rate;   // byte_value / 10.0
    uint16_t sdata;
    uint16_t pdata;
};

// Per-minute data (0x86 frame, 15 bytes content)
struct SleepPadMinData {
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
};

// Frame parser states
enum class ParserState : uint8_t {
    WAIT_HEADER,
    READ_FRAME,
    FRAME_COMPLETE
};

class SleepPadParser {
public:
    SleepPadParser();

    // Feed one byte at a time from Serial1
    void feed(uint8_t byte);

    // Đường LSM-800-T: pad không dùng khung 0x7D mà phát khối 66 byte
    //   [Odata] + 25×int16 áp điện + 2 byte áp lực + [Bdata] + 4 byte kết quả
    // sau khi nhận lệnh ASCII "TAOSG". Quét tag [Bdata] ở vị trí bất kỳ trong
    // dòng byte thay vì bám tổng độ dài, nên không vỡ khi UART cắt/ghép gói.
    // Chạy song song với feed(): hai giao thức không đụng nhau vì máy trạng thái
    // 0x7D bỏ qua mọi byte không phải header.
    void feedTaos(uint8_t byte);

    // Callbacks — set before calling feed()
    void (*onSecData)(const SleepPadSecData&);
    void (*onMinData)(const SleepPadMinData&);

    // Map status byte to human-readable string
    static const char* statusToString(uint8_t code);

    // Callback when device sends 0x87 (idle/standby, requesting commands)
    void (*onIdle)();

private:
    static constexpr uint8_t FRAME_HEADER = 0x7D;
    static constexpr uint8_t FRAME_END    = 0x0D;
    static constexpr size_t  MAX_BUF      = 64;

    ParserState _state;
    uint8_t     _buf[MAX_BUF];
    size_t      _len;

    // Lịch sử byte cho feedTaos: cần 57 byte TRƯỚC tag để lấy pdata/sdata,
    // cộng 5 byte tag và 4 byte kết quả.
    static constexpr size_t TAOS_HIST = 200;
    static constexpr size_t TAOS_KEEP = 80;
    uint8_t _hist[TAOS_HIST];
    size_t  _histLen;

    void processFrame();
    void decode0x85(const uint8_t* content, size_t content_len);
    void decode0x86(const uint8_t* content, size_t content_len);
};
