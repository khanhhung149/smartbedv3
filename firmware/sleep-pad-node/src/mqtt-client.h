#pragma once
#include <Arduino.h>
#include "uart-parser.h"

// MQTT client wrapper around ESP-IDF esp_mqtt_client (built into arduino-esp32 3.x).
// Handles: connect over TCP / WS / WSS, LWT, online status publish,
// JSON payload publish for sec/min frames, and auto-reconnect (driver task).
//
// WSS uses the bundled Mozilla CA store via esp_crt_bundle_attach, which
// validates Cloudflare-issued certs for *.sleeptech.me out of the box.

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
bool mqtt_connect();

// Must be called in loop() — drives PubSubClient internal state machine
// and triggers reconnect if connection dropped.
void mqtt_loop();

// Publish 0x85 per-second data as JSON to sleeppad/{device_id}/sec
void mqtt_publish_sec(const SleepPadSecData& d);

// Publish 0x86 per-minute data as JSON to sleeppad/{device_id}/min
void mqtt_publish_min(const SleepPadMinData& d);

// Returns true if PubSubClient is currently connected to broker.
bool mqtt_connected();
