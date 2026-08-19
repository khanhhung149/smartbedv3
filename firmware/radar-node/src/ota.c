#include "ota.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_app_desc.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_ota_ops.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "ota";

#define OTA_CHUNK 4096

static const char *s_password = "";

// Nạp: POST /update, thân request là firmware.bin thô.
static esp_err_t update_post(httpd_req_t *req) {
  if (s_password[0] != '\0') {
    char given[64] = {0};
    if (httpd_req_get_hdr_value_str(req, "X-OTA-Password", given, sizeof(given)) != ESP_OK ||
        strcmp(given, s_password) != 0) {
      ESP_LOGW(TAG, "từ chối: sai mật khẩu");
      httpd_resp_send_err(req, HTTPD_401_UNAUTHORIZED, "sai mat khau OTA");
      return ESP_FAIL;
    }
  }
  if (req->content_len <= 0) {
    httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "thieu firmware");
    return ESP_FAIL;
  }

  const esp_partition_t *target = esp_ota_get_next_update_partition(NULL);
  if (target == NULL) {
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "khong co phan vung OTA");
    return ESP_FAIL;
  }
  ESP_LOGI(TAG, "nhận %d byte -> phân vùng %s", req->content_len, target->label);

  esp_ota_handle_t handle = 0;
  esp_err_t err = esp_ota_begin(target, req->content_len, &handle);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "esp_ota_begin: %s", esp_err_to_name(err));
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "khong mo duoc phan vung");
    return ESP_FAIL;
  }

  char  *buf = malloc(OTA_CHUNK);
  int    left = req->content_len;
  bool   ok = buf != NULL;
  while (ok && left > 0) {
    const int want = left < OTA_CHUNK ? left : OTA_CHUNK;
    const int got = httpd_req_recv(req, buf, want);
    if (got == HTTPD_SOCK_ERR_TIMEOUT) continue;  // mạng chậm, không phải lỗi
    if (got <= 0) {
      ESP_LOGE(TAG, "mất kết nối khi đang nhận (còn %d byte)", left);
      ok = false;
      break;
    }
    if (esp_ota_write(handle, buf, got) != ESP_OK) {
      ESP_LOGE(TAG, "ghi flash lỗi");
      ok = false;
      break;
    }
    left -= got;
  }
  free(buf);

  if (!ok) {
    esp_ota_abort(handle);
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "nap that bai - giu firmware cu");
    return ESP_FAIL;
  }

  err = esp_ota_end(handle);  // kiểm chữ ký/checksum ảnh; hỏng thì giữ nguyên firmware đang chạy
  if (err == ESP_OK) err = esp_ota_set_boot_partition(target);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "chốt ảnh lỗi: %s", esp_err_to_name(err));
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR, "anh firmware khong hop le");
    return ESP_FAIL;
  }

  httpd_resp_sendstr(req, "OK - khoi dong lai\n");
  ESP_LOGI(TAG, "xong — khởi động lại");
  vTaskDelay(pdMS_TO_TICKS(500));  // kịp đẩy nốt phản hồi cho máy nạp
  esp_restart();
  return ESP_OK;
}

// GET / — kiểm nhanh board còn sống và đang chạy bản nào.
static esp_err_t root_get(httpd_req_t *req) {
  const esp_app_desc_t *app = esp_app_get_description();
  char body[128];
  snprintf(body, sizeof(body), "radar-node %s (%s %s)\nPOST /update de nap firmware\n",
           app->version, app->date, app->time);
  httpd_resp_sendstr(req, body);
  return ESP_OK;
}

esp_err_t ota_http_start(const char *password) {
  s_password = password;

  httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
  cfg.stack_size       = 8192;   // esp_ota_write + đệm 4KB không vừa stack mặc định
  cfg.recv_wait_timeout = 10;    // firmware ~1MB qua WiFi yếu vẫn kịp
  cfg.send_wait_timeout = 10;
  cfg.lru_purge_enable  = true;

  httpd_handle_t server = NULL;
  esp_err_t err = httpd_start(&server, &cfg);
  if (err != ESP_OK) return err;

  const httpd_uri_t update = {.uri = "/update", .method = HTTP_POST, .handler = update_post};
  const httpd_uri_t root   = {.uri = "/",       .method = HTTP_GET,  .handler = root_get};
  httpd_register_uri_handler(server, &update);
  httpd_register_uri_handler(server, &root);
  ESP_LOGI(TAG, "sẵn sàng nhận firmware qua POST /update%s", password[0] ? "" : " (KHÔNG mật khẩu)");
  return ESP_OK;
}
