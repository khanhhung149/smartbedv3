# Phase 04 Review — Alert Engine + FCM + Family Sharing

Scope: 11 files, 830 LOC. All files <200 LOC, ok.

## CRITICAL

### C1. Re-invite after accept wipes `shared_with_id` and breaks access (`sharing/service.py:26-36`)
`ON CONFLICT ... DO UPDATE SET shared_with_id = EXCLUDED.shared_with_id` overwrites with NULL if owner re-invites same email *before* the invited user registered. Since the share was already `accepted=TRUE` (not reset), `accepted=TRUE AND shared_with_id=NULL` is an inconsistent state. Worse: if invited user *had* registered and accepted, a re-invite (benign UI action) also nulls `shared_with_id`, silently revoking access — `list_shared_with_me` filters on `shared_with_id = $1` and returns nothing; `user_can_access_device` also fails. Fix: in ON CONFLICT, guard with `WHERE device_shares.accepted = FALSE`, or `COALESCE(EXCLUDED.shared_with_id, device_shares.shared_with_id)`.

### C2. Orphan thresholds keep alerting revoked users (`sharing/service.py:98-111`)
`delete_share` does not delete `alert_thresholds` for the revoked user. Alert engine `_tick` joins `alert_thresholds → users` with no access check, so revoked user keeps receiving FCM + alert rows indefinitely. Also breach of scope: `/alerts/{id}/history` is gated by `user_can_access_device`, but DB rows accumulate for someone with no access. Fix: delete `alert_thresholds (device_id, user_id)` in same transaction as share delete, or filter `_tick` by joining against `devices` + `device_shares` accepted OR owner.

## HIGH

### H1. `create_invite` raises on same-session retry (`sharing/service.py:26`)
If owner invites an email that both (a) belongs to no user, and (b) already has a row — fine, upsert handles. But if the existing share row exists from a prior run and `invited_user` is NULL, `INSERT ... RETURNING` still works. No bug, but combined with C1 this is the failure path. Recommend adding test for "invite twice, second time still returns valid pending row".

### H2. Alert engine `_tick` unbounded scan (`alerts/engine.py:46-58`)
Loads *every* `alert_thresholds` row each tick and loops per row. At N devices × M users each, this is O(N·M) sequential queries (last-minute data pulled per threshold row, not per device). Two shared users on one device → 2 identical `min_data` scans. Fix: group by device_id, fetch last-minute aggregates once per device, then iterate per-user thresholds against that aggregate. Moderate urgency — works fine at POC scale but grows poorly.

### H3. `user_can_access_device` hot-path join (raised by task)
Called on every WS frame + every data endpoint. The query is indexed (`idx_shares_shared_with`) so it's fast, but still 1 RTT per check. Acceptable for now; consider caching in Redis (`access:{user}:{device}` TTL 60s) if traffic grows. Not blocking.

### H4. Dedup fail-open reasonable, but race window exists (`alerts/engine.py:111-116`)
If two ticks overlap (slow DB causes tick N+1 to start before N finishes), Redis SET NX still provides correctness — good. However `asyncio.wait_for(stop.wait(), timeout=60)` guarantees serial ticks within one process, so no real race. Multi-worker deploy would need Redis-based leader election. Note for future scale-out.

## Suggestions

- **S1.** `update_threshold` dynamic SET is safe (keys validated by Pydantic model fields, not free text). Defense-in-depth: assert `set(changes).issubset(ALLOWED_COLS)` before building SQL.
- **S2.** `delete_share` uses `result.endswith(" 1")`. asyncpg does return `"DELETE N"` (documented), so correct — but fragile. Prefer `result == "DELETE 1"` or `int(result.split()[-1]) > 0` for clarity.
- **S3.** `fmean([])` cannot occur — `hrs` / `rrs` guarded by `if hrs:` / `if rrs:`. Confirmed safe.
- **S4.** `_fire_alert`: FCM `send_push` is sync and called from async context. Blocks event loop on slow network. Wrap in `asyncio.to_thread(send_push, ...)` or mark engine tolerance for 1–2s stalls.
- **S5.** `accept` endpoint: second query to fetch `device_id` after accept is redundant — `accept_invite` already `RETURNING device_id` but discards it. Return it, save a round-trip.
- **S6.** `list_shares_for_device` endpoint has no 404 when device doesn't belong to caller — returns `[]`. Acceptable but consider explicit 404 for parity with other endpoints.
- **S7.** Shutdown: cancelled in-flight `INSERT INTO alerts` is safe (asyncpg rolls back), FCM send is fire-and-forget — no partial state. Good.
- **S8.** FCM no-op behavior is correct; `send_push` returns False on all failure paths without raising — alert engine unblocked.

## Unresolved Questions

1. Should revoking a share also delete prior alert history rows for that user, or keep for audit?
2. If invited email belongs to multiple registered users (should be unique, but DB has no constraint shown) — confirm `users.email` has UNIQUE constraint.
3. Intended behavior when owner PUTs thresholds with all-None body? Currently no-ops and returns current row — acceptable but undocumented.

**Status:** DONE_WITH_CONCERNS
**Summary:** Phase 04 works end-to-end but has two correctness bugs around the `device_shares` lifecycle (C1 upsert clobbers accepted state; C2 revoke leaves orphan threshold rows that keep alerting). Engine fan-out is O(N·M) — fine now, plan to fix before scale.
**Concerns/Blockers:** C1 and C2 should be fixed before shipping multi-user scenarios; H2 before production load.
