# Brainstorm Report: Claude Code Statusline Rounded Pill Optimization

**Date:** 2026-09-04  
**Status:** APPROVED  
**Decision:** Copy project statusline.cjs → user-level; replicate `.claude/` per-project

---

## Problem Statement

User-level Claude Code statusline (`~/.claude/statusline.cjs`) lacks Rounded Pill support, while project-level statusline (`smartbedv3/.claude/statusline.cjs`) has full Pill + ClaudeKit features enabled. Tabs opened from subdirectories load user-level statusline → no Pill UI, inconsistent experience.

## Requirements

- **Output:** Rounded Pill UI globally available across all projects
- **Acceptance:** All new tabs render macOS-style Pill statusline regardless of working directory
- **Scope:** User-level fallback + per-project replication strategy
- **Constraints:** User maintains multiple projects; wants consistent setup
- **Touchpoints:** `~/.claude/statusline.cjs`, `$PROJECT/.claude/` folder

## Evaluated Approaches

### Option 1: Copy Project Statusline (SELECTED ✅)

**Approach:**
- Copy `/mnt/d/smartbedv3/.claude/statusline.cjs` → `~/.claude/statusline.cjs`
- Replicate `.claude/` folder to each new project
- Project-level config (`.ck.json`) overrides/extends user-level when present

**Pros:**
- ✅ Single copy operation, Pill enabled globally
- ✅ Project statusline is config-driven (safe fallback)
- ✅ Future projects inherit full feature set immediately
- ✅ No manual per-project setup required after initial `.claude/` copy
- ✅ ClaudeKit features (plan tracking, usage windows, session state) available when needed

**Cons:**
- Project-less environments get extra features (git details, session state) when `.ck.json` absent
  - *Mitigation:* Set `statusline: "minimal"` in user settings if verbose output unwanted

**Risk:** None — project statusline gracefully degrades when config missing

### Option 2: Merge Intelligently

**Approach:**
- Keep user-level structure simple
- Selectively add Pill support from project version
- Manual merge for each feature

**Pros:**
- Lightweight user-level fallback
- Explicit control over features

**Cons:**
- ❌ Manual merge labor per update
- ❌ Maintenance burden (two parallel versions)
- ❌ Project features hard to replicate consistently

---

## Final Recommendation

**Strategy: Copy project statusline + per-project `.claude/` replication**

### Implementation Steps

```bash
# Step 1: Upgrade user-level statusline
cp /mnt/d/smartbedv3/.claude/statusline.cjs ~/.claude/statusline.cjs

# Step 2: Close all Claude Code tabs
# (or restart Claude Code app)

# Step 3: For each new project, copy .claude folder
cp -r /mnt/d/smartbedv3/.claude /path/to/new-project/
```

### Why This Approach

1. **Global Pill default** — all tabs render Pill UI via user-level fallback
2. **Project autonomy** — each project can override/customize via `.ck.json`
3. **No per-tab workarounds** — consistent UI regardless of CWD
4. **Scalable** — new projects auto-inherit config by copying `.claude/`
5. **ClaudeKit-aware** — plan tracking, session state, usage windows work out-of-box for projects that need them

### Success Metrics

- [ ] All new tabs show Rounded Pill statusline (no gaps by working directory)
- [ ] Project-specific features (plan label, session state) appear when `.ck.json` present
- [ ] No regression: existing single-project workflows unchanged

---

## Next Steps

1. Execute copy command (Step 1 above)
2. Restart Claude Code (close all tabs)
3. Verify Pill UI renders consistently
4. Document `.claude/` template in project onboarding

**Plan:** Not required — implementation is straightforward copy operations.
