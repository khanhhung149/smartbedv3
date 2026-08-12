// Trích đặc trưng âm thanh cho model wakeword "Vừng ơi", dùng THẲNG thư viện microfrontend gốc
// của Google (vendor tại src/microfrontend/lib/, xem README.md trong đó) thay vì tự viết lại
// FFT/mel-filterbank. Lý do: pipeline train Python (microwakeword/audio/audio_utils.py, nhánh
// use_c=True mặc định — gọi qua gói pymicro-features) chạy CÙNG thư viện C này, nên chỉ cần khớp
// tham số là loại bỏ gần hết rủi ro lệch số giữa train và firmware (rủi ro cao nhất được nêu ở
// plans/260810-0843-voice-node-wakeword-gate/phase-02-feature-extraction-validate.md).
//
// Tham số khớp bảng đã trích ở Phase 1 (plans/.../phase-01-*.md) + đối chiếu chéo với
// audio_microfrontend(...) trong audio_utils.py:69-81 — cả hai nguồn cho CÙNG một bộ số:
//   sample_rate=16000  window=30ms  step=10ms  num_channels=40
//   lower_band=125Hz  upper_band=7500Hz  enable_pcan=true  min_signal_remaining=0.05
//   out_type=uint16 (mặc định thư viện, không cần chỉnh log_scale/noise_reduction/pcan khác)
#pragma once

#include <cstddef>
#include <cstdint>

#include "microfrontend/lib/frontend.h"

class WakewordFeatures {
 public:
  static constexpr int kNumChannels = 40;        // filterbank.num_channels — cũng là input[-1] model
  static constexpr int kFramesPerInference = 3;  // input model [1,3,40] — xem model_summary.txt streaming

  // Cấp phát state + FrontendPopulateState. Gọi 1 lần trong setup(). Trả false nếu thư viện báo lỗi
  // (thường do sample_rate/window không hợp lệ — không nên xảy ra với tham số cố định ở trên).
  bool begin(int sampleRateHz);

  // Đẩy PCM16 mới đọc từ I2S vào bộ đệm nội bộ của frontend. FrontendProcessSamples mỗi lần gọi chỉ
  // tiêu thụ ĐỦ mẫu cho một hop (10ms = 160 mẫu @16kHz) rồi trả về — I2S_READ_SAMPLES=256 (16ms)
  // không chia hết cho 160, nên hàm này TỰ LẶP tới khi tiêu thụ hết toàn bộ pcm đưa vào, không để
  // dư mẫu bị bỏ sót (dư mẫu bị bỏ = lệch pha hop dần theo thời gian, feature trôi so với train).
  //
  // Model "stream_state_internal" tự giữ lịch sử qua Invoke() bằng state riêng — mỗi lần Invoke()
  // chỉ cần đúng 3 KHUNG MỚI (không chồng lấp, không phải cửa sổ trượt). Hàm này gom đủ 3 khung mới
  // rồi mới trả về true; nếu >1 bộ-3-khung xuất hiện trong một lần gọi (hiếm, chỉ khi loop() bị trễ
  // nhiều vòng I2S), CHỈ bộ MỚI NHẤT được giữ — bộ cũ hơn bị bỏ, chấp nhận được vì mục tiêu là phát
  // hiện wakeword theo thời gian thực, không phải xử lý lại toàn bộ lịch sử.
  bool pushSamples(const int16_t *pcm, size_t numSamples,
                   uint16_t outFeatures[kFramesPerInference][kNumChannels]);

  void reset();  // FrontendReset — xoá lịch sử hop/PCAN/noise, dùng khi cần "quên" ngữ cảnh cũ

 private:
  FrontendState state_{};
  uint16_t pending_[kFramesPerInference][kNumChannels]{};
  int pendingCount_ = 0;
};
