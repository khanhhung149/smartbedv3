#ifndef MOCK_SLEEPAD_H
#define MOCK_SLEEPAD_H

#include <stdint.h>

typedef enum {
    MOCK_SLEEPAD_SCENARIO_NORMAL_SLEEP,
    MOCK_SLEEPAD_SCENARIO_MOVEMENT_SPIKE,
    MOCK_SLEEPAD_SCENARIO_ALERT_TRIGGER,
    MOCK_SLEEPAD_SCENARIO_OFFLINE,
} mock_sleepad_scenario_t;

void mock_sleepad_init(const char* device_id);
void mock_sleepad_tick(void (*feed_byte)(uint8_t));

#endif
