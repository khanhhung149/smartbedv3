#include "mock-sleeppad.h"
#include <string.h>

// Scenario boundaries (ms since cycle start). See phase-01-firmware-mock.md.
static constexpr uint32_t T_NORMAL_END   = 120000UL;  // 0:00 - 2:00
static constexpr uint32_t T_MOVEMENT_END = 180000UL;  // 2:00 - 3:00
static constexpr uint32_t T_ALERT_END    = 240000UL;  // 3:00 - 4:00
static constexpr uint32_t T_CYCLE_TOTAL  = 310000UL;  // Offline ends at 5:10

static char     s_device_id[11] = {0};  // 10 ASCII + null
static uint32_t s_start_ms      = 0;
static uint32_t s_next_sec_ms   = 0;
static uint32_t s_next_min_ms   = 0;
static uint8_t  s_hr            = 60;     // HR baseline starts low
static uint8_t  s_rr_x10        = 140;    // 14.0 rpm (protocol stores rr*10 as uint8)
static uint8_t  s_serial        = 0;

// --- Scenario detection with automatic cycle wrap ---

static MockScenario current_scenario() {
    uint32_t elapsed = millis() - s_start_ms;
    if (elapsed >= T_CYCLE_TOTAL) {
        // Wrap: start a fresh cycle from NormalSleep
        s_start_ms = millis();
        elapsed    = 0;
    }
    if (elapsed < T_NORMAL_END)   return MockScenario::NormalSleep;
    if (elapsed < T_MOVEMENT_END) return MockScenario::MovementSpike;
    if (elapsed < T_ALERT_END)    return MockScenario::AlertTrigger;
    return MockScenario::Offline;
}

// --- Random walks (clamped so values stay realistic) ---

static uint8_t walk_hr(MockScenario s) {
    int delta;
    int lo, hi;
    if (s == MockScenario::AlertTrigger) {
        delta = (int)random(0, 11) - 5;  // -5..+5
        lo = 128; hi = 145;              // sustained high for alert engine
    } else {
        delta = (int)random(0, 7) - 3;   // -3..+3
        lo = 55;  hi = 72;               // normal-sleep range
    }
    int next = (int)s_hr + delta;
    if (next < lo) next = lo;
    if (next > hi) next = hi;
    s_hr = (uint8_t)next;
    return s_hr;
}

static uint8_t walk_rr_x10() {
    int delta = (int)random(0, 3) - 1;   // -1..+1 (in tenths = narrow walk)
    int next  = (int)s_rr_x10 + delta;
    if (next < 120) next = 120;          // 12.0 rpm floor
    if (next > 165) next = 165;          // 16.5 rpm ceiling
    s_rr_x10 = (uint8_t)next;
    return s_rr_x10;
}

// Weighted status sampling per scenario — matches plan spec.
static uint8_t pick_status(MockScenario s) {
    uint32_t r = random(0, 100);
    switch (s) {
        case MockScenario::NormalSleep:
            return (r < 90) ? 0x04 : 0x02;  // SLEEP 90% / MOVEMENT 10%
        case MockScenario::MovementSpike:
            return (r < 70) ? 0x02 : 0x04;  // MOVEMENT 70% / SLEEP 30%
        case MockScenario::AlertTrigger:
            if (r < 30) return 0x08;        // WEAK_BREATHING 30%
            if (r < 70) return 0x02;        // MOVEMENT 40%
            return 0x04;                    // SLEEP 30%
        default:
            return 0x04;
    }
}

// --- Frame builders ---

// Emit 14-byte frame preamble: [0x7D][type][len_lo][len_hi][10B device_id].
static void emit_preamble(void (*feed)(uint8_t), uint8_t frame_type, uint16_t total_len) {
    feed(0x7D);
    feed(frame_type);
    feed((uint8_t)(total_len & 0xFF));
    feed((uint8_t)((total_len >> 8) & 0xFF));
    for (int i = 0; i < 10; i++) feed((uint8_t)s_device_id[i]);
}

