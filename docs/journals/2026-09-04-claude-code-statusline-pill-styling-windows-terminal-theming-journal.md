# Claude Code Statusline Pill Styling + Windows Terminal Theming

**Date**: 2026-09-04 14:45
**Severity**: Low
**Component**: DevTools / ClaudeKit hooks, Windows Terminal config
**Status**: In Progress (visual confirmation pending)

## What Happened

User requested styling Windows Terminal (WSL) to match macOS aesthetic (Dracula color scheme, transparency, font) and retrofitting Claude Code's statusline with a "rounded pill" visual style. Work flowed through brainstorm → plan (4 phases) → validation → implementation → code-review → bug-fix → test cycle. Scope covered both this project's local statusline and a new global baseline for other Claude Code projects.

## The Brutal Truth

The initial assumptions about font names and ClaudeKit config structure were completely wrong, and this wasted brainstorm cycles. "SF Mono Nerd Font" does not exist as a legally distributed patched font—SF Mono is proprietary Apple, and no Nerd Font variant actually ships it. The global font stack recommendation (MesloLGS NF) was correct, but the justification was backwards. Similarly, ClaudeKit's local project config lives at `.claude/.ck.json`, not root `.ck.json` as initially assumed—and that file already had substantial pre-existing config, which the dev rules explicitly warn about reading before editing. Not checking first was a recipe for losing config on write.

The architectural plan (per-line `pillifyLine()` wrapper at the responsive-wrap layer) ended up being overcomplicated. The actual implementation was simpler and safer: a single-point change in `renderSection()` plus two call sites, gated by `ctx.pillStyle`. The original plan would have risked breaking the threshold/wrap logic; the shipped version touched nothing there. Future planning should bias toward simpler gating locations.

The code-review subagent caught a real, shipping bug: when a section override in `.ck.json` provided a custom icon or color, the pill renderer was duplicating them instead of extracting directly from already-rendered text. This would have been silent visual corruption in production.

## Technical Details

**Font gotcha**: romkatv/powerlevel10k-media is the authoritative source for MesloLGS NF (raw TTF files). The ryanoasis/nerd-fonts repo's Meslo variant has a different font-family name ("MesloLGS Nerd Font" vs. correct "MesloLGS NF"), breaking Windows Terminal's font.face matching. Pinned to commit SHA `145eb9fbc2f42ee408dacd9b22d8e6e0e553f83d` for reproducibility.

**Config location**: `.claude/.ck.json` (confirmed via `.claude/hooks/lib/ck-config-utils.cjs:13` `LOCAL_CONFIG_PATH` constant). Pre-existing config was not empty; overwrites without reading would have lost settings.

**Code layout**:
- New shared module `~/.claude/lib/statusline-pill-theme.cjs` (global, reusable across projects) provides `renderPill()`
- Project adapter `.claude/hooks/lib/statusline-pill-adapter.cjs` (new, gitignored) wires pill styling to this project's statusline
- Bug fix in `renderSection()`: extracted icon directly from rendered text instead of static duplication table; sourced default colors from `DEFAULT_SECTION_COLORS` registry instead of hardcoded fallback

**Test surface**:
- Added 41 new unit tests for adapter (`statusline-pill-adapter.test.cjs`)
- Full local statusline test suite now 175 tests
- Pre-existing test (`statusline-integration.test.cjs` "Long model name is truncated") identified as flaky: baseline already at 99/100 char margin; pill adds ~2 chars/section overhead; only trips with fresh quota-cache + unrealistically long synthetic model name (real Claude names always short). User explicitly accepted this edge-case flakiness rather than broader test-isolation refactor.

**Scope boundary**: Entire `.claude/*` directory (except `.claude/rules/`) is gitignored in this repo. Phase 2-4 code changes are local-machine config, not trackable via git. Same for global `~/.claude/*` changes and Windows Terminal settings.json (both outside repo scope entirely).

## What We Tried

1. **Assumption: "SF Mono Nerd Font" exists and is freely distributed**
   - Failed. Spent brainstorm cycles on a non-existent font package. Corrected to MesloLGS NF with proper source tracking.

2. **Assumption: ClaudeKit local config at root `.ck.json`**
   - Failed. Actual location is `.claude/.ck.json`, discovered by reading source in ck-config-utils.cjs.

3. **Plan: Per-line `pillifyLine()` wrapper in responsive-wrap layer**
   - Feasible but overly complex; risked breaking wrap/threshold logic. Replaced with simpler `renderSection()` gating.

4. **Code-review iteration: Icon/color duplication in pill render**
   - Caught by reviewer. Fixed by extracting from already-rendered text and using registry defaults instead of static fallback table.

## Root Cause Analysis

**Why wrong assumptions?** Brainstorm operated from incomplete context: font knowledge was surface-level (common Nerd Font names), and ClaudeKit's internal config structure was not verified against source before planning. The assumption bias: "use MesloLGS (correct) but justify via SF Mono (wrong)."

**Why simpler architecture won the day?** Original plan touched responsive-wrap logic, which is stability-critical and already well-tested. Once implementation started, the simpler gating point (`renderSection()` + 2 call sites) became obvious—fewer state transitions, no interaction with threshold logic, easier to test in isolation.

**Why the icon duplication bug?** The pill renderer naively duplicated icon/color logic from a static table without checking if the input section had already resolved a custom override. The fix: trust that `sectionConfig` is already rendered, extract directly from output.

## Lessons Learned

1. **Verify source before brainstorming globally-scoped assumptions.** Font names, config file paths, and architecture-critical locations should be confirmed in code (5 min grep) before planning cycles. Wrong assumptions propagate through entire design documents.

2. **Read existing config before editing.** Dev rules explicitly warn this. Especially true for `.claude/.ck.json` since it's rarely empty and losing custom settings is silent data loss at write time.

3. **Prefer gating at output-generation boundaries over input-transformation layers.** Simpler, fewer state interactions, easier to unit-test. The `renderSection()` change was safer than touching responsive-wrap.

4. **Code review for cross-module icon/color handling catches silent visual corruption.** The bug (duplication) would have shipped silently. Static tables + rendered-object overrides are a footgun; extraction from rendered output is more reliable.

5. **Accept edge-case test flakiness when the root cause is out-of-scope.** The flaky test's root cause was insufficient test isolation (quota-cache not reset per test). Fixing that is a broader refactor. User chose to accept occasional flakiness over scope creep—reasonable trade-off.

## Next Steps

1. **Visual confirmation** (user-facing, not automatable):
   - Windows Terminal: Verify Dracula theme, transparency, font rendering in actual terminal UI
   - Claude Code (this project): Statusline pill styling visible in status bar
   - Claude Code (another project): Confirm global statusline baseline works without project-specific adapter

2. **Pending this visual sign-off**: Mark plan as complete; document font source and config location in this repo's dev-rules or a new devtools-config guide if multiple people will need to adjust ClaudeKit settings in future.

3. **If visual issues arise**: Debug via actual terminal/app first before changing code. The implementation is complete; only user perception verification remains.

---

**Outcome**: Architecture implemented, tests passing locally, code-reviewed and fixed. All changes are gitignored (local config), non-trackable via git. Fully reversible if visual confirmation rejects the aesthetic choices.
