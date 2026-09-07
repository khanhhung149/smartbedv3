# Claude Code Setup Guide

## Overview

SmartBedV3 project includes a comprehensive Claude Code configuration with:
- **Rounded Pill statusline** (macOS-style UI)
- **ClaudeKit integration** (plan tracking, session state, hooks)
- **Project-specific rules & development guidelines**

All new projects should replicate this setup for consistency.

## Quick Setup

### For New Projects

```bash
# From smartbedv3 root:
./new-project.sh /path/to/new-project
```

This copies `.claude-template/` → `new-project/.claude/` with all:
- Statusline configuration (Rounded Pill enabled)
- Development rules
- Hook system
- Project metadata

### Manual Setup (Alternative)

```bash
cp -r /mnt/d/smartbedv3/.claude-template /path/to/new-project/.claude
```

### After Setup

1. Restart Claude Code (close all tabs)
2. All new tabs will show **Rounded Pill statusline** ✅
3. Customize `.claude/.ck.json` if project needs different settings

---

## Global Configuration

**User-level statusline** (`~/.claude/statusline.cjs`):
- Updated with Pill support
- Serves as fallback for projects without `.ck.json`
- No changes needed unless adding new global features

---

## Statusline Features

### What Shows

| Element | Status |
|---------|--------|
| Directory path | ✅ Always |
| Git branch | ✅ If in git repo |
| Model name | ✅ Always |
| Context % | ✅ If available |
| Plan label | ✅ If `.ck.json` present |
| Session state | ✅ If `.ck.json` present |
| Usage windows | ✅ If `.ck.json` + quota available |

### Display Mode

Configurable in `.claude/.ck.json`:
```json
{
  "statusline": "full",        // "full" (default) | "compact" | "minimal" | "none"
  "statuslineLayout": {
    "pillStyle": true          // Enable Rounded Pill
  }
}
```

---

## Project-Specific Customization

Edit `.claude/.ck.json` to override defaults:

```json
{
  "statusline": "minimal",     // Reduce verbosity
  "statuslineColors": false,   // Disable colors
  "plan": {
    "namingFormat": "{date}-{slug}"  // Custom plan naming
  }
}
```

See `.claude/.ck.json` in smartbedv3 for all available options.

---

## Troubleshooting

### Pill UI not showing
1. Ensure user-level statusline updated: `cp ./.claude/statusline.cjs ~/.claude/statusline.cjs`
2. Restart Claude Code (close all tabs)
3. Open new tab → should show Pill

### Project config not loading
1. Verify `.ck.json` exists in project `.claude/` folder
2. Check syntax: `cat .claude/.ck.json | jq .` (must be valid JSON)
3. Restart Claude Code

### Too much/too little info in statusline
- Adjust `statusline` field: `"minimal"` for less, `"full"` for more
- Or hide specific sections in `.ck.json` layout config
