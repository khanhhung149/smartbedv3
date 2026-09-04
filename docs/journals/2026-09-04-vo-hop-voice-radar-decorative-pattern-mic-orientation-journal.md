# Voice-Radar Enclosure: Aesthetic Reversal + Mic Orientation Hazard Rethink

**Date**: 2026-09-04 16:20
**Severity**: Medium
**Component**: Mechanical / presence-ac-enclosure (`vo-hop-voice-radar.scad`)
**Status**: In Progress (blocked on physical test prints)

## What Happened

This session executed `phase-04` of the enclosure redesign: ported decorative V-groove pattern from `vo-hop-sleeppad-c3.scad` onto `vo-hop-voice-radar.scad` (all 4 walls), added a mic-orientation mark, and verified via headless OpenSCAD. But it started with reversing a reversal made by an earlier session the same day: the morning session had reverted to `vo-hop-modular.scad` as the official file (logic: "it already has 2-board architecture, just needs USB-C door fix"), but this afternoon the user explicitly chose to stay with `vo-hop-voice-radar.scad` instead (logic: "smaller, nicer, 2-piece snap-fit, matches sleeppad aesthetic").

## The Brutal Truth

The decision feels like fighting the "logical" path. Repairing `vo-hop-modular.scad` would have been simpler (file already has everything, just extend/fix one part). Choosing `vo-hop-voice-radar.scad` means keeping the harder route: it's a 2-piece snap-fit with no parametric history, and now we're grafting a complex decorative pattern plus hardware fit-test cycle onto it. But aesthetics matter for a product that sits in a living room, and consistency with the sleeppad file's visual language matters for brand coherence. So the user went for it.

More frustrating: the plan's claim "mic mount not yet added to this file" was stale. Twenty minutes of reading code revealed it was implemented in commit `528efe8` (belfry and pocket already in `module lid()`). We solved a problem that didn't exist, which meant re-scoping what "mic orientation mark" actually meant.

## Technical Details

**Decision reversal context**: Earlier session reasoning was sound (modular.scad has everything), but it missed the user's unstated preference for aesthetic match with sleeppad-c3. No amount of reading code detects preference. This session took it as direct instruction: "keep voice-radar.scad, add the pattern."

**Stale plan discovery**: `phase-02` claimed "mic pocket not yet implemented in vo-hop-voice-radar.scad." Reading `module lid()` lines 300-322 showed `mic_boss_h`, `mic_pocket_d`, and cable-escape khe already present. Verification log in `plan.md` was kept truthful (marked "mic mount exists" once discovered), but a developer reading just `phase-02` would waste time.

**Mic orientation hazard rethink**: Researched public INMP441 specs (Digi-Key datasheet, components101, easyelecmodule) for the round Ø10 board variant. Found: zero public documentation for this specific form factor — it's an AliExpress OEM variant, not the standard breakout. The original plan's hazard description ("mic orientation") conflated two failure modes. Reading the `system-wiring.md` hazard carefully (and handling a physical INMP441 in an earlier session) revealed the real one: **face-flip** — inserting the board upside-down, so the MEMS chip faces the wrong direction. This is not a rotation around the Z-axis; a D-cut keyway on the perimeter physically cannot prevent a face-flip (the board is symmetric when viewed from above). So the original plan's vague proposal "add a rotational keyway/gørre" was a red herring. We'd be machining a solution to the wrong failure mode.

**Decision: external mark + assembly instruction** instead of mechanical keyway. Engraved a small triangle on the lid's outside surface near the acoustic port, plus a one-line code comment in the `lid()` module: "board soldered-side UP toward lid; MEMS chip faces DOWN into acoustic chamber." This is a documentation hazard, not a design hazard — it shifts risk from geometry to procedure, which is honest about what we can control.

**Decorative pattern port**: Copied `van_hong()` verbatim from sleeppad-c3 for left/right walls (no doors to dodge there). For front/back walls (the longer dimension in this enclosure, unlike sleeppad), wrote new `van_truoc_sau()` module using `rotate([0,90,0])` instead of `rotate([-90,0,0])` — rotation axis swaps when you move the extrusion axis from Y to X. Added `van_doan_ho()` function to split the wall into segments around door/sensor cutouts. For the IR hole, chose keepout diameter **6.5mm (hole size)** not 20mm (module PCB width) — the decorative pattern is on the outside surface, module sits deep inside; using module width wastes half the front wall's pattern. Used `echo()` to verify segment spans within the actual file; got expected results (front: 3 segments, back: 2 segments around USB-C doors).

**Verification via headless OpenSCAD**: Rendered isolated test snippets with `openscad` CLI to confirm rotation-axis math before committing code. Checked that `probe("vach-ngan-kin")` (partition wall intersection) stayed empty. Then rendered all 6 part variants (`base`/`lid`/`test-s3`/`test-s2`/`test-radar`/`test-radar-base-wall`) in the actual file, confirmed CGAL `Simple: yes` for all. Did not assume test snippet success = file-level success (common mistake: local geometry is clean but global geometry has tangencies).

