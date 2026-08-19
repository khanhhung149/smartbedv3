#ifndef SLEEP_PAD_READER_H
#define SLEEP_PAD_READER_H

#include <stdint.h>
#include <stdbool.h>

// Initialize sleep pad reader (mock or real UART)
void sleep_pad_reader_init(const char* device_id, bool is_mock);

// Task function for sleep pad handling
void sleep_pad_task(void *arg);

#endif // SLEEP_PAD_READER_H