#pragma once
#include <stdbool.h>
#include "uart-parser.h"

// MQTT client wrapper around ESP-IDF esp-mqtt (esp_mqtt_client_*, component "mqtt").
// Handles: connect over TCP / WS / WSS, LWT, online status publish,
// JSON payload publish for sec/min frames, and auto-reconnect (driver task).

// Initialise client with connection parameters. Does NOT connect yet.
// device_id : e.g. "CNU2000001" — used as MQTT client_id (required for ACL)
// host      : hostname or IP, optionally with port suffix "host:port"
// scheme    : "tcp" | "ws" | "wss" | "mqtts"
// user/pass : empty string = anonymous connect (dev broker)
void mqtt_setup(const char* device_id,
                const char* host,
                const char* scheme,
                const char* user,
                const char* pass);

// Attempt MQTT connect (blocking, one attempt).
// Returns true on success. Caller should retry with backoff if false.
bool mqtt_connect(void);

// Must be called from the main loop — drains the ring buffer of pending
// publishes into the broker once connected (esp-mqtt itself runs its own
// FreeRTOS task for the wire protocol, this only handles our app-level queue).
void mqtt_loop(void);

// Publish 0x85 per-second data as JSON to sleeppad/{device_id}/sec
void mqtt_publish_sec(const SleepPadSecData* d);

// Publish 0x86 per-minute data as JSON to sleeppad/{device_id}/min
void mqtt_publish_min(const SleepPadMinData* d);

// Returns true if esp-mqtt is currently connected to the broker.
bool mqtt_connected(void);
