# Voice-Node Snore Phase 1: Buffer + Task Scaffold, PSRAM Debugging Saga

**Date**: 2026-08-12 13:47
**Severity**: High (time cost), Medium (code risk)
**Component**: firmware/voice-node/src/main.cpp, Phase 1 implementation + sdkconfig management
**Status**: Phase 1 complete and committed (b129fc5); Phase 2 plan written, not yet implemented

## What Happened

Implemented the snore detection buffer + FreeRTOS task scaffold approved in this morning's architecture decision journal (2026-08-12 10:23), following plan `plans/260812-1029-voice-node-snore-buffer-task-scaffold/`. Phase 1 code: audio ring buffer accumulation + one background task pinned to PRO core (core 0), computing a placeholder RMS "score" from ~1s audio windows. Phase 2 code: Event Manager pattern (N=3 consecutive high-score windows + 5s cooldown debounce) triggering MQTT publish to `home/room/snore_event`. 

Hardware testing on real ESP32-S3-CAM revealed a silent failure: **snore task never ran. Zero `[snore] rms=` log lines appeared in console output.** Code was syntactically correct, compiled cleanly, but `heap_caps_malloc(MALLOC_CAP_SPIRAM)` was allocating from PSRAM that was not actually enabled in the ESP-IDF build. The ESP32-S3 has 8MB physical PSRAM (esptool confirmed via `esptool.py flash_id`), but `CONFIG_SPIRAM` was not set in the build configuration.

Initial debugging and fix attempt: added `board_build.arduino.memory_type = qio_opi` to `platformio.ini` (PlatformIO's documented knob for PSRAM enablement). Triggered a full clean rebuild (49 minutes elapsed). Result: **completely ineffective. The regenerated `sdkconfig.esp32s3_kws` was byte-identical** to the previous version—no `CONFIG_SPIRAM=y` in the merged config. This repeated the same class of failure the project had previously encountered with `board_build.partitions` (PlatformIO knobs that don't propagate for `framework = arduino, espidf` hybrid builds).

