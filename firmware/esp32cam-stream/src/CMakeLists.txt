# REQUIRES cố ý KHÔNG khai component lưu trữ nào (thẻ nhớ, hệ thống tệp, lớp VFS) —
# node này không có tầng lưu trữ, đó là điều kiện của hazard H-25. Thêm một component
# như vậy vào đây là cách dễ nhất để vô tình mở lại đường ghi đĩa.
idf_component_register(
    SRCS "main.c" "stream_handler.c"
    INCLUDE_DIRS "." "../include"
    REQUIRES esp32-camera nvs_flash esp_wifi esp_netif esp_event esp_http_server lwip
)
