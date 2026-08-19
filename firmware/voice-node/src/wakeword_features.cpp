#include "wakeword_features.h"

#include <cstring>

#include "microfrontend/lib/frontend_util.h"

bool WakewordFeatures::begin(int sampleRateHz) {
  FrontendConfig config{};
  FrontendFillConfigWithDefaults(&config);

  // Chỉ ghi đè đúng các field đã xác nhận từ pipeline train (xem comment đầu file .h) —
  // các field khác (noise_reduction.smoothing_bits/even_smoothing/odd_smoothing,
  // pcan.strength/offset/gain_bits, log_scale.scale_shift) GIỮ NGUYÊN mặc định thư viện, vì
  // audio_utils.py không ghi đè chúng — train cũng chạy trên đúng các mặc định đó.
  config.window.size_ms = 30;
  config.window.step_size_ms = 10;
  config.filterbank.num_channels = kNumChannels;
  config.filterbank.lower_band_limit = 125.0f;
  config.filterbank.upper_band_limit = 7500.0f;
  config.pcan_gain_control.enable_pcan = 1;
  config.noise_reduction.min_signal_remaining = 0.05f;

  return FrontendPopulateState(&config, &state_, sampleRateHz) != 0;
}

void WakewordFeatures::reset() {
  FrontendReset(&state_);
  pendingCount_ = 0;
}

bool WakewordFeatures::pushSamples(const int16_t *pcm, size_t numSamples,
                                   uint16_t outFeatures[kFramesPerInference][kNumChannels]) {
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
      memcpy(pending_[pendingCount_], out.values, sizeof(pending_[0]));
      pendingCount_++;
      if (pendingCount_ == kFramesPerInference) {
        memcpy(outFeatures, pending_, sizeof(pending_));
        pendingCount_  = 0;
        gotNewGroup    = true;
      }
    }
  }
  return gotNewGroup;
}