**Code-review findings**: Independent review caught two real issues. Medium-severity: keepout constants (`ir_hole_d=6.5`, `s2_usb_door_off`, `s2_usb_door_w`) were defined separately from the cutout dimensions they approximate. If someone changes the door size later, they'd have to update two places — silent-drift risk. Fixed by hoisting the door definitions into shared variables used by both cutout and keepout logic. Low-severity: `van_doan_ho()` function didn't guard against degenerate input (x0 >= x1). Added `assert()`. Re-rendered all 6 parts after fixes; output was byte-identical (changes only renamed variables, no numeric shift).

## What We Tried

1. **Assumption: "Mic orientation hazard can be solved with a D-cut keyway"**
   - Failed conceptually. The hazard is face-flip (vertical), keyway is rotational (horizontal). No mechanical lock can prevent flipping a symmetric round object. Dropped this approach and went with procedure documentation instead.

2. **Assumption: Keep decorative pattern logic separate from cutout definitions**
   - Failed at code-review stage. Duplication of dimensions (IR hole, S2 door) created silent-drift risk. Refactored to use shared variables.

3. **Approach: Render via GUI to verify 4-wall pattern**
   - Works for visual check but is fragile for geometry. Reinforced with headless CLI + CGAL check in the actual file, not just test snippets.

## Root Cause Analysis

**Why the decision reversal?** The earlier session's logic was airtight (modular.scad has everything), but it treated the design as a pure optimization problem. The user had a non-technical reason — aesthetic consistency, product feel, size. That can't be deduced from reading code. When the user stated the preference directly, it changed the scope.

**Why the stale plan note?** Phase-02 was written before implementation in phase-04 verified the mic pocket actually existed. Documentation wasn't kept in sync when the developer (me) discovered the pocket was already done. Should have flagged this in a plan amendment immediately, not let it sit until phase-04.

**Why the mic-orientation rethink?** The original hazard description was right, but the proposed solution (rotational keyway) addressed the wrong mechanism. This happens when you describe a failure mode abstractly ("wrong orientation") without building or holding the actual part. The `system-wiring.md` hazard docs were more careful — they said "MEMS chip must face cavity, not lid" — which translates to face-flip, not rotation. Reading carefully would have caught it sooner.

**Why duplicate keepout constants?** Keeper principle: "keep related numbers close." The keepout array for pattern rendering and the door cutout array are semantically related (they describe the same physical objects), but they live in separate sections of code. Duplication felt "safer" than sharing at the time (local constants are easier to trace), but that safety is illusory — you trade static duplication for dynamic divergence.

## Lessons Learned

1. **Design decisions can't be purely technical.** When a user reverses a previous session's conclusion, don't re-argue the technical merit of the old approach. Listen for the unstated preference (aesthetics, feel, user experience, product positioning). The decision is sound if you accept the stated values.

2. **Stale plan notes are more dangerous than no notes.** If you discover during implementation that a plan claim is wrong, update the plan document immediately. Don't keep working around it thinking "I'll fix it at the end." Future-you (or a team member) will read the plan, see the claim, and waste time.

3. **Hazard descriptions must be precise.** "Wrong orientation" is a category with multiple failure modes (rotation, flip, insertion depth, polarity). When designing a mechanical lock, verify which mode it actually prevents. A D-cut keyway prevents rotation, not flip. Without physical inspection or detailed documentation, you will propose solutions to the wrong problem.

4. **Keep numeric constants shared between related logic.** If two pieces of code (cutout definition + pattern keepout) both depend on the same dimension, make them reference the same variable. Comments like `ir_hole_d  = 6.5  // must match cutout in base()` are admissions that you've split related data. Refactor to eliminate the comment.

5. **Verify geometry at the scale you're building.** Test snippets are useful for proving rotation-axis math, but they don't catch tangencies with the full hardware. Always render the real file with all parts present before claiming CGAL success. The phrase "looks right when isolated" has burned too many assembly engineers.

## Next Steps

1. **Physical handoff** (blocked on user): Export 3 test STL files (done: `test-s3`, `test-s2`, `test-radar` already in `mech/presence-ac-enclosure/`). User must 3D-print all three and verify that S3-CAM, S2 Mini, and radar LD2410C fit without binding. No further code work can de-risk this; only hardware in hand will tell.

2. **Iterate if fit is wrong**: If test prints show interference or gaps, adjust corresponding dimensions in the SCAD file, re-verify CGAL, re-export, re-print. This loop could be 1-3 iterations depending on print shrinkage and measurement tolerance.

3. **Production print gated on test success**: Only after user confirms all 3 test prints fit correctly should we export full `base()` + `lid()` for production print. Until then, `phase-04` stays `in-progress`.

4. **Plan amendment**: Once user completes physical fit-check and confirms `phase-04` success, update plan status to `completed` and document fit-margin tolerance in the plan's Validation Log (e.g., "all parts fit with 0.5mm clearance, no binding observed").

---

**Emotional note**: This phase involved rethinking assumptions (the mic lock doesn't work that way), discovering plan staleness (the pocket was already done), and accepting a design path that's harder but better. The code-review catch on variable duplication felt like a small win — not a catastrophic bug, but a real fragility avoided. The physical test prints are the final gate; everything else is implementation detail that only hardware can validate. That's uncomfortable (can't ship until user prints), but it's the honest engineering discipline: verify assumptions with concrete evidence before committing to production.
