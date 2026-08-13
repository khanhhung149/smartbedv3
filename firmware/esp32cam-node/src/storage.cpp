#include "storage.h"

#include <cstdio>
#include <cstring>
#include <ctime>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

#include "driver/gpio.h"
#include "driver/sdmmc_host.h"
#include "esp_log.h"
#include "esp_vfs_fat.h"
#include "sdmmc_cmd.h"

namespace {
const char* TAG = "storage";
const char* MOUNT_POINT = "/sdcard";
sdmmc_card_t* s_card = nullptr;
int s_frame_seq = 0;
// YYYYMMDDHH của thư mục giờ đang "mở" trong phiên chạy hiện tại — tránh mkdir/scan
// lại mỗi frame. Đo thật 13/08: 1 đêm 8h ở ~5.24fps tích luỹ ~150K file nếu gộp phẳng
// vào 1 thư mục /YYYYMMDD — 3 điểm dữ liệu thật (0 file→5.24fps, ~1594→~1.16fps,
// ~4300→0.45fps) cho thấy suy giảm LIÊN TỤC theo số file, không phải ngưỡng đột ngột,
// nên 150K/đêm gần như chắc chắn làm fps sụp nặng dần suốt đêm. Sửa: thêm cấp thư mục
// theo GIỜ (/YYYYMMDD/HH/) — mỗi thư mục giờ chỉ còn tối đa ~19K file (150K/8), và seq
// reset về 0 mỗi giờ (tên file vẫn duy nhất nhờ path khác nhau) nên recover_frame_seq()
// cũng chỉ quét trong 1 giờ thay vì cả đêm.
char s_current_period[16] = {};

// Giữ index.csv MỞ suốt đêm thay vì fopen("a")/fclose() mỗi frame. Đo thật 13/08: sau
// ~4000 dòng tích luỹ, mỗi lần mở lại ở chế độ append tốn ngày càng nhiều thời gian —
// driver FAT phải duyệt hết chuỗi cluster để tìm cuối file mỗi lần open. Ảnh hưởng trực
// tiếp DoD "8 tiếng liên tục" — nếu không sửa, fps sẽ giảm dần suốt đêm khi file lớn
// dần thay vì ổn định.
FILE* s_index_file = nullptr;

// Reboot giữa đêm (rất thường gặp lúc bench-test) trước đây khiến s_frame_seq reset về 0
// và ghi đè âm thầm lên frame_000000.jpg... của phiên trước cùng ngày. Scan thư mục tìm
// seq lớn nhất đã có, tiếp tục từ đó thay vì luôn bắt đầu lại từ 0.
int recover_frame_seq(const char* night_dir) {
    DIR* d = opendir(night_dir);
    if (!d) return 0;
    int max_seq = -1;
    struct dirent* entry;
    while ((entry = readdir(d)) != nullptr) {
        int seq = -1;
        if (sscanf(entry->d_name, "frame_%d.jpg", &seq) == 1 && seq > max_seq) {
            max_seq = seq;
        }
    }
    closedir(d);
    return max_seq + 1;
}

bool is_night_dirname(const char* name) {
    if (strlen(name) != 8) return false;
    for (int i = 0; i < 8; ++i) {
        if (name[i] < '0' || name[i] > '9') return false;
    }
    return true;
}

// FAT không rmdir được thư mục còn file/thư mục con bên trong — xoá đệ quy 1 cấp
// (thư mục đêm giờ chứa các thư mục giờ HH, mỗi thư mục giờ chứa file phẳng).
void remove_dir_recursive(const char* path) {
    DIR* d = opendir(path);
    if (!d) return;
    struct dirent* entry;
    char child[300];
    while ((entry = readdir(d)) != nullptr) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        snprintf(child, sizeof(child), "%s/%s", path, entry->d_name);
        struct stat st;
        if (stat(child, &st) == 0 && S_ISDIR(st.st_mode)) {
            remove_dir_recursive(child);  // thư mục giờ HH — 1 cấp con, không sâu hơn
        } else {
            unlink(child);
        }
    }
    closedir(d);
    rmdir(path);
}
}  // namespace

