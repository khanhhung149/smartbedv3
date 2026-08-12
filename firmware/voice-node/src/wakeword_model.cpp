#include "wakeword_model.h"

// Toàn bộ file rỗng nếu KHÔNG bật ENABLE_WAKEWORD (chỉ env esp32s3_kws định nghĩa cờ này trong
// platformio.ini). Bắt buộc phải ifdef ở đây: env esp32dev/esp32s3 (đường lui, framework arduino
// thuần) không có component manager ESP-IDF nên esp-tflite-micro/tensorflow-lite-micro không tồn
// tại ở đó — include các header dưới sẽ lỗi "No such file" nếu thiếu ifdef này.
#ifdef ENABLE_WAKEWORD

#include <cmath>

#include "tensorflow/lite/core/c/common.h"
#include "tensorflow/lite/micro/micro_allocator.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_log.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"
#include "tensorflow/lite/micro/micro_resource_variable.h"
#include "tensorflow/lite/schema/schema_generated.h"

#include "wakeword_model_data.h"

namespace {
// Benchmark thực đo 5.4ms (journal 08/08) trên board S3 thật, không tính phần feature-extraction.
// Cấp dư (26KB đo được -> 32KB) chứ không cấp đúng khít, theo quyết định Phase 3 của plan.
// 32KB -> 34KB (10/08, board thật): thêm MicroAllocator/MicroResourceVariables (xem begin()) ăn
// thêm vào arena, board báo thiếu đúng 524 byte ("Failed to resize buffer. Requested: 18224,
// available 17700"). +2KB dư thay vì vá đúng khít 524 byte.
constexpr int kTensorArenaSize = 34 * 1024;
alignas(16) uint8_t g_tensorArena[kTensorArenaSize];

const tflite::Model *g_model = nullptr;
tflite::MicroInterpreter *g_interpreter = nullptr;
TfLiteTensor *g_input = nullptr;
TfLiteTensor *g_output = nullptr;

// Op resolver: liệt kê theo cấu trúc layer đọc từ model_summary.txt (train) — ExpandDims,
// DepthwiseConv2D/Conv2D (BatchNorm bị TFLite converter fold vào Conv2D lúc quantize nên KHÔNG
// cần op riêng), ChannelSplit->SPLIT_V, StridedKeep/StridedDrop->STRIDED_SLICE,
// Concatenate->CONCATENATION, lớp phân loại nhị phân cuối thường FullyConnected + Logistic
// (sigmoid). "stream_state_internal" gợi ý trạng thái streaming qua resource-variable ops
// (VarHandle/ReadVariable/AssignVariable) nên thêm cả ba, dù `strings` trên .tflite không thấy
// tên tensor rõ — không kết luận được chắc chắn khi chỉ đọc chuỗi debug name.
//
// ⚠️ NẾU BOOT BÁO "Didn't find op for builtin opcode 'X'": thêm đúng AddX() tương ứng ở đây rồi
// build lại — TFLM báo tên op thiếu rõ ràng trong log, không cần đoán lần hai.
constexpr int kNumOps = 21;
tflite::MicroMutableOpResolver<kNumOps> BuildOpResolver() {
  tflite::MicroMutableOpResolver<kNumOps> resolver;
  // Đúng kịch bản cảnh báo ở comment trên: board thật báo thiếu CALL_ONCE (16261, 10/08) —
  // op này chạy 1 lần lúc khởi tạo resource-variable state (đi cùng VarHandle/ReadVariable/
  // AssignVariable đã có sẵn), model list op không lộ ra khi chỉ đọc string debug name.
  resolver.AddCallOnce();
  resolver.AddExpandDims();
  resolver.AddReshape();
  resolver.AddConv2D();
  resolver.AddDepthwiseConv2D();
  resolver.AddFullyConnected();
  resolver.AddLogistic();
  resolver.AddSplit();
  resolver.AddSplitV();
  resolver.AddStridedSlice();
  resolver.AddConcatenation();
  resolver.AddPad();
  resolver.AddRelu();
  resolver.AddAdd();
  resolver.AddMul();
  resolver.AddQuantize();
  resolver.AddDequantize();
  resolver.AddVarHandle();
  resolver.AddReadVariable();
  resolver.AddAssignVariable();
  resolver.AddMean();
  return resolver;
}
}  // namespace

