idf_component_register(SRCS "main.c"
                    INCLUDE_DIRS "."
                    REQUIRES
                        ble
                        connect_wifi
                        mock_sleepad
                        mqtt_wifi
                        sleep_pad
                        
                        config_parameter
                        )
