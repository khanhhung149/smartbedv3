// Trích đặc trưng âm thanh cho model snore-detection (alek6kun/snore-recognition, Apache-2.0),
// dùng THẲNG thư viện microfrontend gốc của Google (vendor tại src/microfrontend/lib/) — CÙNG
// thư viện WakewordFeatures dùng, nhưng KHÁC instance/tham số (window/step/channels/band khác
// hẳn, xem begin()). 2 model chạy độc lập, không chia sẻ FrontendState.
//
// Tham số lấy TRỰC TIẾP từ main/micro_features_generator.cc + main/micro_model_settings.h của
// repo gốc (đọc code thật, không suy đoán) — xem
// plans/260812-1401-voice-node-snore-model-integration/phase-01-model-va-feature-extraction.md.
#pragma once

#include <cstddef>
#include <cstdint>

#include "microfrontend/lib/frontend.h"

class SnoreFeatures {
 public:
  static constexpr int kNumChannels      = 30;  // filterbank.num_channels (repo gốc: kFeatureSliceSize)
  static constexpr int kFeatureSliceCount = 61;  // input model [1, 61*30] — KHÔNG streaming, cần đủ
                                                  // 61 slice/lần Invoke() (khác wakeword 3 khung/lần)

  // Cấp phát state + FrontendPopulateState. Gọi 1 lần trong setup(). Trả false nếu thư viện báo lỗi.
  bool begin(int sampleRateHz);

  // Đẩy PCM16 (thường là snoreSnapshotBuf ~1s = 16000 mẫu @16kHz, khớp đúng 61 hop @ window=32ms/
  // step=16ms) vào frontend, tích luỹ tới khi đủ kFeatureSliceCount slice thì trả true và điền
  // outFeatures. TỰ LẶP tới khi tiêu thụ hết pcm đưa vào (như WakewordFeatures::pushSamples) — dư
  // mẫu bị bỏ sót sẽ làm lệch pha hop dần theo thời gian.
  bool pushSamples(const int16_t *pcm, size_t numSamples,
                   uint8_t outFeatures[kFeatureSliceCount][kNumChannels]);

  void reset();  // FrontendReset — xoá lịch sử hop/PCAN/noise

 private:
  FrontendState state_{};
  uint8_t pending_[kFeatureSliceCount][kNumChannels]{};
  int pendingCount_ = 0;
};
