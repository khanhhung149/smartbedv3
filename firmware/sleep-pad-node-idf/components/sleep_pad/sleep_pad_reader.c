#include "sleep_pad_reader.h"
#include <string.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_log.h>
#include <driver/uart.h>

#include "mock_sleepad.h"
#include "mqtt_wifi.h"
#include "sleep_pad_parser.h"
#include "config_parameter.h"

// UART configuration
#define UART_NUM UART_NUM_1
#define UART_BAUD 115200
#define UART_RX_PIN 5 
#define UART_TX_PIN 6
#define BUF_SIZE 1024

static const char* s_device_id = NULL;
static bool s_is_mock = true;
static SleepPadParser* s_parser = NULL;

#ifdef MOCK_SLEEPPAD
// Mock mode functions
static void on_sec_data_mock(const SleepPadSecData* d) {
    char topic[64];
    char data[128];
    snprintf(topic, sizeof(topic), "sleeppad/%s/sec", s_device_id);
    snprintf(data, sizeof(data), "{\"device_id\":\"%s\",\"ts\":%lu,\"status\":%u,\"heart_rate\":%u,\"resp_rate\":%.1f,\"sdata\":%u,\"pdata\":%u}",
             s_device_id, d->timestamp, d->status, d->heart_rate, d->resp_rate, d->sdata, d->pdata);
    mqtt_publish_data(topic, data);
}

static void on_min_data_mock(const SleepPadMinData* d) {
    char topic[64];
    char data[256];
    snprintf(topic, sizeof(topic), "sleeppad/%s/min", s_device_id);
    snprintf(data, sizeof(data), "{\"device_id\":\"%s\",\"ts\":%lu,\"status\":%u,\"heart_rate\":%u,\"resp_rate\":%.1f,\"movement\":%u,\"snore_count\":%u,\"resp_disorder\":%u,\"pthd\":%u,\"temp\":%.1f}",
             s_device_id, d->timestamp, d->status, d->heart_rate, d->resp_rate, d->movement, d->snore_count, d->resp_disorder, d->pthd, d->temp / 10.0f);
    mqtt_publish_data(topic, data);
}

static void on_idle_mock(void) {
    ESP_LOGI("UART", "Idle frame received, restarting monitor mode");
}

static void feed_func(uint8_t byte) {
    if (s_parser != NULL) {
        sleep_pad_parser_feed(s_parser, byte);
    }
}
#endif

#ifndef MOCK_SLEEPPAD
// Real UART mode functions
static void on_sec_data_real(const SleepPadSecData* d) {
    char topic[64];
    char data[128];
    snprintf(topic, sizeof(topic), "sleeppad/%s/sec", s_device_id);
    snprintf(data, sizeof(data), "{\"device_id\":\"%s\",\"ts\":%lu,\"status\":%u,\"heart_rate\":%u,\"resp_rate\":%.1f,\"sdata\":%u,\"pdata\":%u}",
             s_device_id, d->timestamp, d->status, d->heart_rate, d->resp_rate, d->sdata, d->pdata);
    mqtt_publish_data(topic, data);
}

static void on_min_data_real(const SleepPadMinData* d) {
    char topic[64];
    char data[256];
    snprintf(topic, sizeof(topic), "sleeppad/%s/min", s_device_id);
    snprintf(data, sizeof(data), "{\"device_id\":\"%s\",\"ts\":%lu,\"status\":%u,\"heart_rate\":%u,\"resp_rate\":%.1f,\"movement\":%u,\"snore_count\":%u,\"resp_disorder\":%u,\"pthd\":%u,\"temp\":%.1f}",
             s_device_id, d->timestamp, d->status, d->heart_rate, d->resp_rate, d->movement, d->snore_count, d->resp_disorder, d->pthd, d->temp / 10.0f);
    mqtt_publish_data(topic, data);
}

static void on_idle_real() {
    ESP_LOGI("UART", "Idle frame received, restarting monitor mode");
    // TODO: Send start monitor command
}

static void send_command(uint8_t frame_type, const uint8_t* content, size_t len) {
    uint8_t buffer[256];
    size_t index = 0;
    buffer[index++] = 0x7D;
    buffer[index++] = frame_type;
    uint16_t total = 1 + 1 + 2 + 10 + len + 1;
    buffer[index++] = (uint8_t)(total & 0xFF);
    buffer[index++] = (uint8_t)((total >> 8) & 0xFF);
    memcpy(&buffer[index], s_device_id, 10);
    index += 10;
    if (len > 0) {
        memcpy(&buffer[index], content, len);
        index += len;
    }
    buffer[index++] = 0x0D;
    uart_write_bytes(UART_NUM, (const char*)buffer, index);
}

static void start_monitor_mode() {
    ESP_LOGI("CMD", "0x04 — start server monitor mode");
    uint8_t mode = 0x20;
    send_command(0x04, &mode, 1);
}
#endif

void sleep_pad_reader_init(const char* device_id, bool is_mock) {
    s_device_id = device_id;
    s_is_mock = is_mock;

    if (is_mock) {
#ifdef MOCK_SLEEPPAD
        mock_sleepad_init(device_id);
        s_parser = sleep_pad_parser_create();
        if (s_parser) {
            sleep_pad_parser_set_callbacks(s_parser, on_sec_data_mock, on_min_data_mock, on_idle_mock);
        }
        ESP_LOGI("SLEEP_PAD", "Mock mode initialized");
#endif
    } else {
#ifndef MOCK_SLEEPPAD
        // Initialize UART
        uart_config_t uart_config = {
            .baud_rate = UART_BAUD,
            .data_bits = UART_DATA_8_BITS,
            .parity = UART_PARITY_DISABLE,
            .stop_bits = UART_STOP_BITS_1,
            .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
            .source_clk = UART_SCLK_DEFAULT,
        };
        uart_driver_install(UART_NUM, BUF_SIZE * 2, 0, 0, NULL, 0);
        uart_param_config(UART_NUM, &uart_config);
        uart_set_pin(UART_NUM, UART_TX_PIN, UART_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);

        // Initialize parser
        s_parser = sleep_pad_parser_create();
        if (s_parser) {
            sleep_pad_parser_set_callbacks(s_parser, on_sec_data_real, on_min_data_real, on_idle_real);
        }
        ESP_LOGI("SLEEP_PAD", "Real UART mode initialized");
#endif
    }
}

void sleep_pad_task(void *arg) {
    while (!mqtt_connected) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    if (s_is_mock) {
#ifdef MOCK_SLEEPPAD
        while (1) {
            mock_sleepad_tick(feed_func);
            vTaskDelay(pdMS_TO_TICKS(2000));
        }
#endif
    } else {
#ifndef MOCK_SLEEPPAD
        // Start monitor mode
        start_monitor_mode();

        uint8_t data[BUF_SIZE];
        while (1) {
            int len = uart_read_bytes(UART_NUM, data, BUF_SIZE, pdMS_TO_TICKS(100));
            if (len > 0) {
                for (int i = 0; i < len; i++) {
                    sleep_pad_parser_feed(s_parser, data[i]);
                }
            }
            vTaskDelay(pdMS_TO_TICKS(10));
        }
#endif
    }
}