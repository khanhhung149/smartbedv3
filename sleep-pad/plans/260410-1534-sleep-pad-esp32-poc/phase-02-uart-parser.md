# Phase 02: UART Frame Parser

## Priority: High
## Status: Pending

## Overview
State machine to read UART bytes, detect frame boundaries (0x7D start, 0x0D end), validate structure, decode 0x85 and 0x86 frame payloads into structs.

## Key Insights
- Frame format: `[0x7D][type 1B][length 2B LE][ID 10B ASCII][content][0x0D]`
- 0x85 content: 12 bytes — serial(1) + time(4) + status(1) + hr(1) + rr(1) + sdata(2) + pdata(2)
- 0x86 content: 15 bytes — serial(1) + time(4) + status(1) + hr(1) + rr(1) + movement(1) + snore(1) + resp_disorder(1) + pthd(2) + temp(2)
- Respiration rate real value = byte / 10.0
- All multi-byte integers are little-endian unsigned
- Status codes: 0x01=OUT_OF_BED, 0x02=MOVEMENT, 0x03=SIT_UP, 0x04=SLEEP, 0x05=WAKE, 0x06=HEAVY_OBJECT, 0x07=SNORE, 0x08=WEAK_BREATHING

## Related Code Files
- Create: `src/uart-parser.h`
- Create: `src/uart-parser.cpp`

## Implementation Steps
1. Define `SleepPadSecData` struct (from 0x85): status, heart_rate, respiration_rate, sdata, pdata, timestamp
2. Define `SleepPadMinData` struct (from 0x86): all sec fields + movement, snore_count, resp_disorder, pthd, temp
3. Define `SleepPadParser` class:
   - `feed(uint8_t byte)` — accumulate bytes, detect frame start/end
   - Internal buffer (max 64 bytes, largest frame ~30 bytes)
   - On complete frame: validate header 0x7D, check type, decode content
4. Callback mechanism: function pointers for `onSecData` and `onMinData`
5. Status code to string mapping function
6. In main.cpp loop(): `Serial2.read()` → `parser.feed(byte)`

## Todo
- [ ] Define data structs
- [ ] Implement state machine parser
- [ ] Implement 0x85 decode
- [ ] Implement 0x86 decode
- [ ] Status code to string helper
- [ ] Verify compilation

## Success Criteria
- Parser correctly decodes 0x85 and 0x86 frames
- Handles partial frames and garbage bytes gracefully (discard until next 0x7D)
- Logs parsed data to Serial for verification
