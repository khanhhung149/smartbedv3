// MJPEG streaming qua HTTP.
//
// Định dạng multipart/x-mixed-replace là định dạng DUY NHẤT mà cv2.VideoCapture(url)
// đọc thẳng được, không cần client riêng. RTSP/WebRTC trên ESP32 cần thư viện nặng
// hơn nhiều và đã bị loại ở giai đoạn brainstorm. Xem
// plans/260814-1237-esp32cam-stream-mediapipe-poc/.
//
// KHÔNG ghi frame ra bất kỳ đâu: không thẻ nhớ, không hệ thống tệp, không mở tệp.
// Đó là điều kiện của hazard H-25 (docs/safety/hazard-analysis.md), được verify bằng
// một lệnh grep quét tên các API lưu trữ trong thư mục này — nên chính các comment ở
// đây cũng cố ý tránh viết ra những tên đó.

#include "stream_handler.h"

#include <stdio.h>
#include <string.h>

#include "esp_camera.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "stream";

// Hai HTTP server riêng, hai cổng, hai task — KHÔNG phải hai route trên cùng một
// server. esp_http_server xử lý request trong MỘT task; handler stream chạy vô hạn nên
// nó chiếm trọn task đó và mọi request khác nằm chờ vô thời hạn. Đo thật 14/08: lúc
// rảnh `GET /` trả trong 0.06s, lúc đang stream thì timeout hẳn.
//
// Đây cũng là cách ví dụ esp32-camera chính thức của Espressif làm. Chi phí là một
// task httpd nữa; đổi lại xem trình duyệt và chạy PoC cùng lúc không giẫm chân nhau.
#define INDEX_PORT 80
#define STREAM_PORT 81
#define STREAM_PORT_STR "81"

// Bao nhiêu lần esp_camera_fb_get() lỗi liên tiếp thì coi là camera hỏng thật, không
// phải trục trặc thoáng qua. 100 lần × 10ms ≈ 1 giây im lặng — đủ dài để bỏ qua một
// nhịp trục trặc, đủ ngắn để client biết mà kết nối lại.
#define MAX_CONSECUTIVE_FB_FAILURES 100

// Boundary phải khớp ba chỗ: Content-Type của response, chuỗi phân cách giữa các
// frame, và kỳ vọng của client. Lệch một ký tự là client treo mà không báo lỗi.
#define STREAM_BOUNDARY "frame"
static const char *STREAM_CONTENT_TYPE =
    "multipart/x-mixed-replace;boundary=" STREAM_BOUNDARY;
static const char *STREAM_PART_BOUNDARY = "\r\n--" STREAM_BOUNDARY "\r\n";
static const char *STREAM_PART_HEADER_FMT =
    "Content-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n";

// Trang kiểm tra bằng mắt. Cố ý tối giản — kiểm tra board có stream không, không phải
// giao diện sản phẩm. Nền tối để dễ nhìn khi thử trong phòng thiếu sáng.
//
// Ảnh trỏ sang cổng stream bằng đường dẫn tương đối theo host hiện tại, để trang này
// vẫn đúng dù board đổi IP.
static const char *INDEX_HTML =
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\">"
    "<title>esp32cam-stream</title>"
    "<style>body{margin:0;background:#111;display:flex;align-items:center;"
    "justify-content:center;height:100vh}img{max-width:100%;max-height:100vh}</style>"
    "</head><body><img id=\"v\">"
    "<script>document.getElementById('v').src="
    "'http://'+location.hostname+':" STREAM_PORT_STR "/stream';</script>"
    "</body></html>";

static esp_err_t index_handler(httpd_req_t *req) {
    httpd_resp_set_type(req, "text/html");
    return httpd_resp_send(req, INDEX_HTML, HTTPD_RESP_USE_STRLEN);
}

