# mech/ — CAD

3-plate lift frame. Owner: **anh Khanh**.

| Plate | Position | Function |
|---|---|---|
| Top | Head end | Raise head / upper torso |
| Middle | Wide, torso | Raise / lower torso |
| Bottom | Small | Raise legs |

Small arc, slow speed, low noise. **Slow and small are safety features, not engineering limitations.**

- Lead-screw or ball-screw with a self-locking angle. No pneumatics, no hydraulics.
- Static load 150 kg with a safety factor of at least 2.
- **Recompute force and travel from scratch.** The 500 N / 50 cm figures come from the 2023 ten-point design and mean nothing for a 3-plate configuration.
- Simulate collisions between plates before cutting steel — independently moving plates can still pinch each other at the boundaries.

10-point lift is deferred to Phase 07.
