# Sync Bundle

Cross-machine state for Sleep Pad project. Pulled by git; restored manually by you (or via `import memory` skill on the new machine).

## What's in here

| Path | What | How to use |
|------|------|------------|
| `memory/` | Claude auto-memory (user/feedback/project entries) | Copy to `~/.claude/projects/-Users-{USERNAME}-projects-sleep-pad/memory/` on the new machine |
| `../session-sync.md` | Last session summary, decisions, pending work | Read first when resuming |
| `../journals/` | Already git-tracked; phase journals + retrospectives | Just `git pull`, nothing to copy |
| `../../plans/` | Already git-tracked; implementation plans + reports | Just `git pull` |
| `../../.claude/rules/` | Already git-tracked; project rules + workflows | Just `git pull` |
| `../../CLAUDE.md` | Already git-tracked; project instructions | Just `git pull` |

## Import on a new machine

1. **Clone or pull:**
   ```bash
   git pull   # or: git clone https://github.com/sonpython/sleep-pad-ai.git
   ```

2. **Restore auto-memory** (path varies by username — replace `michaelphan` with the new machine's user):
   ```bash
   USER_HOME="$HOME"
   PROJECT_PATH="${USER_HOME}/projects/sleep-pad"
   # Claude derives memory path from project path with - replacing /
   MEM_DIR="${USER_HOME}/.claude/projects/-Users-$(whoami)-projects-sleep-pad/memory"
   mkdir -p "$MEM_DIR"
   cp "${PROJECT_PATH}/docs/sync/memory/"*.md "$MEM_DIR/"
   ls "$MEM_DIR"
   ```

3. **Verify:** open Claude Code in the project, ask "what do you remember about me?" - it should reference the imported memories.

4. **Optional:** run `import memory` skill - it reads `docs/session-sync.md` and the auto-memory dir, summarizes pending work.

## What's NOT exported

- **claude-mem cross-session DB** (`~/.claude-mem/claude-mem.db`) - binary SQLite, machine-local, would bloat repo. The salient observations are summarized in `session-sync.md` and the auto-memory files.
- **Conversation transcripts** (`~/.claude/projects/.../*.jsonl`) - 22MB+, machine-local. Not needed for resuming work.
- **Local IDE state** (`.opencode/`, `.claude/settings.local.json`) - gitignored.
- **Secrets** (`.env*`) - gitignored. Re-create per-machine.

## Re-export

Run `export memory` skill on this machine before switching. It will:
1. Refresh `docs/sync/memory/` from local auto-memory
2. Update `docs/session-sync.md` with latest session state
3. Commit + push

## Known per-machine config

- **Mac dev IP:** `192.168.1.15` (mosquitto broker host) - re-check on each machine via `ifconfig | grep 'inet 192'`
- **`.env.dev`** must be re-created in `backend/` (POSTGRES_USER, JWT_SECRET, etc.) - see `backend/.env.example`
- **iOS simulator / Xcode iOS SDK** - 8GB+ download, not in repo
