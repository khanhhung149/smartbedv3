// Interpreter TFLite Micro cho model snore-detection (alek6kun/snore-recognition, Apache-2.0 —
// bản retrain của ví dụ chính thức TFLite Micro micro_speech trên dataset Khan 2019).
//
// Input: [1, 61*30] uint8 — 61 slice x 30 kênh đặc trưng ĐỦ MỘT LẦN (KHÔNG streaming, khác
// wakeword). Model tự nén 61 slice xuống 32 bằng RESIZE_BILINEAR ở lớp đầu, nên số 61 là đúng ý
// model chứ không phải dư.
//
// Output: [1, 1] uint8 — MỘT giá trị = P("snoring") sau Logistic, KHÔNG phải 2 lớp. Đã kiểm bằng
// cách dump trực tiếp file .tflite (2026-08-13): lớp cuối là FULLY_CONNECTED [1,128]x[1,128] ->
// [1,1] rồi LOGISTIC. Bản mô tả cũ ở đây ghi "[1,2] — 2 lớp {snoring, background}, snoring là
// index 0" là SAI (chép từ kCategoryLabels của repo gốc micro_speech, không khớp model đã export).
// infer() đọc data.uint8[0] nên vẫn đúng, nhưng ĐỪNG tin có index 1 — đọc nó là đọc ngoài tensor.
#pragma once

#include <cstddef>
#include <cstdint>

#include "snore_features.h"

class SnoreModel {
 public:
  // Nạp model từ mảng nhúng (snore_model_data.h, sinh bằng scripts/gen-model-header.py), khai báo
  // op resolver, cấp phát tensor arena. Trả false nếu bất kỳ bước nào lỗi — Serial đã in lý do cụ
  // thể (MicroPrintf), gọi nơi dùng chỉ cần biết thành/bại.
  bool begin();

  // Chạy 1 lần Invoke() với 61x30 đặc trưng, trả điểm số lớp "snoring" đã dequantize về [0,1].
  // KHÔNG gọi khi begin() trả false.
  float infer(const uint8_t features[SnoreFeatures::kFeatureSliceCount][SnoreFeatures::kNumChannels]);

 private:
  bool ready_ = false;
};
