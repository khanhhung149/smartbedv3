idf_component_register(SRCS "sleep_pad_reader.c" "sleep_pad_parser.c"
                    INCLUDE_DIRS "include"
                    REQUIRES esp_timer mock_sleepad mqtt_wifi driver config_parameter)
