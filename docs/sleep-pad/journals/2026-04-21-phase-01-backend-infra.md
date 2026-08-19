# Phase 01 Backend Infrastructure: Docker Stack Live

**Date**: 2026-04-21 11:21
**Severity**: Low
**Component**: Backend Infrastructure / Deployment
**Status**: Resolved

## What Happened

Phase 01 shipped: Docker Compose stack with TimescaleDB, Redis, Mosquitto, and FastAPI running on dev. All 4 services healthy, /health endpoint responding, 7 tables created with 2 hypertables registered for timeseries data. MQTT pub/sub verified working end-to-end.

## The Brutal Truth

This phase exposed how quickly infrastructure assumptions bite you. We almost shipped two prod footguns: undocumented Mosquitto password bootstrap and FastAPI lacking a compose-level healthcheck. Code review caught both pre-flight. That's the only reason we didn't inherit broken prod secrets and hanging container dependencies on day one.

## Technical Details

- Docker Compose split: `.env.dev` (anon MQTT, LAN IP) vs `.env.prod` (password auth, cloudflared domains)
- pip install timeout on first boot: `files.pythonhosted.org` read timeout. Fixed with `--timeout=120 --retries=5`
- Added `scripts/setup-mosquitto-passwords.sh` to generate hashed passwords from `.env.prod` — closes prod bootstrap loop
- Deferred alembic migration tooling to Phase 02 (no models yet; `init.sql` runs on empty volume)

## Root Cause Analysis

We were too eager to "keep it simple" early. The separate dev/prod split forced us to think through auth strategy, domain routing, and container readiness properly. This was actually healthy friction — it meant we documented the gap rather than buried it.

## Lessons Learned

- Code review on infra prevents prod day-1 surprises
- Document external tooling like password hashing immediately (script lives in repo, not in someone's notes)
- Python Docker timeouts on flaky networks are predictable; build retry logic upfront

## Next Steps

Phase 02: FastAPI auth + device pairing. Auth schema, JWT setup, device registration endpoints.