static void emit_sec_frame(void (*feed)(uint8_t)) {
    MockScenario s = current_scenario();
    uint8_t hr     = walk_hr(s);
    uint8_t rr10   = walk_rr_x10();
    uint8_t status = pick_status(s);
    uint32_t ts    = millis() / 1000;
    uint16_t sdata = 5 + (uint16_t)random(0, 15);
    uint16_t pdata = 5 + (uint16_t)random(0, 15);

    // Total = header(1)+type(1)+len(2)+id(10)+content(12)+end(1) = 27
    emit_preamble(feed, 0x85, 27);
    feed(++s_serial);
    feed((uint8_t)(ts & 0xFF));
    feed((uint8_t)((ts >> 8) & 0xFF));
    feed((uint8_t)((ts >> 16) & 0xFF));
    feed((uint8_t)((ts >> 24) & 0xFF));
    feed(status);
    feed(hr);
    feed(rr10);
    feed((uint8_t)(sdata & 0xFF));
    feed((uint8_t)((sdata >> 8) & 0xFF));
    feed((uint8_t)(pdata & 0xFF));
    feed((uint8_t)((pdata >> 8) & 0xFF));
    feed(0x0D);
}

static void emit_min_frame(void (*feed)(uint8_t)) {
    MockScenario s = current_scenario();
    uint8_t hr     = walk_hr(s);
    uint8_t rr10   = walk_rr_x10();
    uint8_t status = pick_status(s);
    uint32_t ts    = millis() / 1000;

    uint8_t movement, snore_count, resp_disorder;
    switch (s) {
        case MockScenario::MovementSpike:
            movement      = 10 + (uint8_t)random(0, 6);
            snore_count   = 3  + (uint8_t)random(0, 3);
            resp_disorder = 1  + (uint8_t)random(0, 2);
            break;
        case MockScenario::AlertTrigger:
            movement      = 2  + (uint8_t)random(0, 3);
            snore_count   = (uint8_t)random(0, 3);
            resp_disorder = 6  + (uint8_t)random(0, 5);
            break;
        default:  // NormalSleep (Offline never reaches here — gated in tick)
            movement      = (uint8_t)random(0, 3);
            snore_count   = 0;
            resp_disorder = 0;
            break;
    }
    uint16_t pthd = 5   + (uint16_t)random(0, 10);
    uint16_t temp = 365 + (uint16_t)random(0, 15);  // stored as C×10 → 36.5–38.0

    // Total = 1+1+2+10+15+1 = 30
    emit_preamble(feed, 0x86, 30);
    feed(++s_serial);
    feed((uint8_t)(ts & 0xFF));
    feed((uint8_t)((ts >> 8) & 0xFF));
    feed((uint8_t)((ts >> 16) & 0xFF));
    feed((uint8_t)((ts >> 24) & 0xFF));
    feed(status);
    feed(hr);
    feed(rr10);
    feed(movement);
    feed(snore_count);
    feed(resp_disorder);
    feed((uint8_t)(pthd & 0xFF));
    feed((uint8_t)((pthd >> 8) & 0xFF));
    feed((uint8_t)(temp & 0xFF));
    feed((uint8_t)((temp >> 8) & 0xFF));
    feed(0x0D);
}

// --- Public API ---

void mock_init(const char* device_id) {
    memcpy(s_device_id, device_id, 10);
    s_device_id[10] = '\0';
    s_start_ms    = millis();
    s_next_sec_ms = s_start_ms;
    s_next_min_ms = s_start_ms + 1000;  // first min frame 1s after first sec frame
    s_hr          = 60;
    s_rr_x10      = 140;
    s_serial      = 0;
    randomSeed(micros());
}

void mock_tick(void (*feed_byte)(uint8_t)) {
    uint32_t now = millis();

    // Offline scenario: stop publishing. Redis `device:{id}:online` TTL
    // (70s) will expire downstream so the app shows offline — we don't
    // need to also kill the MQTT TCP connection.
    //
    // Fast-forward the schedule while idle so the scenario-exit transition
    // does NOT emit a 70-second backlog of frames in one burst (which would
    // spam MQTT + spuriously trip the alert engine on every cycle wrap).
    if (current_scenario() == MockScenario::Offline) {
        s_next_sec_ms = now + 1000;
        s_next_min_ms = now + 60000;
        return;
    }

    // Signed compare so uint32_t wrap-around (after 49 days uptime) is safe.
    if ((int32_t)(now - s_next_sec_ms) >= 0) {
        emit_sec_frame(feed_byte);
        s_next_sec_ms += 1000;
    }
    if ((int32_t)(now - s_next_min_ms) >= 0) {
        emit_min_frame(feed_byte);
        s_next_min_ms += 60000;
    }
}
