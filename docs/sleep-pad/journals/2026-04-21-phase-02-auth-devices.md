# Phase 02 Complete: JWT Auth + Device Pairing Live

**Date**: 2026-04-21 13:47
**Severity**: Medium
**Component**: Authentication, Device Management
**Status**: Resolved

## What Shipped

FastAPI JWT auth + device pairing API live on dev. 7 endpoints (register, login, refresh, device list, pair, unpair, claim). 11 integration test cases passing. Bcrypt hashing, token generation, device ownership enforcement all validated.

## Brutal Truth

This phase exposed how easy it is to ship bugs in async frameworks when you're not obsessing over type hints. Spent 90 minutes debugging a 422 error that turned out to be a missing `Request` type annotation — FastAPI interpreted it as a request body instead of a dependency. That's frustrating because the error message pointed nowhere useful.

## Technical Highlights & Lessons

**FastAPI Dependency Injection Gotcha**: Missing type hints on dependency parameters aren't cosmetic. `get_db_pool_from_request(request)` without `Request` type annotation causes FastAPI to treat `request` as a required body field. Every endpoint rejected with 422. **Lesson**: Type annotations change runtime behavior in FastAPI — they're not optional.

**Passlib + Bcrypt Breakage**: `passlib[bcrypt]` with bcrypt 4.1.0 fails with `AttributeError: module 'bcrypt' has no attribute '__about__'`. This is a known incompatibility. Fixed by pinning `bcrypt==4.0.1`. Documented because this will bite someone again.

**Timing Side-Channel (Caught in Review)**: Login code branched on `row is None` before running bcrypt — attackers could enumerate valid emails by measuring response time (~200ms for real user, near-zero for ghost). Fix: pre-compute a dummy bcrypt hash, call `dummy_verify()` on the no-user branch. Verified response times now match (231ms both paths).

**Lifespan Pool Leak**: If Redis init failed mid-startup, the DB pool would never close. Fixed with `AsyncExitStack` to push cleanup callbacks regardless of downstream failures.

**Device Takeover Prevention**: Pairing uses `ON CONFLICT ... WHERE owner_id = EXCLUDED.owner_id` to atomically reject ownership theft. Verified bob cannot steal alice's device_id (409 Conflict).

## Deferred

Rate limiting (login/register), JWT refresh/revocation, multi-device FCM tokens. Single-user owner model sufficient for Phase 03 testing.

Next: Phase 03 (MQTT subscriber + realtime WebSocket + history).