bool WakewordModel::begin() {
  g_model = tflite::GetModel(kVungOiModel);
  if (g_model->version() != TFLITE_SCHEMA_VERSION) {
    MicroPrintf("[wakeword] model schema version %d != supported %d", g_model->version(),
               TFLITE_SCHEMA_VERSION);
    return false;
  }

  static tflite::MicroMutableOpResolver<kNumOps> resolver = BuildOpResolver();

  // Model "stream_state_internal" giữ trạng thái streaming qua resource-variable ops (VarHandle/
  // ReadVariable/AssignVariable) — board thật báo lỗi (10/08): "VAR_HANDLE requires resource
  // variables. Please create ResourceVariables and pass it to the interpreter." Đăng ký op ở
  // resolver KHÔNG đủ, TFLM cần một MicroAllocator tường minh (để cấp phát MicroResourceVariables
  // từ persistent buffer) rồi truyền resource_variables vào constructor interpreter — không dùng
  // được overload arena-trực-tiếp (arena+size) nữa vì overload đó không nhận resource_variables
  // theo cách chia sẻ chung allocator. 8 slot là dư so với số resource variable thật của model nhỏ
  // này (rẻ: chỉ vài chục byte struct/slot, cấp dư còn hơn thiếu rồi phải đoán lại).
  static tflite::MicroAllocator *allocator =
      tflite::MicroAllocator::Create(g_tensorArena, kTensorArenaSize);
  static tflite::MicroResourceVariables *resourceVars =
      tflite::MicroResourceVariables::Create(allocator, /*max_num_variables=*/8);
  static tflite::MicroInterpreter interpreter(g_model, resolver, allocator, resourceVars);
  g_interpreter = &interpreter;

  if (g_interpreter->AllocateTensors() != kTfLiteOk) {
    MicroPrintf("[wakeword] AllocateTensors() lỗi — xem log TFLM phía trên để biết op/arena thiếu");
    return false;
  }

  g_input  = g_interpreter->input(0);
  g_output = g_interpreter->output(0);

  MicroPrintf("[wakeword] model sẵn sàng: input type=%d dims=[%d,%d,%d] output type=%d size=%d",
             (int)g_input->type, (int)g_input->dims->data[0], (int)g_input->dims->data[1],
             (int)g_input->dims->data[2], (int)g_output->type, (int)g_output->bytes);

  ready_ = true;
  return true;
}

float WakewordModel::infer(const uint16_t features[WakewordFeatures::kFramesPerInference]
                                                   [WakewordFeatures::kNumChannels]) {
  if (!ready_) return 0.0f;

  constexpr int kElems = WakewordFeatures::kFramesPerInference * WakewordFeatures::kNumChannels;
  const uint16_t *flat = &features[0][0];

  // Input tensor thường là int8 (full-integer quantization, chuẩn microWakeWord export) — quantize
  // đặc trưng uint16 thô (chính là giá trị "thực" model được calibrate lúc train, không qua chuẩn
  // hoá thêm nào khác — audio_utils.py không rescale trước khi đưa vào model) bằng scale/zero_point
  // ĐỌC TRỰC TIẾP từ model đã nạp, không hardcode số — đúng giá trị calibration thật của lần train
  // này. Nhánh float32 giữ lại phòng khi model export không quantize input (ít gặp nhưng rẻ để đỡ).
  if (g_input->type == kTfLiteInt8) {
    const float scale     = g_input->params.scale;
    const int   zeroPoint = g_input->params.zero_point;
    int8_t *dst = g_input->data.int8;
    for (int i = 0; i < kElems; i++) {
      int32_t q = static_cast<int32_t>(lroundf(static_cast<float>(flat[i]) / scale)) + zeroPoint;
      if (q < -128) q = -128;
      if (q > 127) q = 127;
      dst[i] = static_cast<int8_t>(q);
    }
  } else if (g_input->type == kTfLiteFloat32) {
    float *dst = g_input->data.f;
    for (int i = 0; i < kElems; i++) dst[i] = static_cast<float>(flat[i]);
  } else {
    MicroPrintf("[wakeword] input type %d không xử lý — thêm nhánh quantize tương ứng",
               (int)g_input->type);
    return 0.0f;
  }

  if (g_interpreter->Invoke() != kTfLiteOk) {
    MicroPrintf("[wakeword] Invoke() lỗi");
    return 0.0f;
  }

  if (g_output->type == kTfLiteInt8) {
    int8_t raw = g_output->data.int8[0];
    return (static_cast<float>(raw) - g_output->params.zero_point) * g_output->params.scale;
  } else if (g_output->type == kTfLiteUInt8) {
    uint8_t raw = g_output->data.uint8[0];
    return (static_cast<float>(raw) - g_output->params.zero_point) * g_output->params.scale;
  }
  return g_output->data.f[0];  // float32
}

#endif  // ENABLE_WAKEWORD
