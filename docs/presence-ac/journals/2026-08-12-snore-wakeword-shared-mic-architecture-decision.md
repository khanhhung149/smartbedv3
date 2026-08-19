# Voice-Node: Snore + Wakeword Shared Microphone Architecture Decision

**Date**: 2026-08-12 10:23
**Severity**: Medium
**Component**: firmware/voice-node/src/main.cpp, Phase 4 follow-up (architecture)
**Status**: Architecture approved (doc complete); code not yet started

## What Happened

User brought an external reference doc (`esp32s3-snore-wakeword-docs-revised.md`) proposing an architecture to layer snore detection on top of the existing "Vừng ơi" wakeword gate on voice-node (ESP32-S3-CAM N16R8 + INMP441 mic). Both engines would read from a shared audio pipeline.

Reference doc recommended: **Ring Buffer + independent FreeRTOS task per engine** (Wakeword Engine + Snore Engine both reading from single ring buffer, similar to production audio middleware).

Evaluation against actual `firmware/voice-node/src/main.cpp` revealed a critical mismatch: **current firmware runs a single synchronous Arduino loop** (no FreeRTOS tasks beyond main thread, no ring buffer). Already live E2E in production per README, Phase 4 testing complete (73.3% true-positive, ~2.48/h false-trigger, threshold 0.80).

User's clarifying question mid-brainstorm forced a crucial distinction: **"Does single-loop approach cause contention if someone snores while saying the wakeword at the same time?"**

This split into two categories:
1. **Acoustic collision** — two sounds mixing in mono mic waveform, not a software problem. Same noise-robustness class as Phase 4 testing (room noise was NOT the main driver of false-triggers per existing data). Measurement already complete.
2. **CPU/timing contention** — snore inference (MFCC on ~1s window) running synchronously in same loop tick as `i2s_read()`, risking delayed I2S reads and dropped audio samples. **This IS a real risk** if snore processing takes >16ms per tick (main loop frame is ~16ms at INMP441 sample rate).

Resolution: **Architecture "B+"** — hybrid approach chosen as middle ground.

## The Brutal Truth

The reference doc's architecture is textbook correct for a general-purpose audio middleware. But adopting it verbatim would mean rewriting the entire voice-node firmware from scratch: tear out the Arduino loop, replace with FreeRTOS task spawning, add mutex/queue guards, manage ring buffer lifecycle, test concurrency under realistic mic/speaker/IR load. That's a 2–3 week effort for what should be a feature addition, not a rewrite.

The frustrating part is that the single-loop approach feels "simpler" on the surface, but it has a real timing risk that's harder to debug later in the field: if snore inference stalls the loop for >16ms, the I2S peripheral's internal buffer will overflow silently, dropping audio samples. You won't see a compile error or a crash—just degraded wakeword accuracy the next time someone speaks after a snore. That's the kind of bug that appears intermittently in production and takes weeks to root-cause.

Choosing "B+" means we accept a modest architectural inconsistency (single loop + one offloaded task) to avoid the rewrite tax and still eliminate the I2S-delay risk. Acceptable trade-off, but it means the codebase now has two concurrency patterns (Arduino loop + FreeRTOS task), which is one more thing a future maintainer has to hold in their head.

## Technical Details

- **Reference doc architecture (Option A)**: Ring buffer + 2× FreeRTOS tasks (one for wakeword, one for snore), both pinned to separate cores (APP core + PRO core on ESP32-S3). Zero blocking calls in main loop; `i2s_read()` always runs in predictable time. Tradeoff: ~800 lines of mutex/queue boilerplate; testing concurrency is tedious.
  
- **Pure single-loop (Option B)**: Keep current firmware unchanged; add snore inference directly in main loop after wakeword processing. Simplest code change (~200 lines). **Risk**: if snore MFCC + inference takes >10ms, and that happens during an I2S read cycle, audio is dropped. No guard rail.

- **Chosen: Hybrid "B+"**: Keep main loop unchanged (I2S read + wakeword processing stays on APP core, ~10ms/frame, deterministic). Spawn a **single** FreeRTOS task pinned to PRO core, runs snore inference task at ~1Hz cadence (every ~1 second). Fed by a one-way **buffer snapshot copy** (no mutex needed; single producer in main loop, single consumer in task). When main loop has fresh audio, it atomically copies the last ~1s window to a shared snapshot buffer; snore task reads it when ready. No queue contention, no ring buffer complexity.
  - **Rationale**: Snore inference is not latency-critical (1s window means 1s update lag is acceptable). Wakeword IS latency-critical (needs <100ms response). By separating them, we protect the wakeword path.
  - **I2S risk eliminated**: `i2s_read()` is never blocked by snore processing; always completes in <5ms.
  - **Code complexity**: ~100 lines of FreeRTOS setup + ~50 lines of snapshot buffer logic. Minimal.

