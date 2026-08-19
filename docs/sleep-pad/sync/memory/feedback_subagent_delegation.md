---
name: Michael delegates heavy work to background agents
description: User prefers to dispatch long-running phases to background subagents so they can work on other things in parallel
type: feedback
originSessionId: f8363123-ac47-4985-835d-dc4b0d64f072
---
When a phase involves substantial work (>10 min agent time, >15 files, or screen-by-screen implementation), dispatch a fullstack-developer agent in the background (`run_in_background: true`) and tell the user plainly. User will work on unrelated tasks (often the next design in Stitch, or reading docs) while the agent runs. Return notifications arrive automatically — don't poll.

**Why:** User said explicitly "để tôi làm việc khác" (let me do other things) when Phase 05 started. They're time-efficient and hate waiting for foreground agents to finish. Asynchronous dispatch respects their flow.

**How to apply:**
- Background agents for: Phase-level implementation (Flutter screens, firmware rewrites, large refactors, multi-file pixel-perfect UI ports)
- Foreground agents for: code review (need the verdict before continuing), quick fixes (<2 min), finalization steps (project-manager sync, journal)
- Always include detailed context in the async prompt (agent can't ask clarifying questions mid-run)
- When 10+ screens, split into 2 sequential background waves — avoid one agent hitting context limit mid-phase
- After notification, run code-reviewer on the output, fix criticals inline (small), delegate more fixes if large
