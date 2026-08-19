#include "net.h"

#include <string.h>
#include <sys/time.h>

#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "mdns.h"

static const char *TAG = "net";

// Chờ trước khi thử nối lại. Nối lại ngay lập tức sẽ quay vòng nghẽn log khi router tắt.
#define WIFI_RETRY_MS 2000

static volatile bool s_has_ip;
static bool          s_mdns_up;
static char          s_hostname[32];
static esp_timer_handle_t s_retry_timer;

static void retry_connect(void *arg) { esp_wifi_connect(); }

static void on_wifi_event(void *arg, esp_event_base_t base, int32_t id, void *data) {
  if (id == WIFI_EVENT_STA_START) {
    esp_wifi_connect();
    return;
  }
  if (id == WIFI_EVENT_STA_DISCONNECTED) {
    s_has_ip = false;
    const wifi_event_sta_disconnected_t *e = (const wifi_event_sta_disconnected_t *)data;
    ESP_LOGW(TAG, "WiFi rớt (reason=%d) — thử lại sau %dms", e->reason, WIFI_RETRY_MS);
    // Hẹn giờ thay vì delay: handler chạy trên task event loop chung, chặn ở đây là chặn cả
    // sự kiện IP/MQTT.
    esp_timer_start_once(s_retry_timer, WIFI_RETRY_MS * 1000);
  }
}

static void on_got_ip(void *arg, esp_event_base_t base, int32_t id, void *data) {
  const ip_event_got_ip_t *e = (const ip_event_got_ip_t *)data;
  ESP_LOGI(TAG, "WiFi OK — IP " IPSTR, IP2STR(&e->ip_info.ip));
  s_has_ip = true;

  // mDNS chỉ dựng một lần, sau khi có IP (dựng sớm hơn thì bản ghi không gắn được địa chỉ).
  if (!s_mdns_up && mdns_init() == ESP_OK) {
    mdns_hostname_set(s_hostname);
    mdns_instance_name_set(s_hostname);
    mdns_service_add(NULL, "_http", "_tcp", 80, NULL, 0);  // endpoint nạp OTA
    s_mdns_up = true;
    ESP_LOGI(TAG, "mDNS: %s.local", s_hostname);
  }
}

esp_err_t net_start(const char *ssid, const char *pass, const char *hostname,
                    const net_static_ip_t *static_ip) {
  strncpy(s_hostname, hostname, sizeof(s_hostname) - 1);

  ESP_ERROR_CHECK(esp_netif_init());
  ESP_ERROR_CHECK(esp_event_loop_create_default());
  esp_netif_t *sta = esp_netif_create_default_wifi_sta();
  esp_netif_set_hostname(sta, s_hostname);

  // IP tĩnh: phải tắt DHCP client TRƯỚC khi esp_wifi_start, nếu không nó vẫn phát DISCOVER và
  // ghi đè địa chỉ vừa đặt. Dùng khi mạng không có máy cấp DHCP dùng được.
  if (static_ip != NULL) {
    ESP_ERROR_CHECK(esp_netif_dhcpc_stop(sta));
    esp_netif_ip_info_t ip_info = {
        .ip      = {.addr = esp_ip4addr_aton(static_ip->ip)},
        .gw      = {.addr = esp_ip4addr_aton(static_ip->gw)},
        .netmask = {.addr = esp_ip4addr_aton(static_ip->mask)},
    };
    ESP_ERROR_CHECK(esp_netif_set_ip_info(sta, &ip_info));

    // Không có DHCP thì cũng không ai đưa máy chủ DNS. Chính là gateway trước (router LAN thường
    // kiêm luôn DNS), nhưng phải có đường lui: bộ chia sẻ mạng của Windows chỉ trả lời DNS cho
    // client có lease DHCP, mà đi IP tĩnh thì không có lease — thiếu backup là NTP không phân giải
    // được tên máy chủ, đồng hồ đứng ở 0 và presence không bao giờ được publish.
    esp_netif_dns_info_t dns = {.ip = {.type = ESP_IPADDR_TYPE_V4,
                                       .u_addr.ip4.addr = ip_info.gw.addr}};
    ESP_ERROR_CHECK(esp_netif_set_dns_info(sta, ESP_NETIF_DNS_MAIN, &dns));
    esp_netif_dns_info_t dns_backup = {.ip = {.type = ESP_IPADDR_TYPE_V4,
                                              .u_addr.ip4.addr = esp_ip4addr_aton("8.8.8.8")}};
    ESP_ERROR_CHECK(esp_netif_set_dns_info(sta, ESP_NETIF_DNS_BACKUP, &dns_backup));
    ESP_LOGI(TAG, "IP tĩnh: %s (gw %s)", static_ip->ip, static_ip->gw);
  }

  const esp_timer_create_args_t retry_args = {.callback = retry_connect, .name = "wifi_retry"};
  ESP_ERROR_CHECK(esp_timer_create(&retry_args, &s_retry_timer));

  ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi_event, NULL, NULL));
  ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, on_got_ip, NULL, NULL));

  const wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_wifi_init(&init));
  ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));

  wifi_config_t cfg = {0};
  strncpy((char *)cfg.sta.ssid, ssid, sizeof(cfg.sta.ssid) - 1);
  strncpy((char *)cfg.sta.password, pass, sizeof(cfg.sta.password) - 1);
  ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
  ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &cfg));
  ESP_ERROR_CHECK(esp_wifi_start());
  ESP_LOGI(TAG, "WiFi: nối %s", ssid);

  // UTC epoch cho trường ts của presence/motion. Cùng cặp máy chủ như bản Arduino trước.
  esp_sntp_config_t sntp = ESP_NETIF_SNTP_DEFAULT_CONFIG_MULTIPLE(
      2, ESP_SNTP_SERVER_LIST("pool.ntp.org", "time.google.com"));
  return esp_netif_sntp_init(&sntp);
}

bool net_has_ip(void) { return s_has_ip; }

uint64_t net_epoch_ms(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  if (tv.tv_sec < 100000) return 0;  // đồng hồ chưa được NTP đặt
  return (uint64_t)tv.tv_sec * 1000ULL + tv.tv_usec / 1000ULL;
}
