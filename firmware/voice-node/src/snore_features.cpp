#include "snore_features.h"

#include <cstring>

#include "microfrontend/lib/frontend_util.h"

bool SnoreFeatures::begin(int sampleRateHz) {
  FrontendConfig config{};
  FrontendFillConfigWithDefaults(&config);

  // Số lấy TRỰC TIẾP từ InitializeMicroFeatures() (main/micro_features_generator.cc repo gốc) —
  // khác hẳn WakewordFeatures (window 30ms/step 10ms/40ch/125-7500Hz). Model snore train trên bộ
  // tham số này, lệch bất kỳ field nào cũng lệch phân bố đặc trưng so với lúc train.
  config.window.size_ms = 32;
  config.window.step_size_ms = 16;
  config.noise_reduction.smoothing_bits = 10;
  config.filterbank.num_channels = kNumChannels;
  config.filterbank.lower_band_limit = 40.0f;
  config.filterbank.upper_band_limit = 6000.0f;
  config.noise_reduction.even_smoothing = 0.025f;
  config.noise_reduction.odd_smoothing = 0.06f;
  config.noise_reduction.min_signal_remaining = 0.05f;
  config.pcan_gain_control.enable_pcan = 1;
  config.pcan_gain_control.strength = 0.95f;
  config.pcan_gain_control.offset = 80.0f;
  config.pcan_gain_control.gain_bits = 21;
  config.log_scale.enable_log = 1;
  config.log_scale.scale_shift = 6;

  return FrontendPopulateState(&config, &state_, sampleRateHz) != 0;
}

void SnoreFeatures::reset() {
  FrontendReset(&state_);
  pendingCount_ = 0;
}

bool SnoreFeatures::pushSamples(const int16_t *pcm, size_t numSamples,
                                uint8_t outFeatures[kFeatureSliceCount][kNumChannels]) {
  bool gotNewGroup = false;
  const int16_t *p = pcm;
  size_t remaining = numSamples;

  while (remaining > 0) {
    size_t consumed = 0;
    FrontendOutput out = FrontendProcessSamples(&state_, p, remaining, &consumed);
    if (consumed == 0) break;  // an toàn: thư viện không tiêu thụ gì thì dừng, tránh vòng lặp vô hạn
    p += consumed;
    remaining -= consumed;

    if (out.size == kNumChannels) {
      // Công thức quy đổi ĐÚNG từ GenerateMicroFeatures() (main/micro_features_generator.cc:98 repo
      // gốc) — KHÔNG dùng thẳng giá trị frontend thô như WakewordFeatures. Model này được train trên
      // đặc trưng đã qua bước rescale thủ công lúc train (input_data.py): feature dao động thô
      // ~0..670 -> chia 25.6 -> chia 26.0 -> nhân 256 -> trừ 128, rút gọn thành 1 phép nguyên
      // (raw*128)/335. Bỏ bước này thì input lệch hẳn phân bố lúc train dù model vẫn chạy KHÔNG lỗi
      // (score vô nghĩa — đúng rủi ro "format dữ liệu lệch" nêu ở plan Risk Assessment).
      //
      // Repo gốc clamp trên ở 256 rồi gán thẳng vào uint8_t (256 tràn số thành 0) — trong thực tế
      // không xảy ra vì raw tối đa ~670 -> value tối đa ~255 (670*128/335=255.9), nhưng ở đây clamp
      // đúng ở 255 (giới hạn thật của uint8_t) để không lặp lại lỗi tràn số đó nếu raw vượt dự kiến.
      for (int c = 0; c < kNumChannels; c++) {
        int32_t value = (static_cast<int32_t>(out.values[c]) * 128) / 335;
        if (value < 0) value = 0;
        if (value > 255) value = 255;
        pending_[pendingCount_][c] = static_cast<uint8_t>(value);
      }
      pendingCount_++;
      if (pendingCount_ == kFeatureSliceCount) {
        memcpy(outFeatures, pending_, sizeof(pending_));
        pendingCount_ = 0;
        gotNewGroup    = true;
      }
    }
  }
  return gotNewGroup;
}
