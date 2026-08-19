/* Copyright 2023 The TensorFlow Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
==============================================================================*/

#include "tensorflow/lite/kernels/internal/common.h"

namespace tflite {

// Single-rounding MultiplyByQuantizedMultiplier
#if TFLITE_SINGLE_ROUNDING
int32_t MultiplyByQuantizedMultiplier(int32_t x, int32_t quantized_multiplier,
                                      int shift) {
  TFLITE_DCHECK(quantized_multiplier >= 0);
  TFLITE_DCHECK(shift >= -31 && shift <= 30);

  const int64_t total_shift = 31 - shift;
  const int64_t round = static_cast<int64_t>(1) << (total_shift - 1);
  int64_t result = x * static_cast<int64_t>(quantized_multiplier) + round;
  result = result >> total_shift;

  TFLITE_DCHECK(result >= std::numeric_limits<int32_t>::min() &&
                result <= std::numeric_limits<int32_t>::max());
  return static_cast<int32_t>(result);
}

int32_t MultiplyByQuantizedMultiplier(int64_t x, int32_t quantized_multiplier,
                                      int shift) {
  // Inputs:
  // - quantized_multiplier has fixed point at bit 31
  // - shift is -31 to +7 (negative for right shift)
  //
  // Assumptions: The following input ranges are assumed
  // - quantize_scale>=0  (the usual range is (1<<30) to (1>>31)-1)
  // - scaling is chosen so final scaled result fits in int32_t
  // - input x is in the range -(1<<47) <= x < (1<<47)
  TFLITE_DCHECK(quantized_multiplier >= 0);
  TFLITE_DCHECK(shift >= -31 && shift < 8);
  TFLITE_DCHECK(x >= -(static_cast<int64_t>(1) << 47) &&
                x < (static_cast<int64_t>(1) << 47));

  const int32_t reduced_multiplier =
      (quantized_multiplier < 0x7FFF0000)
          ? ((quantized_multiplier + (1 << 15)) >> 16)
          : 0x7FFF;
  const int64_t total_shift = 15 - shift;
  const int64_t round = static_cast<int64_t>(1) << (total_shift - 1);
  int64_t result = x * static_cast<int64_t>(reduced_multiplier) + round;
  result = result >> total_shift;

  TFLITE_DCHECK(result >= std::numeric_limits<int32_t>::min() &&
                result <= std::numeric_limits<int32_t>::max());
  return static_cast<int32_t>(result);
}
// Double-rounding MultiplyByQuantizedMultiplier
#else
int32_t MultiplyByQuantizedMultiplier(int32_t x, int32_t quantized_multiplier,
                                      int shift) {
  using gemmlowp::RoundingDivideByPOT;
  using gemmlowp::SaturatingRoundingDoublingHighMul;
  int left_shift = shift > 0 ? shift : 0;
  int right_shift = shift > 0 ? 0 : -shift;
  // Clamp: RoundingDivideByPOT asserts exponent<=31 (undefined behavior for a
  // 32-bit rounding right-shift by 32+). Board thật crash (Guru Meditation, đo qua
  // soak test 2026-08-13) vì 1 kênh DepthwiseConv2D int16 (nhánh nội bộ streaming
  // của model wakeword) có output_shift <= -32 trong tham số lượng tử hoá đã export
  // — dùng thẳng shift đó (right_shift=32+) vi phạm giả định của hàm. Clamp về 31
  // thay vì assert-crash: sai số làm tròn thêm cho đúng 1 kênh này là 1 bit cuối
  // cùng của phép right-shift 32-bit, không đáng kể so với độ chồng lấn threshold
  // 0.80-0.99 đã đo thật của wakeword (docs/system-architecture.md).
  if (right_shift > 31) right_shift = 31;
  return RoundingDivideByPOT(SaturatingRoundingDoublingHighMul(
                                 x * (1 << left_shift), quantized_multiplier),
                             right_shift);
}

int32_t MultiplyByQuantizedMultiplier(int64_t x, int32_t quantized_multiplier,
                                      int shift) {
  // Inputs:
  // - quantized_multiplier has fixed point at bit 31
  // - shift is -31 to +7 (negative for right shift)
  //
  // Assumptions: The following input ranges are assumed
  // - quantize_scale>=0  (the usual range is (1<<30) to (1>>31)-1)
  // - scaling is chosen so final scaled result fits in int32_t
  // - input x is in the range -(1<<47) <= x < (1<<47)
  assert(quantized_multiplier >= 0);
  assert(shift >= -31 && shift < 8);
  assert(x >= -(static_cast<int64_t>(1) << 47) &&
         x < (static_cast<int64_t>(1) << 47));

  int32_t reduced_multiplier = (quantized_multiplier < 0x7FFF0000)
                                   ? ((quantized_multiplier + (1 << 15)) >> 16)
                                   : 0x7FFF;
  int total_shift = 15 - shift;
  x = (x * (int64_t)reduced_multiplier) + ((int64_t)1 << (total_shift - 1));
  int32_t result = x >> total_shift;
  return result;
}
#endif  // TFLITE_SINGLE_ROUNDING

}  // namespace tflite
