---
status: completed
created: 2026-04-22
completed: 2026-04-22
slug: firmware-sleep-pad-mock
description: ESP32 firmware self-mock for sleep pad data — compile-flag gated, 4 scenarios, protocol-compliant frames
blockedBy: []
blocks: []
---

# Firmware Sleep Pad Mock

## Overview

Add firmware self-mock so ESP32 can generate realistic Legact Pro V2 telemetry without a physical sleep pad. Enables full-platform smoke test with just an ESP32 on the bench.

Gated by compile flag `MOCK_SLEEPPAD` — zero overhead in production `esp32dev` build.

Reference: [Brainstorm report](../reports/brainstorm-260422-0140-firmware-sleep-pad-mock.md)

## Phases

| Phase | File | Status | Description |
|-------|------|--------|-------------|
| 01 | [phase-01-firmware-mock.md](phase-01-firmware-mock.md) | completed | Single-phase: mock module + platformio env + main.cpp integration + build verify |

## Key Dependencies

- Existing firmware at `firmware/` (Phase 05 of platform plan — status=completed)
- `firmware/src/uart-parser.h/.cpp` — reused unchanged (parser exercised via byte-feed)
- `firmware/src/main.cpp` — minor `#ifdef` injection in setup + loop

## Out of scope

- Real sleep pad hardware testing (future, when device arrives)
- Python MQTT publisher (deferred — firmware mock covers smoke-test goal alone)
- Custom scenario duration via build flags (YAGNI — fixed 5m10s cycle)
