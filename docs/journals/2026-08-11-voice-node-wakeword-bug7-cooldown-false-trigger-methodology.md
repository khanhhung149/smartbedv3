# Voice-Node Wakeword: Bug #7 (Missing Debounce) + False-Trigger Test Methodology Decision

**Date**: 2026-08-11 09:15
**Severity**: Medium
**Component**: firmware/voice-node/src/main.cpp, Phase 4 field testing
**Status**: In progress (quiet-baseline capture running; noisy segment pending)

## What Happened

Two live test rounds on physical ESP32-S3 board running the "Vừng ơi" wakeword model (Phase 4, Step 2).

**First round (30 spoken "Vừng ơi" utterances counted by mouth)**: Serial log showed 51 TRIGGER events — far more than utterances spoken. This was diagnostic of a state-machine leak.

**Root cause identified (Bug #7)**: When `voiceState` transitioned from STREAMING back to LISTENING after `SILENCE_MS` milliseconds of inactivity, the wakeword inference score wasn't gated by any cooldown. The trailing ML-model output from the same utterance was still resonating in the numerical score; the state-flip wasn't accompanied by a score-reset, so a single utterance's residual score fired multiple consecutive TRIGGER events over ~100-200ms.

**Fix applied**: Added `WAKEWORD_COOLDOWN_MS = 1200` constant and `wakewordCooldownUntilMs` guard in `main.cpp`. Once triggered, the firmware blocks new TRIGGER events until 1.2 seconds have elapsed. Retest with same methodology: 30 counted utterances → **22 TRIGGER events = 73.3% true-positive rate**. Near-misses (score 0.5–0.8) only 3/log-lines; rest were clear misses (score much lower), so threshold not lowered based on this data.

## The Brutal Truth

The core test procedure — **false-trigger measurement over ≥2 hours in the real install location** — has a methodological weakness that would have bitten us later. Phase 4 Step 1 spec said: "TV/background music/normal talking in the room, **if any**". The "if any" was meant to capture opportunistic noise, not require us to generate it. But here's the problem: Claude Code has no way to inject realistic bedroom noise (no speaker/microphone to simulate environmental sound). If the physical room happens to be silent for the entire 2-hour capture window (e.g., user is away, room is unoccupied), the false-trigger baseline will be unrepresentative of noisier, real-world conditions where false-triggers are more likely to happen.

That's frustrating because the 73.3% true-positive number is solid, but we'd be flying blind on the false-trigger side.

## Technical Details

- **Bug #7 symptom**: 30 utterances → 51 TRIGGER log lines. Ratio 1.7:1 indicates state-machine aliasing, not occasional misfires.
- **Root cause**: `main.cpp` loop processes wakeword score every 16ms frame. State machine:
  - LISTENING: if score > THRESHOLD, fire TRIGGER and move to STREAMING
  - STREAMING: if SILENCE_MS elapsed, return to LISTENING
  - **Bug**: no `wakewordCooldownUntilMs` guard during the LISTENING→STREAMING→LISTENING cycle, so one utterance's lingering score could fire 3–5 triggers in rapid succession during state recovery
- **Fix**: `wakewordCooldownUntilMs = millis() + WAKEWORD_COOLDOWN_MS` set after each TRIGGER; block new triggers until `millis() > wakewordCooldownUntilMs`
- **Measured TP after fix**: 22 valid triggers / 30 voiced utterances = 0.733 (73.3%). Not 100%, but acceptable for a ML classifier; score distribution analysis shows most misses are hard negatives (score << threshold), not near-threshold; no evidence of threshold being too strict.

## What We Tried

1. **Option A: Keep false-trigger test passive-only** — Capture 2h at install location, rely on whatever ambient noise naturally occurs. Fast, minimal coordination. **Rejected** because silence bias.

2. **Option B: Run quiet baseline + deliberate noise segment afterward** — Keep the already-running 2h quiet-baseline capture (started 09:06 UTC, PID 4878 in this session) as a control. After it finishes, run a separate ~20–30 minute segment where the user manually creates realistic room noise (TV on, background music, talking, walking around, A/C running, etc.). Compare false-trigger rates between quiet and noisy. **CHOSEN**. Adds ~30min of real testing time; provides actionable comparison.

3. **Option C: Scrap 2h baseline, redo full 2h interleaved with natural daily activity** — Most representative of real-world conditions. **Rejected** because it's complex to coordinate, high variance (depend on user schedule), and would waste the already-running 2h baseline.

## Root Cause Analysis

**Why did Bug #7 exist?** The state machine was designed to fire a TRIGGER on score-threshold crossing, then immediately mute further triggers by moving to STREAMING state. But the score itself wasn't gated—only the state was. So if the score "lingers" above threshold for 100–200ms (common for ML-classifier numerical output), and the state-machine is in a transient region (e.g., just returned from STREAMING to LISTENING), the lingering score re-crosses the threshold multiple times before falling. This is a classic embedded-ML gotcha: neural-network outputs decay gradually, not discontinuously.

**Why did the methodology need correction?** Phase 4 Step 1 relied on "opportunistic" environmental noise—whatever naturally occurs during a 2-hour window. But we have no control over that environment (it's passive measurement). In a quiet room (bedtime, unoccupied during day), a 2-hour baseline gives false-trigger rate *under silence*, which is the wrong test condition for a device that should also work in noisy environments (TV on, people talking). We can't simulate that noise in firmware testing without actually playing it in the room.

## Lessons Learned

1. **Firmware: Guard ML-inference output decay.** Don't rely on state transitions alone to prevent multiple triggers from one utterance. Implement a cooldown or score-reset on TRIGGER. Budget: ~2–5 lines of code per trigger type; impact on latency: negligible (1.2s cooldown is well below user-perception threshold).

2. **Measurement methodology: Distinguish what's uncontrollable from what's a feature.** Passive capture (no deliberate stimulation) seems simpler, but it introduces environment-dependent variance. When the environment is silent, you're testing the wrong condition. Deliberately injecting known stimuli (noise, voice patterns) adds complexity but pins the failure mode.

3. **Test methodology must be bidirectional: true-positive + false-positive.** A 73.3% TP rate with no FP baseline is uninformative for threshold choice. We need both numbers before committing `WAKEWORD_THRESHOLD`.

## Next Steps

1. **Wait for quiet-baseline 2h capture to complete** (started ~09:06). Script will auto-exit; logs will show total TRIGGER count over 2 hours of passive monitoring.

2. **Run deliberate noise segment** (~20–30 minutes, user-initiated). Same `scripts/ghi-log-serial-wakeword.py` script; user manually creates realistic room noise (TV/music on, talking, movement, A/C running). Log separately to distinguish from quiet baseline.

3. **Compute false-trigger rates** for both conditions:
   - FP_quiet = TRIGGER_count_quiet / 120 minutes
   - FP_noisy = TRIGGER_count_noisy / (20–30 minutes)
   - Compare; document both in `plan.md` § Phase 4.

4. **Set final `WAKEWORD_THRESHOLD`** using both TP (73.3%, 22/30) and FP rates. Current threshold `0.80` may need adjustment. Criteria: maximize TP while keeping FP < 1 per hour in noisy conditions (or user-specified acceptable rate).

5. **Run end-to-end test** (Step 4): Speak "Vừng ơi, bật điều hoà" in the room; confirm Serial log shows `[ir] Daikin ON` (same AC behavior as before voice-node gating).

---

**Owner**: Phase 4 (field testing) in progress. Quiet capture running autonomously. Awaiting next deliberate-noise segment execution and threshold decision.
