# Đánh giá repo sanoTTS cho tính năng voice-output tương lai

**Ngày**: 2026-09-08 | **Loại**: brainstorm — ghi lại để áp dụng sau, chưa triển khai
**Link**: https://github.com/Ampixa/sanoTTS

## Vấn đề đặt ra

User hỏi repo `sanoTTS` có giúp ích cho smartbedv3 không. Không có tính năng cụ thể cần ngay — trả
lời "ghi lại để đó sau này, áp dụng" khi được hỏi use case. Đây là ghi chú tham khảo cho lần sau khi
có nhu cầu voice-output cụ thể (bed phản hồi wakeword, đọc báo cáo giấc ngủ, cảnh báo giọng nói, ...).

## sanoTTS là gì

- TTS engine siêu nhẹ: 294k–2.3M tham số, không cần GPU, RAM vài MB, <4MB/voice.
- Chạy được trên ESP32-S3 (C runtime), WASM (browser), Python (CLI/lib).
- 11 giọng, gồm **tiếng Việt**. Input text → output WAV 22/24kHz.
- Thành phần: duration model + acoustic latent + decoder, phonemizer espeak-ng.
- License: **GPL-3.0** (do phụ thuộc espeak-ng copyleft); tác giả claim runtime code MIT nhưng
  cần đọc kỹ license thật trước khi ship vào firmware phân phối — chưa verify chi tiết điều khoản.
- 432 sao, 42 fork, 35 commit — đang phát triển, có PyPI/npm/HuggingFace/demo.

## Đối chiếu với smartbedv3 (đã scout)

- `firmware/voice-node` chạy trên **ESP32-S3-CAM N16R8 + mic INMP441** — cùng họ chip sanoTTS
  target → điểm khớp kỹ thuật thật, không suy đoán.
- Voice-node hiện tại **chỉ thu âm** (wakeword "Vừng ơi" field-test xong: TP 73.3%, false-trigger
  2.48/h; snore detection qua TFLite Micro) — xem
  `docs/presence-ac/voice-node-snore-wakeword-architecture.md`.
- **Không có phần cứng phát âm thanh** nào được document ở `docs/`, `mech/`, hay firmware config
  (không loa, không I2S DAC/amp kiểu MAX98357A). Cần thêm phần cứng thật, không chỉ software.
- Roadmap hiện có (`plans/`, `docs/system-architecture.md`,
  `docs/presence-ac/project-roadmap.md`) không có mục nào về phản hồi giọng nói — đây là tính năng
  mới, chưa nằm trong scope đã duyệt.
- Rule an toàn của README: mọi output (ngưng thở, hô hấp, sleep stage) phải ghi "tham khảo, không
  dùng chẩn đoán" — nếu dùng TTS để đọc cảnh báo sức khỏe, câu chữ phải tuân rule này.

## Kết luận

Liên quan về mặt kỹ thuật (cùng chip, nhẹ tài nguyên, có tiếng Việt) nhưng **chưa có chỗ để cắm vào**
scope hiện tại: chưa có yêu cầu tính năng xác định, chưa có phần cứng loa, license GPL-3.0 cần rà kỹ
trước khi ship. Không phải "không dùng được" — mà "dùng được cho tính năng chưa tồn tại".

## Khi nào quay lại đánh giá này

- Khi có yêu cầu cụ thể: bed phản hồi giọng nói cho wakeword / đọc báo cáo giấc ngủ / cảnh báo âm
  thanh.
- Trước khi bắt tay: (1) chọn + gắn phần cứng loa (I2S DAC/amp) vào voice-node hoặc node mới,
  (2) đọc kỹ license GPL-3.0 của sanoTTS đối chiếu với mô hình phân phối firmware của dự án,
  (3) benchmark thật độ trễ + chất lượng giọng tiếng Việt trên board ESP32-S3 N16R8 đang dùng.

## Câu hỏi chưa giải quyết

- Mô hình phân phối firmware (mã nguồn có công khai không) để biết GPL-3.0 có ràng buộc gì thật sự.
- Board hiện tại (N16R8) còn đủ GPIO/RAM rảnh để thêm I2S output driver song song I2S input mic
  không — chưa kiểm tra.