esp_err_t storage_init() {
    sdmmc_host_t host = SDMMC_HOST_DEFAULT();
    sdmmc_slot_config_t slot_config = SDMMC_SLOT_CONFIG_DEFAULT();
    slot_config.width = 1;  // 1-bit mode — camera AI-Thinker chiếm hết chân cho 4-bit
    // SDMMC_SLOT_CONFIG_DEFAULT() điền sẵn d1/d2/d3 = GPIO4/12/13 (mặc định slot 1),
    // driver vẫn "giữ" 3 chân này dù width=1 nếu không tự tay đặt NC — bắt được lỗi
    // thật "GPIO 4/13 is not usable" khi VL53L0X cần đúng 2 chân đó (13/08). Giải
    // phóng rõ ràng để VL53L0X dùng được GPIO4 (SDA) + GPIO13 (SCL).
    slot_config.d1 = GPIO_NUM_NC;
    slot_config.d2 = GPIO_NUM_NC;
    slot_config.d3 = GPIO_NUM_NC;
    slot_config.clk = static_cast<gpio_num_t>(14);
    slot_config.cmd = static_cast<gpio_num_t>(15);
    slot_config.d0 = static_cast<gpio_num_t>(2);
    slot_config.flags |= SDMMC_SLOT_FLAG_INTERNAL_PULLUP;

    esp_vfs_fat_sdmmc_mount_config_t mount_config = {};
    mount_config.format_if_mount_failed = false;  // KHÔNG tự format — thẻ phải format
                                                    // exFAT sẵn theo phase-02-mua-sam-phan-cung.md
    mount_config.max_files = 5;
    mount_config.allocation_unit_size = 16 * 1024;

    esp_err_t err =
        esp_vfs_fat_sdmmc_mount(MOUNT_POINT, &host, &slot_config, &mount_config, &s_card);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Mount thẻ SD thất bại (0x%x) — kiểm tra format/wiring", err);
        return err;
    }
    ESP_LOGI(TAG, "SD mount OK tại %s", MOUNT_POINT);
    return ESP_OK;
}

esp_err_t storage_open_night(int64_t epoch_s, char* out_dir, size_t out_dir_len) {
    time_t t = static_cast<time_t>(epoch_s);
    struct tm tm_info;
    gmtime_r(&t, &tm_info);
    char night_name[16];
    char period_name[16];  // YYYYMMDDHH — đổi mỗi khi sang giờ mới, không chỉ khi sang ngày
    snprintf(night_name, sizeof(night_name), "%04d%02d%02d", tm_info.tm_year + 1900,
             tm_info.tm_mon + 1, tm_info.tm_mday);
    snprintf(period_name, sizeof(period_name), "%s%02d", night_name, tm_info.tm_hour);

    char night_dir[64];
    snprintf(night_dir, sizeof(night_dir), "%s/%s", MOUNT_POINT, night_name);
    snprintf(out_dir, out_dir_len, "%s/%02d", night_dir, tm_info.tm_hour);

    if (strcmp(period_name, s_current_period) == 0) {
        return ESP_OK;  // đã mở/khôi phục seq cho giờ này trong phiên chạy hiện tại
    }

    // Thư mục đêm (YYYYMMDD) có thể đã có từ giờ trước — mkdir bỏ qua lỗi "đã tồn tại".
    struct stat st_night;
    if (stat(night_dir, &st_night) != 0) {
        mkdir(night_dir, 0755);
    }

    struct stat st;
    if (stat(out_dir, &st) != 0) {
        if (mkdir(out_dir, 0755) != 0) {
            ESP_LOGE(TAG, "Không tạo được thư mục giờ %s", out_dir);
            return ESP_FAIL;
        }
        s_frame_seq = 0;
    } else {
        // Thư mục giờ đã tồn tại từ trước (reboot giữa giờ, hoặc quay lại giờ cũ) —
        // khôi phục seq thay vì ghi đè từ 0. Chỉ quét TRONG thư mục giờ này (tối đa
        // ~19K file/giờ ở 5.24fps), không phải cả đêm.
        s_frame_seq = recover_frame_seq(out_dir);
        ESP_LOGI(TAG, "Thư mục giờ %s đã tồn tại, tiếp tục từ seq %d", out_dir, s_frame_seq);
    }
    strncpy(s_current_period, period_name, sizeof(s_current_period) - 1);

    // Mở index.csv MỘT LẦN cho cả giờ (xem giải thích ở s_index_file phía trên).
    if (s_index_file) fclose(s_index_file);
    char index_path[300];
    snprintf(index_path, sizeof(index_path), "%s/index.csv", out_dir);
    s_index_file = fopen(index_path, "a");
    if (!s_index_file) {
        ESP_LOGE(TAG, "Không mở được %s", index_path);
        return ESP_FAIL;
    }
    return ESP_OK;
}

