#include "snore_model.h"

// Toàn bộ file rỗng nếu KHÔNG bật ENABLE_WAKEWORD — cùng lý do wakeword_model.cpp: env esp32dev/
// esp32s3 (framework arduino thuần) không có component manager ESP-IDF nên esp-tflite-micro không
// tồn tại ở đó.
#ifdef ENABLE_WAKEWORD

#include <cstring>

#include <esp_heap_caps.h>  // heap_caps_aligned_alloc(..., MALLOC_CAP_SPIRAM) — arena đặt PSRAM, xem dưới

#include "tensorflow/lite/core/c/common.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_log.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"
#include "tensorflow/lite/schema/schema_generated.h"

#include "snore_model_data.h"

namespace {
// Model KHÔNG dùng resource-variable/streaming (không có VarHandle/CallOnce như wakeword) nên dùng
// thẳng overload MicroInterpreter(model, resolver, arena, size) — không cần MicroAllocator/
// MicroResourceVariables tường minh như wakeword_model.cpp.
//
// ĐO THẬT trên board (2026-08-12, kTensorArenaSize=100*1024 ban đầu theo main_functions.cc repo
// gốc): AllocateTensors() báo lỗi rõ ràng "Failed to resize buffer. Requested: 152384, available
// 98580, missing: 53804" — 100KB không đủ (repo gốc chạy trên ESP-IDF thuần với cấu hình linker
// khác, không thể copy nguyên số 100KB). 200KB (dư ~48KB so với 152384 thật cần) là số ĐO ĐƯỢC sau
// khi sửa, không phải suy đoán.
//
// Đặt PSRAM (KHÔNG phải mảng tĩnh trong DIRAM như wakeword's g_tensorArena 34KB): DIRAM của board
// này chỉ còn ~57KB trống (đo được, xem báo cáo build) — không đủ chứa thêm ~53-100KB arena. N16R8
// có 8MB PSRAM dư dả (đã dùng tiền lệ này cho snoreAccumBuf/snoreSnapshotBuf trong main.cpp), cấp
// phát ĐỘNG trong begin() bằng heap_caps_aligned_alloc thay vì mảng tĩnh.
constexpr int kTensorArenaSize = 200 * 1024;
uint8_t *g_tensorArena = nullptr;

const tflite::Model *g_model = nullptr;
tflite::MicroInterpreter *g_interpreter = nullptr;
TfLiteTensor *g_input = nullptr;
TfLiteTensor *g_output = nullptr;

// Op resolver đọc TRỰC TIẾP từ main/main_functions.cc repo gốc (11 op) — khác hẳn wakeword (không
// có ExpandDims/DepthwiseConv2D/Split/resource-variable ops, CÓ Conv2D/MaxPool2D/Shape/
// ResizeBilinear mà wakeword không dùng).
//
// ⚠️ NẾU BOOT BÁO "Didn't find op for builtin opcode 'X'": thêm đúng AddX() tương ứng ở đây rồi
// build lại — TFLM báo tên op thiếu rõ ràng trong log.
constexpr int kNumOps = 11;
tflite::MicroMutableOpResolver<kNumOps> BuildOpResolver() {
  tflite::MicroMutableOpResolver<kNumOps> resolver;
  resolver.AddConv2D();
  resolver.AddFullyConnected();
  resolver.AddReshape();
  resolver.AddMaxPool2D();
  resolver.AddShape();
  resolver.AddStridedSlice();
  resolver.AddPack();
  resolver.AddResizeBilinear();
  resolver.AddQuantize();
  resolver.AddDequantize();
  resolver.AddLogistic();
  return resolver;
}
}  // namespace

