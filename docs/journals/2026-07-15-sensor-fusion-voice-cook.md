# Cook 3 phase: Presence Fusion + ASR Voice — VAD Thiết kế Lỏng

**Date**: 2026-07-15 20:47  
**Severity**: High  
**Component**: P2 Backend (ASR VAD), P3 Firmware Voice (INMP441)  
**Status**: Resolved (fixes in place), Unverified (E2E pending)

## Sự kiện

Cook 3 phase parallel: P1 gộp PIR+radar tại S2 Mini → P2 Go backend WS `/api/voice/stream` + VAD flusher → P3 voice-node INMP441 I2S stream PCM qua WS. Code review subagent phát hiện 2 MAJOR bugs VAD sẽ khiến utterance treo hoặc mất câu cuối → fix + re-verify go build/vet/test PASS.

## Sự thật tàn khốc

VAD device↔backend contract bị **suốt lỏng**: phía device (firmware voice-node) chỉ gửi frame khi RMS > VAD_THRESHOLD; phía backend (asr/ service) nhận frame → flush cache lên OpenAI Whisper. **Problem**:
1. **Utterance treo**: device im (VAD ngừng gửi) → backend không có timeout flusher → cache chứa "xin chào" nhưng chẳng bao giờ flush → người dùng chờ vô hạn.
2. **Mất câu cuối**: client WebSocket đóng khi vẫn có frame trong cache → không gửi EOF tín hiệu → backend drop buffer → mất "ON air" lệnh cuối.

**Lý do đau**: thiết kế lúc đầu "device VAD = chôn im; backend chỉ flush khi frame tới" không tính tới graceful shutdown hoặc edge case cả client lẫn firmware cùng im (bằng design, không phải lỗi).

## Chi tiết kỹ thuật

**M1 — Utterance treo** (device im):  
- Firmware voice-node: INMP441 capture RMS → nếu RMS < VAD_THRESHOLD in SilenceMS (e.g. 1000ms) → **ngừng gửi frame**.
- Backend asr/: WS `ReadMessage()` loop → chỉ flush khi có frame tới (`if len(buf) > X bytes`).
- **Kịch bản lỗi**: user nói "xin chào" → device gửi 20 frame, RMS giảm → im 1000ms → STOP gửi → backend cache full nhưng không flush → timeout client.

**M2 — Mất câu cuối** (client close):  
- Browser/client WebSocket close → backend thread `ReadMessage()` return `io.EOF`.
- Handler không explicit flush lại cache → drop in-flight buffer.
- Lệnh cuối "ON air" (4-5 frame cuối cùng) mất.

**Fixes**:
```go
// Backend: read deadline + explicit silence flush
ticker := time.NewTicker(silenceMS * time.Millisecond)  // Timeout flusher
for {
  select {
  case <-ticker.C:
    if len(cache) > 0 { flush(cache); cache = nil }  // Timeout flush
  case n, ok := <-ReadMessage():
    if !ok { flush(cache); return }  // Graceful close flush
    cache += frame; if len(cache) >= byte cap { flush() }
  }
}
```
- Read deadline: `conn.SetReadDeadline(time.Now().Add(SilenceMS + 500ms))`.
- Byte cap: ~16KB (2s audio @ 16kHz).
- Volume cache model: config.LoadVoice() trả struct với silence timeout.

## Nguyên nhân gốc

**Lỗi thiết kế giao thức**, không phải logic lỗi:
1. **Async state mismatch**: device im = im; backend chờ frame = chờ frame. Không có tín hiệu rõ "utterance xong" hay "device im ≥2s".
2. **Graceful shutdown undefined**: WS close không kèm EOF marker → backend không biết có frame sót hay không.
3. **Contract implicit**: code comment nói "device send while speaking" nhưng không codify trong message type hay state machine.

## Bài học

1. **Device ↔ Backend VAD = State Machine tường minh**. Không đủ "device gửi, backend nhận". Cần:
   - Định nghĩa frame type: `DATA | VAD_STOP | EOF | TIMEOUT`.
   - Backend reset timeout mỗi khi frame tới; flush trên TIMEOUT hay EOF.
   - Device gửi VAD_STOP khi RMS < threshold ≥ silence window (hoặc timeout).

2. **Graceful shutdown tính trước**. WebSocket close ≠ EOF audio. Cần explicit message hay read deadline.

3. **Code review VAD logic PHẢI kiểm tra**:
   - State machine diagram (device) ↔ backend flush policy.
   - Edge case: im 0s, im 60s, close instant.
   - Test: timeout flusher, loss last frame, reopen fast.

## Việc còn treo

1. **HW verification**:
   - S2 Mini: đo GPIO7 input mức 3.3/5V, strapping không lỗi → flash P1 presence firmware.
   - WROOM voice-node: hàn INMP441 I2S → tune VAD_THRESHOLD (dò từ volume quiet room) → flash P3.

2. **E2E voice test**:
   - real mic → Whisper in LAN → parse lệnh Việt → AC cmd.
   - Check timeout flush, loss last frame edge case.

3. **Radar USB-C short** (minor):
   - S2 Mini radar LD2410 vẫn hàn đè cổng USB-C → mầm chập; board còn sống.
   - Low priority (presence fused tại board, không phụ thuộc). Để sau.

4. **E2E restart**: Stop all services → reboot WROOM + S2 Mini → voice again → check re-init WAI.

---

**Status**: DONE  
**Summary**: Code review phát hiện VAD device↔backend contract suốt → lỗi thiết kế (no state machine, no graceful EOF) → fix timeout flusher + read deadline + explicit close → verify xong, chờ E2E HW.  
**File**: `/mnt/c/Users/HP/Desktop/New folder/docs/journals/2026-07-15-sensor-fusion-voice-cook.md`