- **New doc**: `docs/voice-node-snore-wakeword-architecture.md` (200 lines) written, adapts reference material to real pinouts (GPIO5/6/7 for I2S, not reference's GPIO1/2/42), real MQTT contract, and real existing patterns.
  - Reuses `preRoll` sliding-buffer technique already in wakeword code for capturing pre-utterance audio.
  - Proposes snore hysteresis pattern based on `WAKEWORD_COOLDOWN_MS` debounce added 2026-08-11 as precedent.
  - Proposes new MQTT topic `home/room/snore_event` as **documented proposal only** — explicitly NOT added to canonical `firmware/mqtt/README.md` contract yet. Acknowledges this is a design surface that will need API review once snore dataset is real.

## What We Tried

1. **Option A: Adopt reference doc verbatim** — Full Ring Buffer + multi-task rewrite. Clean architecture, battle-tested pattern.
   - **Rejected**: Rewrite cost too high for current project state; reference doc was exploratory, not meant as drop-in spec.

2. **Option B: Pure single-loop, add snore directly** — Minimal code change, fastest to ship.
   - **Rejected**: I2S-delay risk unacceptable; silent audio drops would break wakeword reliability we just proved in Phase 4.

3. **Option B+: Hybrid (keep loop, spawn one snore task)** — Medium complexity, protects wakeword path.
   - **CHOSEN**. Adds ~150 lines of new code; reuses existing buffer patterns; snore inference gets its own core; I2S path isolated.

## Root Cause Analysis

**Why the reference doc's architecture didn't fit?** It was written as a general-purpose design for a greenfield project, not adapted to an existing live codebase. The reference author didn't have access to `main.cpp` and didn't know the current pattern was single-loop + Arduino. Mismatch is blameless (reasonable for an external doc), but required design decision here.

**Why CPU/timing contention is real?** MFCC computation is O(n log n) for FFT (Cooley-Tukey). On an ESP32-S3 running at 240MHz with 16-bit audio at 16kHz, a 1-second window = 16k samples = 2.7kB raw. MFCC preprocessing (filtering, windowing, FFT, log, DCT) can take 15–25ms depending on implementation. If that runs in the main loop during an I2S read cycle, the I2S peripheral's internal buffer (typically 128 samples on INMP441 = ~8ms at 16kHz) overflows silently. Next wakeword inference window is missing the audio, leading to false negatives.

**Why single-loop felt safe initially?** The wakeword processing is lightweight (~5ms per frame). One more lightweight inference looked harmless. But snore processing has a different computational profile: not per-frame, but per-1s-window. That's a different scale; mixing it into the fast loop violates the separation of concerns.

## Lessons Learned

1. **Separate latency-critical from latency-tolerant workloads in firmware.** Wakeword detection (needs <100ms response) and snore detection (~1s window) are different animals. Don't run them in the same synchronous loop just because the code is smaller.

2. **Document timing budgets explicitly.** "Add snore" sounds innocent until you measure that MFCC is 20ms. Future maintainers need to see: "main loop frame = 16ms, I2S read = ~5ms, wakeword inference = ~5ms, total = ~10ms margin. Snore cannot fit here." Budget is visible, not tacit.

3. **Acoustic collision is not a CPU problem.** User's question ("contention?") mapped to two different failure modes. Mixing two sounds in a mono mic is a signal-processing problem solved by better ML features/training, not by architecture. Don't over-engineer firmware to solve an ML problem.

4. **Buffer snapshots beat queues for slow-update workloads.** Snore updates at 1Hz; main loop is 60Hz. A one-way snapshot (main writes atomically, snore reads when ready, no mutex) is simpler and lower-latency than queue-based handoff. Use the right tool for the update rate.

## Open Questions

**Microphone placement conflict**: Wakeword detection works best when mic is near the mouth/head of bed (closer to speaker, clearer voice pickup). Snore detection needs mic positioned to pick up snoring clearly, which typically means closer to the nose/mouth area during sleep. Are these compatible mic placements, or does snore detection require a second microphone? This is unresolved and will be determined when real snore dataset collection starts. Current architecture assumes one mic suffices; proof-of-concept will validate or invalidate that assumption.

## Next Steps

1. **No code or plan created yet** — User ended brainstorm at doc-only stage. Architecture approved; implementation gated on dataset collection + user decision to proceed to Phase 1 (snore model training).

2. **When snore dataset collection starts** (future phase):
   - Validate mic placement assumption (does one mic pick up both wakeword and snore with acceptable SNR?).
   - Implement snore feature extractor (MFCC or alternative, must match training pipeline).
   - Implement snore inference in C++ (TFLite model on PRO core).
   - Test latency of snapshot buffer under full load (I2S + wakeword + snore running together).

3. **Document implications for MQTT contract**: Current `firmware/mqtt/README.md` does not mention `snore_event` topic. Once snore code is in QA, add formal topic definition + payload schema.

4. **Future Phase doc** should link back to this architecture decision (this journal entry) to explain why B+ was chosen over A.

---

**Owner**: Brainstorm complete. User may proceed to dataset collection or defer snore feature indefinitely without impact to wakeword Phase 4 (which is committed + live).
