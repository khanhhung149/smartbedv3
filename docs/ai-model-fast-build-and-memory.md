# Chiến lược build model AI nhanh + Tối ưu bộ nhớ trên voice-node

**Trạng thái (2026-08-13):** tài liệu tham khảo/quyết định chính sách — tổng hợp cách đẩy nhanh vòng
fine-tune model (wakeword "Vừng ơi", snore, ASR) và các nguyên tắc cấp phát bộ nhớ trên ESP32-S3 N16R8.
Đối chiếu với số liệu thật trong `plans/260812-1619-power-memory-architecture-review/` và journal
`docs/journals/2026-08-12-snore-phase1-scaffold-psram-rebuild-saga.md`.

## 1. Build model AI nhanh — nguyên tắc chung

### 1.1. Không train từ đầu (pretrained + fine-tune)

Đây là chiến lược đang dùng và đúng hướng:

| Model | Nguồn pretrained | Việc ta làm |
|---|---|---|
| Wakeword "Vừng ơi" | microWakeWord + esp-nn (pipeline TFLite Micro) | fine-tune trên dataset vài trăm mẫu tự thu |
| Snore | [`alek6kun/snore-recognition`](https://github.com/alek6kun/snore-recognition) (retrain `micro_speech` trên Khan 2019, 500 ngáy/500 không) | dùng thẳng, tinh chỉnh sau nếu cần |
| ASR tiếng Việt | Whisper (faster-whisper, self-host) | dùng thẳng, optional fine-tune |

Lợi ích: chỉ cần fine-tune vài trăm mẫu cho wakeword tùy biến, không cần hàng triệu mẫu/tuần GPU.

### 1.2. Distillation + Quantization

Pipeline chuẩn để có model nhỏ chạy trên ESP32:

1. Train model lớn (hoặc lấy pretrained) → 2. Distill ra model nhỏ → 3. Post-training quantization
   sang INT8 (dùng `tensorflow-model-optimization`) → 4. Convert TFLite, kiểm tra mất độ chính xác.

Model INT8 nhỏ ~2-4x so với FP32, và **tensor arena nhỏ hơn hẳn** — chính là đòn bẩy giải bài toán
bộ nhớ ở mục 2.

### 1.3. Tận dụng cloud GPU cho vòng fine-tune

- Colab / Kaggle / cloud GPU (A100/T4) cho các vòng fine-tune, kết hợp post-training quantization.
- Chạy local chỉ hợp lý khi có GPU; không có GPU thì vòng lặp fine-tune quá chậm.
- Công cụ hỗ trợ: `tensorflow-model-optimization` (quantization), Hugging Face AutoTrain hoặc
  microWakeWord pipeline sẵn có của dự án.

## 2. Tối ưu bộ nhớ trên ESP32-S3 (N16R8)

### 2.1. SRAM vs PSRAM — vai trò khác nhau

| Loại | Dung lượng | Đặc điểm | Dùng cho |
|---|---|---|---|
| SRAM (DIRAM) | ~512KB | Nhanh, DMA tin cậy | Stack task, DMA buffer I2S, code nóng, arena nhỏ |
| PSRAM | 8MB | Chậm hơn hẳn | Data lớn: buffer audio tích lũy, arena lớn, model weights |

**Quy tắc**: PSRAM chỉ để *data*, không để *code nóng*. Chậm nên mọi thứ nhạy latency
(wakeword infer mỗi frame I2S) phải kiểm chứng bằng số đo thật, không suy đoán.

### 2.2. Cấp phát có chủ đích (đang đúng)

- `heap_caps_malloc(MALLOC_CAP_SPIRAM)` cho buffer audio lớn (snore 2×16KB int16 ≈ 62.5KB) — đã làm ở
  `firmware/voice-node/src/main.cpp:642-643`.
- Arena TFLite: wakeword 34KB + snore 200KB đã dời PSRAM, SRAM tĩnh 58.6% → 16.7%
  (journal PSRAM rebuild saga). Log free heap lúc boot + trước/sau cấp phát — đã làm.
- Bật PSRAM đúng cách qua `sdkconfig.defaults` (`CONFIG_SPIRAM=y`, `CONFIG_SPIRAM_MODE_OCT=y`,
  `CONFIG_SPIRAM_SPEED_80M=y`) — không qua `board_build.*` của PlatformIO (hybrid Arduino+IDF bỏ qua,
  đã cháy ~97 phút rebuild vì lầm chỗ này).

### 2.3. Cạm bẫy đã gặp — KHÔNG lặp lại

1. **esp-nn DepthwiseConv2D ghi out-of-bounds khi arena ở PSRAM** → crash-loop heap corruption
   (TLSF), 50 reboot/4h trong soak test (`plans/260812-1619-.../phase-02-soak-test-stability.md`).
   Đã thử rồi revert (12-13/08). Nếu đưa arena model có esp-nn sang PSRAM: phải đảm bảo align +
   `MALLOC_CAP_8BIT`, và **test tay/soak trước khi chốt**, không tin vào lý thuyết.
2. **DMA buffer I2S không đặt PSRAM** — DMA driver chạy chắc trên SRAM; giữ nguyên.
3. **PSRAM được malloc tự do**: không dùng `heap_caps_malloc` bừa; phân bổ có chủ đích, log heap để
   theo dõi leak.

### 2.4. Đòn bẩy giảm arena để nằm gọn SRAM

Nếu model INT8 + input window nhỏ, arena có thể xuống vài chục KB → nằm gọn SRAM, bỏ hẳn rủi ro
PSRAM + latency PSRAM. Đây là hướng ưu tiên cho tương lai (snore arena 200KB hiện là to nhất).

### 2.5. Ngân sách bộ nhớ toàn hệ thống

Cần bảng ngân sách toàn hệ thống (SRAM + PSRAM theo từng khối: WiFi stack, tflite arena, buffer audio,
MQTT/WebSocket) — kết quả đang thiếu, là acceptance criteria của
`plans/260812-1619-power-memory-architecture-review/plan.md` (Phase 5 docs).

## 3. Việc cần làm tiếp (đề xuất)

1. Xác minh latency wakeword thật trên PSRAM (baseline DIRAM 5.4ms) — chưa đo lại chính thức.
2. Root-cause crash-loop heap corruption trước khi chạm tiếp PSRAM/arena.
3. Thử model INT8 + arena gọn để có phương án SRAM-only cho wakeword.
4. Viết bảng ngân sách bộ nhớ toàn hệ thống vào tài liệu này khi có số đo thật.

Liên kết: `docs/voice-node-snore-wakeword-architecture.md`, `docs/system-architecture.md`,
`docs/journals/2026-08-12-snore-phase1-scaffold-psram-rebuild-saga.md`.
