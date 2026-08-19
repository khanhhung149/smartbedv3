#pragma once

// SLEEPPAD_UART is a token-only macro substituted at call sites (main.cpp),
// so this header doesn't need Arduino.h itself — including it here would just
// pull HardwareSerial transitively via the call-site translation unit.

// WiFi credentials managed by BLE provisioning + NVS — no hardcoded SSID/password.

// UART pins for sleep pad (Legact Pro V2)
//
// Per-target defaults: ESP32 classic uses Serial2 (GPIO 16 RX / 17 TX — its
// native UART2 pads). ESP32-C3 has only Serial0 (USB CDC) + Serial1, and lacks
// GPIO 16/17 entirely, so we remap to GPIO 20/21 (free pads on the C3
// Super Mini, away from USB D±/strapping pins).
#if CONFIG_IDF_TARGET_ESP32C3
  #define UART_RX_PIN     20
  #define UART_TX_PIN     21
  #define SLEEPPAD_UART   Serial1
#else
  #define UART_RX_PIN     16
  #define UART_TX_PIN     17
  #define SLEEPPAD_UART   Serial2
#endif

#define UART_BAUD       115200

// Web server (legacy WiFiManager flow — unused after BLE provisioning landed)
#define WEB_SERVER_PORT 80
