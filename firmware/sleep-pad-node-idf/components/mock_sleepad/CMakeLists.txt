idf_component_register(SRCS "mock_sleepad.c"
                    INCLUDE_DIRS "include"
                    REQUIRES esp_timer sleep_pad mqtt_wifi)
