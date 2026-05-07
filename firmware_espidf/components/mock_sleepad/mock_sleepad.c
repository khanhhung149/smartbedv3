#include "mock_sleepad.h"
#include <string.h>
#include <esp_timer.h>
#include <esp_random.h>
#include <esp_system.h>
#include <stdint.h>

static const uint32_t T_NORMAL_END   = 120000U;
static const uint32_t T_MOVEMENT_END = 180000U;
static const uint32_t T_ALERT_END    = 240000U;
static const uint32_t T_CYCLE_TOTAL  = 310000U;

static char     s_device_id[11] = {0};
static uint32_t s_start_ms      = 0;
static uint32_t s_next_sec_ms   = 0;
static uint32_t s_next_min_ms   = 0;
static uint8_t  s_hr            = 60;
static uint8_t  s_rr_x10        = 140;
static uint8_t  s_serial        = 0;

static uint32_t mock_sleepad_now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000ULL);
}

static uint32_t mock_sleepad_rand(uint32_t min, uint32_t max)
{
    if (max <= min) {
        return min;
    }
    return min + (esp_random() % (max - min));
}

static mock_sleepad_scenario_t mock_sleepad_current_scenario(void)
{
    uint32_t elapsed = mock_sleepad_now_ms() - s_start_ms;
    if (elapsed >= T_CYCLE_TOTAL) {
        s_start_ms = mock_sleepad_now_ms();
        elapsed    = 0;
    }
    if (elapsed < T_NORMAL_END) {
        return MOCK_SLEEPAD_SCENARIO_NORMAL_SLEEP;
    }
    if (elapsed < T_MOVEMENT_END) {
        return MOCK_SLEEPAD_SCENARIO_MOVEMENT_SPIKE;
    }
    if (elapsed < T_ALERT_END) {
        return MOCK_SLEEPAD_SCENARIO_ALERT_TRIGGER;
    }
    return MOCK_SLEEPAD_SCENARIO_OFFLINE;
}

static uint8_t mock_sleepad_walk_hr(mock_sleepad_scenario_t scenario)
{
    int delta;
    int lo;
    int hi;
    if (scenario == MOCK_SLEEPAD_SCENARIO_ALERT_TRIGGER) {
        delta = (int)mock_sleepad_rand(0, 11) - 5;
        lo = 128;
        hi = 145;
    } else {
        delta = (int)mock_sleepad_rand(0, 7) - 3;
        lo = 55;
        hi = 72;
    }
    int next = (int)s_hr + delta;
    if (next < lo) next = lo;
    if (next > hi) next = hi;
    s_hr = (uint8_t)next;
    return s_hr;
}

static uint8_t mock_sleepad_walk_rr_x10(void)
{
    int next = (int)s_rr_x10 + ((int)mock_sleepad_rand(0, 3) - 1);
    if (next < 120) next = 120;
    if (next > 165) next = 165;
    s_rr_x10 = (uint8_t)next;
    return s_rr_x10;
}

static uint8_t mock_sleepad_pick_status(mock_sleepad_scenario_t scenario)
{
    uint32_t r = mock_sleepad_rand(0, 100);
    switch (scenario) {
        case MOCK_SLEEPAD_SCENARIO_NORMAL_SLEEP:
            return (r < 90) ? 0x04 : 0x02;
        case MOCK_SLEEPAD_SCENARIO_MOVEMENT_SPIKE:
            return (r < 70) ? 0x02 : 0x04;
        case MOCK_SLEEPAD_SCENARIO_ALERT_TRIGGER:
            if (r < 30) return 0x08;
            if (r < 70) return 0x02;
            return 0x04;
        default:
            return 0x04;
    }
}

static void mock_sleepad_emit_preamble(void (*feed)(uint8_t), uint8_t frame_type, uint16_t total_len)
{
    feed(0x7D);
    feed(frame_type);
    feed((uint8_t)(total_len & 0xFF));
    feed((uint8_t)((total_len >> 8) & 0xFF));
    for (int i = 0; i < 10; i++) {
        feed((uint8_t)s_device_id[i]);
    }
}

static void mock_sleepad_emit_sec_frame(void (*feed)(uint8_t))
{
    mock_sleepad_scenario_t scenario = mock_sleepad_current_scenario();
    uint8_t hr      = mock_sleepad_walk_hr(scenario);
    uint8_t rr10    = mock_sleepad_walk_rr_x10();
    uint8_t status  = mock_sleepad_pick_status(scenario);
    uint32_t ts     = mock_sleepad_now_ms() / 1000U;
    uint16_t sdata  = 5 + (uint16_t)mock_sleepad_rand(0, 15);
    uint16_t pdata  = 5 + (uint16_t)mock_sleepad_rand(0, 15);

    mock_sleepad_emit_preamble(feed, 0x85, 27);
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

static void mock_sleepad_emit_min_frame(void (*feed)(uint8_t))
{
    mock_sleepad_scenario_t scenario = mock_sleepad_current_scenario();
    uint8_t hr      = mock_sleepad_walk_hr(scenario);
    uint8_t rr10    = mock_sleepad_walk_rr_x10();
    uint8_t status  = mock_sleepad_pick_status(scenario);
    uint32_t ts     = mock_sleepad_now_ms() / 1000U;

    uint8_t movement;
    uint8_t snore_count;
    uint8_t resp_disorder;
    switch (scenario) {
        case MOCK_SLEEPAD_SCENARIO_MOVEMENT_SPIKE:
            movement      = 10 + (uint8_t)mock_sleepad_rand(0, 6);
            snore_count   = 3 + (uint8_t)mock_sleepad_rand(0, 3);
            resp_disorder = 1 + (uint8_t)mock_sleepad_rand(0, 2);
            break;
        case MOCK_SLEEPAD_SCENARIO_ALERT_TRIGGER:
            movement      = 2 + (uint8_t)mock_sleepad_rand(0, 3);
            snore_count   = (uint8_t)mock_sleepad_rand(0, 3);
            resp_disorder = 6 + (uint8_t)mock_sleepad_rand(0, 5);
            break;
        default:
            movement      = (uint8_t)mock_sleepad_rand(0, 3);
            snore_count   = 0;
            resp_disorder = 0;
            break;
    }
    uint16_t pthd = 5 + (uint16_t)mock_sleepad_rand(0, 10);
    uint16_t temp = 365 + (uint16_t)mock_sleepad_rand(0, 15);

    mock_sleepad_emit_preamble(feed, 0x86, 30);
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

void mock_sleepad_init(const char* device_id)
{
    memcpy(s_device_id, device_id, 10);
    s_device_id[10] = '\0';
    s_start_ms    = mock_sleepad_now_ms();
    s_next_sec_ms = s_start_ms;
    s_next_min_ms = s_start_ms + 1000U;
    s_hr          = 60;
    s_rr_x10      = 140;
    s_serial      = 0;
}

void mock_sleepad_tick(void (*feed_byte)(uint8_t))
{
    uint32_t now = mock_sleepad_now_ms();
    if (mock_sleepad_current_scenario() == MOCK_SLEEPAD_SCENARIO_OFFLINE) {
        s_next_sec_ms = now + 1000U;
        s_next_min_ms = now + 60000U;
        return;
    }

    if ((int32_t)(now - s_next_sec_ms) >= 0) {
        mock_sleepad_emit_sec_frame(feed_byte);
        s_next_sec_ms += 1000U;
    }
    if ((int32_t)(now - s_next_min_ms) >= 0) {
        mock_sleepad_emit_min_frame(feed_byte);
        s_next_min_ms += 60000U;
    }
}
