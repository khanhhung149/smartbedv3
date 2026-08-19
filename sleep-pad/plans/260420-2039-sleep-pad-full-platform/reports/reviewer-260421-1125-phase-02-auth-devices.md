# Phase 02 Review — Auth + Device Pairing

**Scope:** `backend/app/` (main, config, database, dependencies, redis_client, auth/*, devices/*). All files <200 LOC.

## CRITICAL

**C1. Login email enumeration via timing (auth/router.py:39-44).** When user not found, bcrypt never runs; attacker measures response time to enumerate emails. Fix: call a dummy verify when `row is None` (e.g. `_pwd_context.dummy_verify()`), then raise the unified 401.

**C2. Lifespan resource leak on Redis init failure (main.py:21-29).** If `_redis_lifespan(app)` raises during `__aenter__`, the already-created `pool` is never closed. Wrap pool setup in try/except-close, or use `AsyncExitStack`:
```python
async with AsyncExitStack() as stack:
    pool = await init_pool()
    stack.push_async_callback(pool.close)
    await stack.enter_async_context(_redis_lifespan(app))
    yield
```

## HIGH

**H1. `_is_online` swallows all exceptions (devices/service.py:72-73).** `except Exception: return False` hides Redis outages, auth errors, network partitions — devices appear offline silently. Narrow to `redis.RedisError` and log.

**H2. No rate limiting on /auth/login or /auth/register.** Credential stuffing + account enumeration + registration spam. Add `slowapi` or equivalent before production; flag as explicit Phase 03+ TODO.

**H3. `jwt_secret` has no minimum-length validation (config.py:18).** Short/empty-but-nonempty secrets accepted. Add `Field(min_length=32)` and validate at startup.

**H4. `/auth/fcm-token` bypasses DI for pool (auth/router.py:65).** Uses `request.app.state.db_pool` directly instead of `Depends(get_db_pool_from_request)`. Inconsistent with every other route; harms testability.

## SUGGESTIONS

- **S1.** Remove dead import `get_redis_from_request` from `main.py:16`; the `# noqa` comment is misleading — it's truly unused there (used in `devices/router.py` directly).
- **S2.** Promote `_is_online` to public `is_device_online` — `devices/router.py:30` imports a private symbol inline to avoid a perceived cycle. There's no actual cycle; just import at module top.
- **S3.** `/devices/pair` always returns 200; consider 201 for new pair vs 200 for rename (return `xmax = 0` trick or separate endpoint). Minor REST nit; current passes tests.
- **S4.** `ON CONFLICT (id) DO UPDATE ... WHERE devices.owner_id = EXCLUDED.owner_id` correctly no-ops on owner mismatch (verified: RETURNING emits nothing → `fetchrow` returns None → `conflict` branch fires). Works, but a deliberate comment in the SQL would help future readers.
- **S5.** 30-day JWT with no refresh/revocation is acceptable for MVP; document in code-standards that logout = client-discard-token until a revocation list ships.
- **S6.** SQL injection: all queries use asyncpg `$N` params — verified safe across both modules.
- **S7.** `/auth/me` returning 401 for deleted user is defensible (token's `sub` is invalid) — keep as-is.
- **S8.** `redis_client.py` `import redis.asyncio as redis` shadows module name. Works but rename to `aioredis` or `redis_async` for clarity.

## Positive

- Pydantic email/length validation at model layer.
- asyncpg parameterization everywhere — zero SQLi surface.
- Bcrypt via passlib (locked versions per CLAUDE note).
- HTTPBearer `auto_error=False` + manual 401 keeps error shape consistent.
- 13/13 integration tests green; no unused runtime imports in business logic.

## Unresolved Questions

- Should registration be rate-limited now (Phase 02) or deferred to Phase 03 alongside MQTT ingress throttling?
- Is FCM token single-device (current schema) or do we need multi-device-per-user before mobile Phase 05?
- Refresh-token / JWT revocation — defer to Phase 05 (mobile) or earlier?

**Status:** DONE_WITH_CONCERNS
**Summary:** Implementation is clean and test-covered; SQL is safe and structure respects 200-LOC limit. Two correctness items (login timing-side-channel, lifespan leak on Redis failure) and four high-priority hardening items should land before any public deploy.
**Concerns/Blockers:** C1 (timing enum) and C2 (pool leak on lifespan failure) are production-blocking and fixable in <20 LOC total.
