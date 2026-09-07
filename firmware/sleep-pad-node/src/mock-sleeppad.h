#pragma once
#include <stdint.h>

// Mock sleep-pad telemetry generator — compile-flag gated (MOCK_SLEEPPAD).
// Synthesizes raw Legact Pro V2 binary frames (0x85 per second, 0x86 per
// minute) so ESP32-C3 can smoke-test the full pipeline without physical hardware.
// Bytes are emitted through a caller-supplied feed callback so the existing
// SleepPadParser state machine is exercised end-to-end.

typedef enum {
    MOCK_SCENARIO_NORMAL_SLEEP,    // 0:00-2:00 HR~60, status SLEEP
    MOCK_SCENARIO_MOVEMENT_SPIKE,  // 2:00-3:00 movement 10+, snore 3-5, resp_disorder 1-2
    MOCK_SCENARIO_ALERT_TRIGGER,   // 3:00-4:00 HR 130-140, WEAK_BREATHING 30%, resp_disorder 6-10
    MOCK_SCENARIO_OFFLINE,         // 4:00-5:10 no publish (Redis TTL expires downstream)
} MockScenario;

// Call once from app_main(). Caches device_id (10 ASCII chars, no null), seeds
// RNG, and starts the scenario timer.
void mock_init(const char* device_id);

// Call from main loop every iteration. Emits sec frame every 1000 ms and min
// frame every 60000 ms (unless scenario is Offline). Non-blocking — returns
// immediately when nothing is due.
void mock_tick(void (*feed_byte)(uint8_t));