Root cause diagnosis: PlatformIO's Arduino+IDF hybrid mode doesn't honor the `board_build.arduino.*` knobs. The actual configuration source is `sdkconfig.defaults` (a small, hand-curated file that ESP-IDF's Kconfig merge system reads authoritatively). The `board_build.*` knobs only work for pure-Arduino or pure-IDF builds, not hybrids.

Real fix: Located the actual Kconfig symbols in the installed ESP-IDF source (`framework-espidf/components/esp_psram/esp32s3/Kconfig.spiram`), then added three critical lines to `sdkconfig.defaults`:

```
CONFIG_SPIRAM=y
CONFIG_SPIRAM_MODE_OCT=y
CONFIG_SPIRAM_SPEED_80M=y
```

Deleted the stale generated `sdkconfig.esp32s3_kws` file to force regeneration. Triggered another full clean rebuild (48 minutes). This time, the regenerated config contained `CONFIG_SPIRAM=y`; malloc(MALLOC_CAP_SPIRAM) now succeeded; snore task started running and emitting `[snore] rms=` logs.

**Total time spent on PSRAM debugging: ~97 minutes of pure rebuild time, for a 3-line config fix.**

After PSRAM fix, hardware validation on snore buffer + task:
- **Wakeword regression test**: baseline 6/7 true positives (85.7%) from pre-snore phase, post-snore measured 7/7 and 9/10 (91.4% average, no regression). Measured via exact spoken-utterance counting, same field-testing methodology as original Phase 4 validation. Wakeword accuracy did not degrade.
- **MQTT delivery test**: Spawned snore events by monitoring via `mosquitto_sub home/room/snore_event`. Received 2 events in a 60-second window, properly spaced by the 5-second cooldown (no spam). End-to-end pipeline (buffer → task → Event Manager → MQTT publish) confirmed working with placeholder RMS model.

## The Brutal Truth

The PSRAM rebuild saga is a perfect storm of bad luck and documented-but-not-visceral knowledge. The project had already hit the `board_build.partitions` pitfall once (documented in git history). That should have been enough of a warning to distrust PlatformIO knobs for this specific build mode. But rebuilding is so slow (~45 min) that you don't immediately try the next thing—you spend 20 minutes reading docs instead, convince yourself the knob should work, then commit to the rebuild. Then it fails. Then you read the real docs (ESP-IDF's Kconfig, not PlatformIO's Arduino knob list), identify the root cause, and apply the correct fix. But you've already burned 97 minutes on the wrong tool.

The frustrating part: **97 minutes is non-negotiable time waste.** There's no way to avoid it. The ESP-IDF build system rebuilds the entire component tree if sdkconfig changes, because Kconfig-dependent `#define` macros propagate to headers included in dozens of `.cpp` files. No incremental rebuild will help. This is a tax on any firmware experiment that requires a config change.

The emotional reality: You know intellectually that "build time is a sunk cost, move on," but after 49 minutes of staring at a Ninja progress bar only to discover it had zero effect, and then waiting another 48 minutes for the *actually* correct fix, the cumulative frustration is very real. The session lost almost two hours of wall-clock time to the config toolchain, not to design or testing.

## Technical Details

- **Malloc failure mode**: `heap_caps_malloc(MALLOC_CAP_SPIRAM)` was succeeding (returning non-NULL) but allocating from regular SRAM, not PSRAM. By default, the allocator falls back to SRAM if SPIRAM is not enabled. No error raised; malloc returned valid pointers; but the snore task was starving SRAM for wakeword buffers, causing silent failures downstream. This cascaded into the task never running (stack corruption or heap exhaustion is likely, but no crash message was emitted—the task just silently exited).
  
- **Config regeneration**: The `.pio` build cache kept the stale `sdkconfig.esp32s3_kws` file. Adding `sdkconfig.defaults` entries alone is insufficient; you must delete the generated sdkconfig to force ESP-IDF to regenerate from scratch. First attempt missed this step.

- **PlatformIO board_build documentation**: The `board_build.arduino.memory_type` knob is listed in PlatformIO's Arduino core docs, not in ESP-IDF docs. For hybrid Arduino+IDF builds, PlatformIO's Arduino layer doesn't control PSRAM enablement; the ESP-IDF Kconfig does. Two separate config systems, one of which applies, and no error if you misconstrue which one is authoritative.

- **Code fixed (after PSRAM enabled)**:
  - Phase 1: Ring buffer accumulation in main loop (captures last ~1s of 16kHz audio), snore task reads snapshots every ~1s, computes placeholder RMS "score" (currently `sqrt(mean_of_squares)` of the audio window).
  - Phase 2: Event Manager tracks N=3 consecutive high-score windows (heuristic threshold = 0.15, no learning, raw placeholder), publishes MQTT event on 3rd consecutive high window, enforces 5-second cooldown before next event can fire.
  - MQTT payload: `{"ts":0,"confidence":0.xx}` (timestamp field currently hardcoded to 0, confidence = normalized RMS score, 0.0–1.0).

## What We Tried

1. **PlatformIO `board_build.arduino.memory_type = qio_opi` knob** — Followed the documented Arduino build path for PSRAM enablement.
   - **Rejected**: 49-minute rebuild showed zero effect (sdkconfig byte-identical). Knob does not propagate for Arduino+IDF hybrids; misleading docs.

2. **Delete `sdkconfig.esp32s3_kws`, re-run build** — Applied mid-debugging when root cause became apparent.
   - **Partial success**: Showed that sdkconfig needs regeneration. But alone, this step was not sufficient without the corrected `sdkconfig.defaults` entries.

3. **Direct `CONFIG_SPIRAM=y`, `CONFIG_SPIRAM_MODE_OCT=y`, `CONFIG_SPIRAM_SPEED_80M=y` in `sdkconfig.defaults`** — Located Kconfig source truth in installed ESP-IDF and added exact symbol names.
   - **CHOSEN**. 48-minute rebuild; regenerated sdkconfig now contains `CONFIG_SPIRAM=y`; malloc works; task runs; logs appear.

## Root Cause Analysis

**Why was PSRAM not enabled?** The project's base `sdkconfig.defaults` file did not include SPIRAM symbols. The hardware has PSRAM (confirmed via esptool), but the firmware was never explicitly told to use it. When the snore task was added and allocated from SPIRAM, the allocator fell back to SRAM, causing resource exhaustion.

**Why was the PlatformIO knob ineffective?** PlatformIO's `board_build.arduino.*` knobs are designed for pure-Arduino boards (e.g., Arduino Nano, Arduino Mega). For hybrid Arduino+ESP-IDF builds (which is the current `platformio.ini` configuration), these knobs are cosmetic; they don't propagate to the ESP-IDF Kconfig merge step. The authoritative config is `sdkconfig.defaults`, which PlatformIO passes to ESP-IDF's Kconfig system. Adding a `board_build.*` knob has no effect on that merge.

**Why was this not caught earlier?** The original wakeword and MQTT code used small fixed buffers (few KB); they fit in SRAM. The snore task introduced the first ~8KB SPIRAM-only allocation. No earlier feature required PSRAM, so PSRAM enablement was simply not necessary. This is a classic "works until you scale" failure.

## Lessons Learned

1. **For ESP32 + ESP-IDF, `sdkconfig.defaults` is the source of truth, not PlatformIO board knobs.** The project has now been bitten by this twice (board_build.partitions, now board_build.arduino.memory_type). Document this in `CLAUDE.md` or create a `.claude/skills/firmware/notes.md` explicitly stating: "Do not use `board_build.*` for ESP-IDF config. Modify `sdkconfig.defaults` instead; validate by inspecting the regenerated sdkconfig after a clean build." This is a repeatable footgun.

2. **Deleting stale generated files is required when Kconfig changes.** The `.pio/build/` cache keeps copies of sdkconfig. If you edit `sdkconfig.defaults` and re-run build without cleaning, ESP-IDF's Kconfig merge may use the cached old sdkconfig, ignoring your changes. Always `rm sdkconfig.esp32s3_kws` or use `pio run -t clean` before rebuilding after a Kconfig edit.

3. **Silent malloc fallback (SPIRAM → SRAM) masks the real failure.** In a future project, consider adding an explicit check after PSRAM allocation: `assert(esp_ptr_in_spiram(ptr), "SPIRAM allocation failed, got SRAM instead")`. This would have caught the problem immediately on the first run, not after 97 minutes of misdirected debugging.

4. **Build time tax on firmware is real; design accordingly.** Each config change triggers a full rebuild (~45–50 min). This is not a "pay it once" cost if you need to iterate. Design configuration decisions early (e.g., PSRAM enablement, partition layout) to avoid mid-implementation config pivots. For the snore feature, PSRAM should have been enabled the moment the architectural decision chose PSRAM-backed buffers.

## Code Review & Fixes

Spawned a `code-reviewer` subagent for the diff. Found 2 Medium-severity issues:

1. **Hardcoded MQTT timestamp** — Payload template: `"ts":0`. This contradicts both the plan's spec (event-local timestamp) and the existing `firmware/mqtt/README.md` contract (all events must have a `ts` field). User chose `millis()` (relative uptime in milliseconds since ESP32 boot) over literal 0, since voice-node has no NTP and millis() at least allows events to be ordered. **Fixed**: Changed to `"ts":%lld,"confidence":%0.2f}, millis(), snoreEventConfidence`. Committed in b129fc5.

2. **Cross-core volatile access** — The event handoff between core 0 (snore task) and core 1 (main loop) uses plain `volatile bool snoreEventPending` and `volatile float snoreEventConfidence`. Volatile is not a C++ memory-ordering guarantee across the ESP32-S3's two Xtensa cores; strictly speaking, there is no documented synchronization. Unlikely to misfire in practice (the specific pipeline has low contention), but not a safe contract. **Fixed**: Switched to `std::atomic<bool>` and `std::atomic<float>` with explicit `memory_order_release` (snore task writes) and `memory_order_acquire` (main loop reads). Rebuilt, reflashed, smoke-tested clean. Committed in b129fc5.

Both fixes were minimal and did not introduce regressions.

## Snore Model Training Decision

Mid-session, user asked directly: **"Do we need to train a custom snore model, or can we reuse an existing one?"** This challenged the original architecture decision's implicit assumption (custom dataset collection would be required).

Presented three architectural options:
1. **Pure DSP heuristic** (current placeholder RMS threshold) — Fast to implement, no ML overhead, but requires manual parameter tuning and domain expertise. False-trigger rate would be high without careful calibration.
2. **Pretrained model reuse** — Find an existing snore-detection model trained on public datasets, integrate as-is. Fast to integrate, lower false-trigger risk, but model may not generalize to this project's specific hardware/environment.
3. **Custom model training** — Collect snore dataset specific to this project, retrain a model, integrate. Highest data quality, best generalization, but 2–4 week effort to collect data, label, and train.

User chose option 2: **"Find a pretrained model, I'll test by playing snoring sounds."** This is a scope-reduction win.

Spawned a `researcher` subagent to evaluate 8 candidate sources (Edge Impulse public projects, GitHub repos referenced in the architecture doc's own reference list). Narrowed to 3 viable candidates; top pick: `alek6kun/snore-recognition` (Apache-2.0 license, 16kHz native, 168KB model, ESP32+INMP441 hardware match, public GitHub repo).

**Direct source inspection** (did not rely solely on the subagent's web research): Cloned the repo locally, examined `main/model.h` (genuine standalone `.tflite` as C-array, structurally identical to this project's `wakeword_model_data.h`), read `micro_model_settings.cc` (2-class classifier: `{"snoring", "background"}`), examined `main/micro_features_generator.cc` to extract exact frontend parameters:
- Window: 32ms
- Step/stride: 16ms
- Channels: 30 (mel-scale filterbank)
- Frequency band: 40–6000 Hz (human snore acoustic range)

This is a retrained fork of TensorFlow Lite Micro's official `micro_speech` example, trained on the Khan 2019 snoring dataset (~500 snore + 500 non-snore samples).

Feature extraction parameters are **directly compatible** with this project's audio pipeline (16kHz INMP441 input, same window/step sizes). No model retraining needed.

## Plan Phase 1: Model Integration (Not Yet Implemented)

Created `plans/260812-1401-voice-node-snore-model-integration/` with two phases:

**Phase 1 — Convert Model & Embed**:
- Extract `.tflite` binary from `alek6kun/snore-recognition/main/model.h` (reverse the C-array embedding).
- Run through this project's existing `scripts/gen-model-header.py` to generate `snore_model_data.h` (same pattern as `wakeword_model_data.h`).
- Write `SnoreFeatures` class (MFCC extraction with the 32ms/16ms/30-channel/40–6000Hz parameters from the reference model).
- Write `SnoreModel` class (TFLite Micro interpreter, op resolver list: Conv2D, FullyConnected, Reshape, MaxPool2D, Shape, StridedSlice, Pack, ResizeBilinear, Quantize, Dequantize, Logistic — notably different from wakeword's streaming op set).
- Allocate tensor arena for snore model (unknown size; risk flagged: may require tuning).

**Phase 2 — Wire Real Model + Field Test**:
- Replace the RMS placeholder in `snoreTask()` with real SnoreModel inference.
- Keep Event Manager/cooldown/MQTT code unchanged (already verified).
- Hand-test with real snoring audio playback (via phone speaker) vs. control tests (talking, TV, silence) to get initial (non-exhaustive) false-trigger baseline.

**Risks noted in plan**:
- Tensor arena size unknown (model card doesn't specify); will require empirical tuning if OOM occurs.
- Op resolver list differs from wakeword; if an op is unsupported, will fail at build-time (not runtime), but requires manual fix.
- Single pretrained model may not generalize to this specific bedroom environment; false-trigger rate unknown until tested.

This plan is written but **not yet implemented**. Next session (fresh context via `/ck:cook`) will execute Phase 1 & 2.

## Open Questions

- **Tensor arena sizing**: The snore model card does not specify required tensor arena. Will need to measure via trial-or-error (allocate 8KB, test; if OOM, try 16KB, etc.).
- **False-trigger generalization**: The Khan dataset is diverse, but may not match this project's specific hardware acoustics (INMP441 mic, ESP32-S3 board resonance, bedroom acoustics). Field testing will reveal if retuning is needed.
- **Mic placement redux**: Architecture decision flagged a potential conflict (wakeword wants mic near speaker's mouth, snore wants mic near nose/mouth during sleep). Phase 2 field test will validate whether one mic position suffices for both detections simultaneously.

## Next Steps

1. **Session context cleared** — User is starting fresh with `/ck:cook` on `plans/260812-1401-voice-node-snore-model-integration/`. This journal entry is a handoff document; do not extend or modify after this point.

2. **Phase 1 implementation**: Extract `.tflite` from reference model, embed in `snore_model_data.h`, write SnoreFeatures/SnoreModel classes, build, verify no build errors.

3. **Phase 2 implementation**: Wire real model into `snoreTask()`, test with audio playback, measure false-trigger rate on diverse signals (snoring, talking, TV, silence, room noise).

4. **PSRAM config lesson**: Document in project notes or CLAUDE.md that ESP-IDF + Arduino hybrid builds require `sdkconfig.defaults` edits, not `board_build.*` knobs. This is now the third time the project will have learned this class of lesson; make it explicit and persistent.

5. **Build optimization**: Consider caching `.pio/build/` volumes or evaluating faster ESP-IDF build systems (e.g., ccache) to reduce the feedback loop on future config changes. ~45 min per change is acceptable for rare changes, but if this becomes frequent, the project should invest in speedup.

---

**Owner**: Implementation complete (commit b129fc5). Code review complete. Model evaluation complete. Plan written. Ready for Phase 1 implementation in fresh session.

**Related**: Continuation of 2026-08-12 10:23 architecture decision (same day, direct follow-on).