esp_err_t storage_write_frame(const char* night_dir, const uint8_t* jpg_buf, size_t jpg_len,
                               int32_t distance_mm, int64_t t_ms) {
    char frame_path[320];
    snprintf(frame_path, sizeof(frame_path), "%s/frame_%06d.jpg", night_dir, s_frame_seq);

    FILE* f = fopen(frame_path, "wb");
    if (!f) {
        ESP_LOGE(TAG, "Không mở được %s để ghi", frame_path);
        return ESP_FAIL;
    }
    size_t written = fwrite(jpg_buf, 1, jpg_len, f);
    fclose(f);
    if (written != jpg_len) {
        ESP_LOGE(TAG, "Ghi frame thiếu (%zu/%zu byte) — có thể thẻ đầy", written, jpg_len);
        return ESP_FAIL;
    }

    // jpg đã ghi thành công lúc này — tăng seq ngay để lần sau KHÔNG ghi đè lên file
    // này, kể cả nếu phần index.csv dưới đây lỗi (trước đây seq chỉ tăng sau khi cả
    // 2 bước OK, khiến 1 lần fopen(index.csv) lỗi thoáng qua làm mất frame kế tiếp).
    const int written_seq = s_frame_seq;
    ++s_frame_seq;

    if (!s_index_file) {
        ESP_LOGE(TAG, "index.csv chưa mở — frame_%06d.jpg đã ghi nhưng thiếu dòng index",
                 written_seq);
        return ESP_FAIL;
    }
    fprintf(s_index_file, "%lld,frame_%06d.jpg,%ld\n", static_cast<long long>(t_ms), written_seq,
            static_cast<long>(distance_mm));
    fflush(s_index_file);  // đẩy xuống lớp FS ngay — rẻ hơn nhiều so với fopen("a") lại
                            // từ đầu, vẫn chống mất dữ liệu nếu mất điện đột ngột.

    return ESP_OK;
}

void storage_rotate(int max_nights) {
    DIR* d = opendir(MOUNT_POINT);
    if (!d) return;

    char oldest[16] = {};
    int count = 0;
    struct dirent* entry;
    while ((entry = readdir(d)) != nullptr) {
        if (!is_night_dirname(entry->d_name)) continue;
        ++count;
        if (oldest[0] == '\0' || strcmp(entry->d_name, oldest) < 0) {
            strncpy(oldest, entry->d_name, sizeof(oldest) - 1);
        }
    }
    closedir(d);

    if (count > max_nights && oldest[0] != '\0') {
        char full_path[300];
        snprintf(full_path, sizeof(full_path), "%s/%s", MOUNT_POINT, oldest);
        ESP_LOGI(TAG, "Rotation: xoá thư mục đêm cũ nhất %s (%d/%d thư mục)", full_path, count,
                 max_nights);
        remove_dir_recursive(full_path);
    }
}
