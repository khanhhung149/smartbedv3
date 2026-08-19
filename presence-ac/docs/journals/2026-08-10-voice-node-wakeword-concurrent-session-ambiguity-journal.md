# Voice-Node Wakeword: Concurrent Session Ambiguity and Scope Expansion Decision

**Date**: 2026-08-10 08:43
**Severity**: Medium
**Component**: voice-node firmware, backend LLM integration
**Status**: Proceeding to implementation (Phase 1 cook)

## What Happened

User initiated a brainstorm for voice-node wakeword detection via `/ck:brainstorm`. During the session, a **concurrent Claude Code session (one of two others active in the project)** deleted 34 files from the working tree, including the entire `firmware/voice-node/` directory (main.cpp, CMakeLists.txt, platformio.ini, bootloader binaries, etc.). Data remained safe in git commit ff33137, but the working tree became unreliable as a source of truth.

Scout discovered existing but uncommitted wakeword work: a **Vietnamese custom wakeword "Vừng ơi" trained via the microWakeWord framework** (same framework ESPHome uses), complete with data collection scripts (thu-mau-wakeword.ps1), TTS augmentation (sinh-mau-tts-local.py), tone-quality gate using F0 pitch analysis (kiem-thanh-dieu.py), a Colab training notebook, and a model-to-C-header embedder (gen-model-header.py). A platformio.ini env `esp32s3_kws` on ESP-IDF+Arduino had been proven to compile and boot on hardware with inference benchmarked at **5.4ms (budget 30ms, arena 26KB)**. However, **the trained .tflite model was never wired into main.cpp's loop() — only the toolchain was verified feasible.**

## The Brutal Truth

This is maddening because the most valuable part of the work — training a custom Vietnamese wakeword — **already exists but is orphaned**. The model inference framework, the training infrastructure, even a Colab notebook are all there. But nobody actually finished the integration, so a developer looking at main.cpp sees no reference to wakeword at all. It looks like a blank slate. Compounding this: concurrent sessions actively corrupting the working tree while we're trying to make decisions creates genuine uncertainty about whether we're working with stale data or if the state is about to change again.

The feature I'm most nervous about: **MFCC/spectrogram feature extraction parity**. If the C++ firmware computes features differently than the Python training pipeline, the model will silently fail to wake—false negatives indistinguishable from a dead battery or unplugged mic. No error message, no stack trace, just "it doesn't work." This is the classic silent-failure mode for embedded ML on microcontrollers.

## Technical Details

- **Existing model path**: Unknown; not yet located in working tree or git history. Phase 1 must verify it exists.
- **Feature extraction risk**: gen-model-header.py suggests a model was generated, but no C++ feature extractor implementation exists in main.cpp. Training was via microWakeWord (MFCC input, [1,3,40] tensor shape). Firmware must replicate those exact MFCC bins, frame stride, window function, and preprocessing.
- **Dependencies gap**: platformio.ini env `esp32s3_kws` lists no `esp-tflite-micro` in dependencies.lock — inference code has nowhere to run yet.
- **Working tree state**: 34 deleted files, but git show HEAD:firmware/voice-node/* is accessible. Scout read them to verify last-known-good state.

## What We Tried

1. **Abort and clarify**: Ask user if concurrent session corruption invalidates the whole session. 
   - Rejected. User chose to proceed; concurrent interference is an operational risk, not a decision blocker.

2. **Conservative scope (AC on/off only)**: Keep voice-node as a simple state machine—detect wakeword, stream audio, backend returns AC command.
   - Rejected. User expanded to free-form conversation: wakeword wakes board → stream audio → Whisper transcription → **Gemini LLM for open-ended replies** → logged to new SQLite table → shown in Flutter app chat. AC control stays in the fast path via ParseVietCommand; anything unmatched goes to LLM (but LLM never controls AC, avoiding two-logic-layer conflicts).

3. **TTS response on speaker**: Voice reply back to user via speaker.
   - Rejected. No speaker on the hardware; replies are text-only in the Flutter app.

4. **IR receiver utilization**: Use the combo module's IR RX for learning arbitrary remote codes.
   - Rejected. Out of scope for this phase; IR TX stays, RX goes unused.

## Root Cause Analysis

**Why the concurrent-session ambiguity?** User likely running multiple interactive Claude Code sessions in parallel on the same repo to explore different angles. WSL file deletion was rapid (likely a git checkout or worktree prune). This is a real operational hazard in multi-agent workflows: no central lock, git working tree is shared, file mutations race against each other.

**Why wakeword integration was abandoned?** Training completed (Colab + scripts), model generated (gen-model-header.py convention suggests .h file exists or was planned), but nobody finished the firmware loop integration. Classic project debt: the hard exploratory work is done, but the boring integration never closed.

**Why feature-extraction parity is the hidden risk?** MFCC computation has many degrees of freedom: FFT size, hop length, number of cepstral coefficients, window type, energy normalization. A 1-bin mismatch silently breaks the model. Python training defines these params (likely in a config file or notebook cell). C++ firmware must replicate them EXACTLY. No compile-time check catches this.

## Lessons Learned

1. **Concurrent session corruption is real.** For risky multi-session work, establish a working-tree ownership protocol or run sessions sequentially. Concurrent Claude Code + git checkout = race condition.

2. **Verify feature-extraction parity BEFORE trusting on-device inference.** This is not a "run a test and iterate" problem. Feature-param mismatch requires a numerical validation step: extract 100 audio samples in Python, compute features, save them; extract the same audio in C++, compute features the same way, diff the arrays. Pixel-perfect match required. Budget Phase 2 for this.

3. **Don't let training output sit. If you train a model, wire it into production in the same effort cycle.** Orphaned models are technical debt that compound: future developers don't know if the model is stale, if the training succeeded, or if it's even being used.

4. **Expand scope explicitly, document rationale.** User moved from "simple AC voice control" to "free-form LLM conversation"—this changes security boundary (LLM gets user queries), cost model (Gemini API calls), and failure modes (LLM errors now visible in app chat). Brainstorm report captured this, but a future developer should see it in commit message + docs too.

## Next Steps

1. **Phase 1 (cook)**: Run `/ck:cook` on plan `plans/260810-0843-voice-node-wakeword-gate/` to execute Phase 1 investigation:
   - Confirm model file exists in git history or working tree (git show HEAD:firmware/... or locate .tflite).
   - Extract exact feature-extraction parameters from Colab notebook (FFT size, hop length, mfcc_num, etc.).
   - If no model found, hard-stop and report back before proceeding to Phase 2.

2. **Phase 2 (pending Phase 1)**: Implement C++ feature extractor in `firmware/voice-node/src/main.cpp` using esp-dsp; validate against Python training pipeline frame-by-frame.

3. **Resolve working-tree state**: Phase 1 cook will ask user before any git operations; do not proactively restore deleted files.

4. **Backend Scope 2 (deferred)**: LLM integration (Gemini API client, SQLite schema, Flutter app chat tab) scheduled for separate plan after voice-node firmware is proven.

---

**Owner**: Proceeding to implementation phase once user is ready. Session ended at user's request; fresh session will run cook when user initiates.
