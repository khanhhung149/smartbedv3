---
name: Stitch HTML → Flutter pixel-perfect workflow
description: Proven method for converting Google Stitch exports to Flutter, preserving design fidelity
type: feedback
originSessionId: f8363123-ac47-4985-835d-dc4b0d64f072
---
When user exports Google Stitch designs (as `code.html` + `screen.png` per screen), use HTML as ground truth (screen.png is only cross-check). Stitch exports Tailwind CSS with an identical `tailwind.config.theme.extend.colors` block across all screens — extract once into `lib/core/app_colors.dart` as constants, then map Tailwind classes 1:1 to Flutter: `p-5` → `EdgeInsets.all(20)`, `rounded-[20px]` → `BorderRadius.circular(20)`, `text-2xl font-bold` → `TextStyle(fontSize: 24, fontWeight: FontWeight.bold)`, hex colors verbatim.

**Why:** User explicitly requires pixel-perfect match. They chose Stitch to drive the design, so deviating breaks trust. Mapping HTML→Flutter deterministically prevents "interpretation" drift.

**How to apply:**
- Pick one canonical variant for shared widgets (e.g., bottom nav from Home screen — user's rule: first screen's style wins, ignore variations in other HTML exports)
- For 10+ screens, split implementation into sequential agent "waves" (5 screens each) — one agent's context can't hold all HTML + scaffold cleanly
- Deviations allowed only when unavoidable: Stitch CDN illustration URLs (non-distributable → Icon placeholder with TODO), Tailwind `<select>` dropdown for WiFi scan (OS network scan out of scope → text input), stacked bars that need backend schema extension (single-series fallback, flag for backend work)
- File naming: Dart convention is snake_case. Override the backend's kebab-case rule for .dart files. Agents may correct user instructions here — trust them.