static esp_err_t stream_handler(httpd_req_t *req) {
    esp_err_t res = httpd_resp_set_type(req, STREAM_CONTENT_TYPE);
    if (res != ESP_OK) {
        return res;
    }
    // Cho phép mở stream từ trang khác (ví dụ notebook chạy ở localhost). Không phải
    // biện pháp bảo mật — stream này vốn không có xác thực, xem H-25.
    httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");

    ESP_LOGI(TAG, "Client bắt đầu xem stream");

    int64_t started_us = esp_timer_get_time();
    uint32_t frames_sent = 0;
    uint32_t frames_dropped = 0;

    uint32_t consecutive_failures = 0;

    while (true) {
        camera_fb_t *fb = esp_camera_fb_get();
        if (fb == NULL) {
            // Một frame lỗi không phải lý do để cắt stream — driver thường lấy lại
            // được ở lần sau. Đếm và đi tiếp; con số này in ra lúc client ngắt.
            frames_dropped++;
            consecutive_failures++;

            // Nhường CPU trước khi thử lại. Thiếu dòng này thì camera hỏng biến vòng
            // lặp thành vòng quay tít: task watchdog kích và log ngập, che mất
            // nguyên nhân thật.
            vTaskDelay(pdMS_TO_TICKS(10));

            if (consecutive_failures >= MAX_CONSECUTIVE_FB_FAILURES) {
                // Hỏng dai dẳng, không phải trục trặc thoáng qua. Đóng stream để
                // client thấy lỗi và thử kết nối lại, thay vì ngồi nhìn khung hình
                // đứng im tưởng mọi thứ vẫn bình thường.
                ESP_LOGE(TAG, "esp_camera_fb_get() lỗi %u lần liên tiếp — đóng stream",
                         (unsigned)consecutive_failures);
                break;
            }
            if (consecutive_failures == 1) {
                ESP_LOGW(TAG, "esp_camera_fb_get() trả NULL, bỏ frame");
            }
            continue;
        }
        consecutive_failures = 0;

        char part_header[64];
        int header_len =
            snprintf(part_header, sizeof(part_header), STREAM_PART_HEADER_FMT,
                     (unsigned)fb->len);

        // Ba chunk cho mỗi frame: ranh giới, header, dữ liệu JPEG. Bất kỳ chunk nào
        // lỗi đều nghĩa là client đã ngắt — trả buffer rồi thoát vòng, KHÔNG cố gửi
        // tiếp (cố gửi tiếp là cách làm treo httpd task).
        res = httpd_resp_send_chunk(req, STREAM_PART_BOUNDARY,
                                    strlen(STREAM_PART_BOUNDARY));
        if (res == ESP_OK) {
            res = httpd_resp_send_chunk(req, part_header, header_len);
        }
        if (res == ESP_OK) {
            res = httpd_resp_send_chunk(req, (const char *)fb->buf, fb->len);
        }

        // Trả frame buffer về driver NGAY, kể cả khi gửi lỗi. Quên bước này thì sau
        // fb_count lần lặp esp_camera_fb_get() sẽ chặn vĩnh viễn.
        esp_camera_fb_return(fb);

        if (res != ESP_OK) {
            break;
        }
        frames_sent++;
    }

    int64_t elapsed_us = esp_timer_get_time() - started_us;
    float elapsed_s = (float)elapsed_us / 1000000.0f;
    ESP_LOGI(TAG,
             "Client ngắt sau %.1fs — %u frame đã gửi (%.1f fps), %u frame bỏ",
             elapsed_s, (unsigned)frames_sent,
             elapsed_s > 0.0f ? (float)frames_sent / elapsed_s : 0.0f,
             (unsigned)frames_dropped);

    // Chunk rỗng đóng response đúng cách. Nếu client đã đi rồi thì lệnh này lỗi —
    // không sao, chỉ để httpd dọn dẹp sạch.
    httpd_resp_send_chunk(req, NULL, 0);
    return ESP_OK;
}

esp_err_t start_webserver(void) {
    httpd_handle_t index_server = NULL;
    httpd_handle_t stream_server = NULL;

    httpd_config_t index_config = HTTPD_DEFAULT_CONFIG();
    index_config.server_port = INDEX_PORT;
    // Cổng điều khiển nội bộ phải khác nhau giữa hai instance, nếu không instance thứ
    // hai không khởi động được.
    index_config.ctrl_port = INDEX_PORT + 1000;

    esp_err_t err = httpd_start(&index_server, &index_config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "httpd_start cổng %d thất bại (0x%x)", INDEX_PORT, err);
        return err;
    }

    httpd_uri_t index_uri = {
        .uri = "/",
        .method = HTTP_GET,
        .handler = index_handler,
        .user_ctx = NULL,
    };
    httpd_register_uri_handler(index_server, &index_uri);

    httpd_config_t stream_config = HTTPD_DEFAULT_CONFIG();
    stream_config.server_port = STREAM_PORT;
    stream_config.ctrl_port = STREAM_PORT + 1000;
    // Kéo frame VGA từ PSRAM và gọi driver camera ngay trong stack của httpd task —
    // mặc định 4096 quá sát.
    stream_config.stack_size = 8192;
    // Một client stream tại một thời điểm. Server này vẫn xử lý tuần tự trong một
    // task; nhiều socket chỉ tạo ra hàng đợi chờ vô ích chứ không cho xem song song.
    stream_config.max_open_sockets = 2;
    // Không lru_purge_enable: đóng socket cũ giữa chừng làm PoC mất stream mà không
    // rõ vì sao. Thà từ chối kết nối mới còn hơn cắt kết nối đang chạy.

    err = httpd_start(&stream_server, &stream_config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "httpd_start cổng %d thất bại (0x%x)", STREAM_PORT, err);
        httpd_stop(index_server);
        return err;
    }

    httpd_uri_t stream_uri = {
        .uri = "/stream",
        .method = HTTP_GET,
        .handler = stream_handler,
        .user_ctx = NULL,
    };
    httpd_register_uri_handler(stream_server, &stream_uri);

    ESP_LOGI(TAG, "HTTP server đã lên: cổng %d GET /  |  cổng %d GET /stream",
             INDEX_PORT, STREAM_PORT);
    return ESP_OK;
}
