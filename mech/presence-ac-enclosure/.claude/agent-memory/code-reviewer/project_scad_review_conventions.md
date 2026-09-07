---
name: project-scad-review-conventions
description: OpenSCAD enclosure files (vo-hop-*.scad) in mech/presence-ac-enclosure — review conventions and a recurring defect class to check
metadata:
  type: project
---

The `mech/presence-ac-enclosure/vo-hop-*.scad` files (voice-radar, sleeppad-c3, modular) are
parametric CGAL-manifold enclosures verified via `openscad -D 'part="<x>"' -o out.stl file.scad`
and grepping for `Simple: yes` in stderr. There is no test framework beyond this — CGAL manifold
validity + hand-verified `echo()` output + a custom `probe()` module (intersection-based checks for
sealed walls / hardware collisions) are the only correctness signals.

**Established convention, not scope creep**: permanent `echo()` statements left at the bottom of
the file printing computed invariants (e.g. component clearance distances, computed keepout
segments) are intentional self-checking documentation, matching an existing pattern (radar-to-USB
clearance echo predates the reviewed diff). Do not flag these as leftover debug output.

**Recurring defect class to check in future phases of this file family**: decorative
groove/keepout code tends to duplicate a real cutout's dimension as a bare literal instead of
referencing the same named variable (e.g. IR hole `d=6.5` duplicated between the actual cutout
cylinder and a `ir_hole_d` variable used only for keepout math; USB-C door half-width `6` duplicated
similarly for the S2 door). This is a latent silent-divergence risk: OpenSCAD has no exceptions, so
if only one copy is updated later, the decorative cut can silently overlap or fail to clear the real
opening without any render error. Worth grepping for repeated literals between `base()`/`lid()`
`difference()` cutouts and any decorative-keepout section in future reviews of this file.

Verification technique used successfully: independently re-render `intersection(){ base(); ghosts();
}` (or similar probe) against both `HEAD:<file>` and the working tree via `git show HEAD:path >
/tmp/orig.scad` + a throwaway `use <...>` wrapper script, then `cmp` the resulting STLs — confirms
"pre-existing, unaffected by this diff" claims byte-for-byte rather than trusting the author's
self-report.
