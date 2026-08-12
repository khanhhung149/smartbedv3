// Interpreter TFLite Micro cho model wakeword "Vừng ơi" (microWakeWord, biến thể
// stream_state_internal_quant — trạng thái streaming được model TỰ giữ nội bộ giữa các lần
// Invoke(), không cần code ngoài quản lý buffer trạng thái).
//
// Input: [1, 3, kNumChannels] — 3 khung đặc trưng MỚI mỗi lần Invoke() (xem WakewordFeatures).
// Output: 1 điểm số (sigmoid, 0..1) — so với WAKEWORD_THRESHOLD để quyết định LISTENING->STREAMING.
#pragma once

#include <cstddef>
#include <cstdint>

#include "wakeword_features.h"

class WakewordModel {
 public:
  // Nạp model từ mảng nhúng (wakeword_model_data.h, sinh bằng scripts/gen-model-header.py),
  // khai báo op resolver, cấp phát tensor arena. Trả false nếu bất kỳ bước nào lỗi — Serial đã
  // in lý do cụ thể (MicroPrintf), gọi nơi dùng chỉ cần biết thành/bại.
  bool begin();

  // Chạy 1 lần Invoke() với 3 khung đặc trưng mới, trả điểm số đã dequantize về [0,1].
  // KHÔNG gọi khi begin() trả false.
  float infer(const uint16_t features[WakewordFeatures::kFramesPerInference]
                                     [WakewordFeatures::kNumChannels]);

 private:
  bool ready_ = false;
};