bool SnoreModel::begin() {
  g_model = tflite::GetModel(kSnoreModel);
  if (g_model->version() != TFLITE_SCHEMA_VERSION) {
    MicroPrintf("[snore] model schema version %d != supported %d", g_model->version(),
               TFLITE_SCHEMA_VERSION);
    return false;
  }

  if (!g_tensorArena) {
    // alignment=16: TFLM yêu cầu arena thẳng hàng, giống lý do alignas(16) ở snore_model_data.h.
    g_tensorArena = static_cast<uint8_t *>(
        heap_caps_aligned_alloc(16, kTensorArenaSize, MALLOC_CAP_SPIRAM));
    if (!g_tensorArena) {
      MicroPrintf("[snore] cấp phát PSRAM cho tensor arena (%u byte) lỗi", (unsigned)kTensorArenaSize);
      return false;
    }
  }

  static tflite::MicroMutableOpResolver<kNumOps> resolver = BuildOpResolver();
  static tflite::MicroInterpreter interpreter(g_model, resolver, g_tensorArena, kTensorArenaSize);
  g_interpreter = &interpreter;

  if (g_interpreter->AllocateTensors() != kTfLiteOk) {
    MicroPrintf("[snore] AllocateTensors() lỗi — xem log TFLM phía trên để biết op/arena thiếu");
    return false;
  }

  g_input  = g_interpreter->input(0);
  g_output = g_interpreter->output(0);

  MicroPrintf("[snore] model sẵn sàng: arena dùng=%u/%u byte, input type=%d bytes=%u, "
             "output type=%d bytes=%u",
             (unsigned)g_interpreter->arena_used_bytes(), (unsigned)kTensorArenaSize,
             (int)g_input->type, (unsigned)g_input->bytes, (int)g_output->type,
             (unsigned)g_output->bytes);

  // Repo gốc xác nhận input model này là kTfLiteUInt8 ghi thẳng (main_functions.cc:117/131,
  // model_input->data.uint8) — KHÔNG phải kiểu affine-quantize đọc scale/zero_point như wakeword
  // (int8). Chặn sớm ở đây nếu converter khác đi cho ra kiểu khác, tránh Invoke() chạy "không lỗi"
  // nhưng ghi dữ liệu sai kiểu (đúng rủi ro "format dữ liệu lệch" nêu ở plan).
  constexpr int kElems = SnoreFeatures::kFeatureSliceCount * SnoreFeatures::kNumChannels;
  if (g_input->type != kTfLiteUInt8 || g_input->bytes != kElems) {
    MicroPrintf("[snore] input type=%d bytes=%u != kTfLiteUInt8/%d (repo gốc) — memcpy() ở "
               "infer() sẽ ghi sai kích thước/tràn arena nếu bỏ qua kiểm tra này",
               (int)g_input->type, (unsigned)g_input->bytes, kElems);
    return false;
  }

  // Output cũng PHẢI là uint8 (recognize_commands.cc repo gốc: latest_results->type kiểm là
  // kTfLiteUInt8 trước khi đọc data.uint8) — infer() đọc data.uint8[0] không qua nhánh kiểu nào
  // khác, khác wakeword_model.cpp (đọc int8/uint8/float32 tuỳ nhánh). Đọc union sai kiểu KHÔNG
  // crash, chỉ cho điểm số vô nghĩa im lặng — đúng rủi ro nguy hiểm nhất nêu ở plan Risk Assessment.
  if (g_output->type != kTfLiteUInt8) {
    MicroPrintf("[snore] output type %d != kTfLiteUInt8 (repo gốc) — infer() sẽ đọc sai kiểu",
               (int)g_output->type);
    return false;
  }

  ready_ = true;
  return true;
}

float SnoreModel::infer(const uint8_t features[SnoreFeatures::kFeatureSliceCount]
                                              [SnoreFeatures::kNumChannels]) {
  if (!ready_) return 0.0f;

  constexpr int kElems = SnoreFeatures::kFeatureSliceCount * SnoreFeatures::kNumChannels;

  // Ghi THẲNG uint8 đã rescale sẵn ở SnoreFeatures — KHÔNG quantize lại qua scale/zero_point của
  // tensor input như wakeword. Input tensor model này không mang ý nghĩa affine-quantize chuẩn
  // TFLite: nó là đặc trưng thô đã rescale thủ công lúc train (xem comment
  // SnoreFeatures::pushSamples + main_functions.cc:131 repo gốc: model_input_buffer = uint8 trực
  // tiếp, không có bước nhân scale/cộng zero_point nào ở phía ghi input).
  memcpy(g_input->data.uint8, &features[0][0], kElems);

  if (g_interpreter->Invoke() != kTfLiteOk) {
    MicroPrintf("[snore] Invoke() lỗi");
    return 0.0f;
  }

  // Output NGƯỢC LẠI dùng scale/zero_point thật đọc từ tensor (affine-quantize chuẩn TFLite ở đầu
  // ra Logistic) — an toàn hơn giả định cứng "raw/255" mà recognize_commands.cc repo gốc dùng (họ
  // so thẳng uint8 thô với ngưỡng 128, tương đương ngầm định zero_point=0/scale=1/255 — đúng với
  // converter chuẩn nhưng không đảm bảo 100%, đọc trực tiếp từ model luôn đúng bất kể converter).
  uint8_t raw = g_output->data.uint8[0];  // index 0 = "snoring" (kCategoryLabels[0] repo gốc)
  return (static_cast<float>(raw) - g_output->params.zero_point) * g_output->params.scale;
}

#endif  // ENABLE_WAKEWORD
