# Firmware Mock Sleep Pad — Code Review

**Scope:** `firmware/src/mock-sleeppad.{h,cpp}`, `firmware/src/main.cpp` mock branches, `platformio.ini` env gate.
**LOC:** mock.cpp 193, mock.h 24, main.cpp 202 (main was already 200 pre-mock; mock added ~10 lines).
**Builds:** both envs SUCCESS, mock delta ≈ 1.6KB flash.

## Protocol correctness — PASS

0x85 frame: preamble(14) + serial(1) + ts(4) + status(1) + hr(1) + rr(1) + sdata(2) + pdata(2) + 0x0D = **27 bytes**, content = **12 bytes**. Matches `decode0x85` expectation (`len != 12` reject). Little-endian ts/sdata/pdata matches decode shift layout (`c[1] | c[2]<<8 | c[3]<<16 | c[4]<<24`).

0x86 frame: preamble(14) + 1+4+1+1+1+1+1+1+2+2 + 0x0D = **30 bytes**, content = **15 bytes**. Matches `decode0x86`. Field order (movement, snore_count, resp_disorder, pthd, temp) matches parser indices c[8]..c[14].

Preamble order [0x7D][type][len_lo][len_hi][10B id] correct per production `send_command()` at main.cpp:28-38.

## Critical issue — Offline backlog burst

**Location:** `mock-sleeppad.cpp:177-193`.

`mock_tick` returns early during Offline (4:00-5:10), but `s_next_sec_ms` is NOT advanced. When scenario wraps to NormalSleep, the signed compare `(int32_t)(now - s_next_sec_ms) >= 0` stays true for ~70 seconds of catchup. Each loop iteration emits one frame and bumps timer by 1000ms, so within a few hundred ms the parser is fed **~70 back-to-back 0x85 frames** (and ~1 bonus 0x86). Effect: MQTT publish burst — PubSubClient TCP buffer pressure, broker rate limits, timeline gaps on backend.

**Fix (one-liner):** when Offline, fast-forward both timers to `now` before returning:
```cpp
if (current_scenario() == MockScenario::Offline) {
    s_next_sec_ms = millis();
    s_next_min_ms = millis() + 1000;
    return;
}
```

## High — Scenario wrap doesn't reset min timer phase

After `current_scenario()` mutates `s_start_ms` on wrap, `s_next_min_ms` keeps its original cadence (it was set once at init to `start+1000` and bumped by 60000 each emit). No functional bug, but min-frame phase drifts relative to the displayed cycle position after each wrap. Low impact for a mock — note only.

## Medium — Serial counter wraps silently

`s_serial` is `uint8_t`, `++` at both emit sites. Wraps at 256. Parser doesn't enforce monotonicity and backend treats it as opaque. Acceptable.

## Medium — `random()` seed collision

`randomSeed(micros())` at `mock_init` — called ~after BLE+WiFi+MQTT, so micros() has entropy. Fine.

## Checks passed

- **Overflow safety:** `(int32_t)(now - s_next_sec_ms) >= 0` handles `uint32_t` wrap correctly (works while drift < 2^31 ms ≈ 24.8 days). ✓
- **`#ifdef` isolation:** `g_mock_parser`, `mock_feed_parser`, `mock_init` call, include — all gated. Production build bytewise identical for non-mock env (flash diff 1644 bytes = mock-only code). ✓
- **Offline semantics:** Redis TTL-based offline detection is the right call; keeping MQTT TCP alive avoids reconnect storms every cycle. ✓
- **Random walk bounds:** HR 55-72 / 128-145, RR 12.0-16.5 rpm clamped — realistic. ✓
- **0x04 monitor-mode + 0x08 heartbeat** still fire in mock — writes to unused Serial2, harmless, preserves boot parity. ✓
- **No shared mutable state races:** all mock state is loop()-thread only, no ISRs. ✓

## Recommended actions

1. **MUST FIX before merge:** Offline backlog fast-forward (see patch above). One-line change, eliminates ~70-frame burst at minute 5:10 of every cycle.
2. Optional: add `Serial.printf("[Mock] scenario=%d\n", (int)s)` inside `current_scenario()` on transition for observability during bench test.

## Unresolved questions

- Does the backend alert engine debounce rapid 0x85 bursts, or would a 70-frame flush trip spurious alerts? (Confirms urgency of fix #1.)
- Should Offline also sever MQTT to simulate realistic network loss, or is TTL-only offline sufficient for POC? (Plan says TTL-only; reviewer concurs.)

**Status:** DONE_WITH_CONCERNS
**Summary:** Protocol layout and `#ifdef` isolation are correct; one real bug (Offline backlog burst) needs a 3-line fix before merge.
**Concerns/Blockers:** Offline→Normal scenario transition floods parser with ~70 backlogged sec frames — fix by fast-forwarding timers on early-return.
