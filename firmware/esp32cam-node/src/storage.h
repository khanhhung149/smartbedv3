// Ghi frame + khoảng cách + timestamp vào microSD cục bộ (SDMMC 1-bit, mount FAT).
// Cấu trúc: /sdcard/<YYYYMMDD>/frame_<seq>.jpg + /sdcard/<YYYYMMDD>/index.csv
// (t_ms,frame_file,distance_mm). Rotation xoá thư mục đêm cũ nhất khi >30 thư mục.
//
// CHỈ compile khi BENCH_TEST_MODE=1 (xem main.cpp) — build production không link
// module này, đúng ranh giới riêng tư đã chốt (docs/safety/hazard-analysis.md H-25).
#pragma once

#include <cstddef>
#include <cstdint>
#include "esp_err.h"

// Mount thẻ SD (SDMMC 1-bit: CLK=14, CMD=15, D0=2 — chuẩn AI-Thinker). Format phải
// là FAT/exFAT theo quyết định plan (256GB, xem phase-02-mua-sam-phan-cung.md).
esp_err_t storage_init();

// Tạo (nếu chưa có) thư mục đêm hiện tại theo epoch_s, trả về qua out_dir (buffer
// tối thiểu 32 byte, dạng "/sdcard/YYYYMMDD").
esp_err_t storage_open_night(int64_t epoch_s, char* out_dir, size_t out_dir_len);

// Ghi 1 frame JPEG + append dòng vào index.csv của thư mục đêm đang mở.
esp_err_t storage_write_frame(const char* night_dir, const uint8_t* jpg_buf, size_t jpg_len,
                               int32_t distance_mm, int64_t t_ms);

// Đếm thư mục YYYYMMDD dưới /sdcard, xoá thư mục cũ nhất nếu vượt max_nights.
void storage_rotate(int max_nights);
