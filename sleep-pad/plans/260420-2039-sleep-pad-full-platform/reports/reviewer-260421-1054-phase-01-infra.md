# Phase 01 Infra Review

Scope: docker-compose (base/dev/prod), env examples, gitignore, init.sql, mosquitto configs, app Dockerfile/requirements/main.

## CRITICAL

- **Prod FastAPI sends no MQTT creds to broker 1883 listener.** `docker-compose.yml` sets `MQTT_PORT: 1883`, but `mosquitto-prod.conf` disables anonymous on 1883 and requires password. FastAPI subscriber will fail to connect in prod unless `MQTT_USERNAME`/`MQTT_PASSWORD` from `.env.prod` match an entry in `mosquitto/passwords`. No docs or script generates/validates this. Risk: silent prod breakage on first boot. Add a README note + `mosquitto_passwd` bootstrap snippet, and verify creds match.

- **`mosquitto/passwords` mount is required in prod but not validated.** If file missing or wrong mode, Mosquitto refuses to start. `.gitignore` correctly excludes it, but no placeholder/instructions exist. Document: `docker run --rm -v $(pwd)/mosquitto:/m eclipse-mosquitto:2 mosquitto_passwd -c -b /m/passwords $USER $PASS`.

## HIGH

- **FastAPI healthcheck + depends_on gap.** Base compose lacks `healthcheck` on `fastapi`, so `cloudflared: depends_on: fastapi` resolves as "started" not "healthy". Dockerfile has a HEALTHCHECK but compose doesn't reference it. Low blast radius, but tunnel may route traffic before app is ready. Add `condition: service_healthy` or declare healthcheck at compose level.

- **Dev hot-reload mount shadows installed deps location fine, but overwrites `requirements.txt` only on rebuild.** `./app:/app` bind-mount is OK since deps install to site-packages, not `/app`. Confirm team understands adding a dep requires rebuild.

- **`JWT_SECRET` in `.env.dev.example` is literal placeholder** (`dev-not-secret-change-me`). Low-risk but devs copy-paste; at minimum add a comment to regenerate even for dev. Same for `POSTGRES_PASSWORD=devpassword`.

- **`init.sql` runs only on first init** (empty data dir). Any schema change after first boot requires migration tooling (alembic not in requirements). Flag for Phase 02.

- **`alerts.device_id` lacks FK to `devices(id)`** (plan omits it too, but consistency with other tables suggests adding `REFERENCES devices(id) ON DELETE CASCADE`).

## Suggestions

- Add TimescaleDB `chunk_time_interval` tuning on hypertables (default 7d is fine for `sec_data`? High write volume may benefit from 1d).
- Consider `BRIN` index on `sec_data.time` for range scans; current `(device_id, time DESC)` btree handles Phase 03 `time_bucket` queries correctly — acceptance criterion met.
- `mosquitto` base service has no healthcheck; add `mosquitto_sub -E -t '$SYS/#' -C 1` or TCP probe.
- `container_name` hardcoded prevents running dev+prod side-by-side — acceptable for MVP.
- Prod compose has no `restart: unless-stopped` on `cloudflared` — it does (inherits nothing from base since cloudflared is prod-only; explicit is correct, already set).
- `.env.prod.example` `MQTT_DOMAIN=wss://...` good; verify Cloudflare tunnel config enables WebSocket upgrade (noted in plan risk table — track it).
- `pgcrypto` extension added (good, plan didn't specify but required for `gen_random_uuid()` on PG<=16 without default).

## Isolation verdict

Dev/prod cleanly separated via override files + distinct env files + distinct mosquitto configs. Secrets not baked into images (verified: Dockerfile `COPY . .` only copies `app/`, no secrets path). `.gitignore` covers `.env.*`, `secrets/`, `mosquitto/passwords`. Good.

## MQTT internal reach (answer to focus Q)

Yes — prod FastAPI reaches Mosquitto on internal docker network `mosquitto:1883` because `mosquitto-prod.conf` keeps listener 1883 active (auth-required). External exposure is zero (no `ports:` in prod override). Correct.

## Unresolved Questions

1. Who generates `mosquitto/passwords` and when — bootstrap script needed?
2. Migration strategy post-Phase-01 (alembic? raw SQL runner?) — not in scope but blocks Phase 02.
3. Should `alerts.device_id` have FK? Plan omits; recommend adding.
4. `chunk_time_interval` default 7d OK given write volume of 1Hz×N_devices?

**Status:** DONE_WITH_CONCERNS
