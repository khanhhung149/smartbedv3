"""Database access for sleep sessions.

Time axis is the `time` column throughout. `time` is stamped by the backend on
ingest (mqtt/subscriber.py) — the pad's own clock never reaches the database.
Do not wrap it in COALESCE(received_at, time): measured on the dev database,
that expression loses the index range scan and defeats TimescaleDB chunk
exclusion, turning a one-night query into a scan of every chunk.
"""

import logging
from datetime import datetime, timedelta, timezone
from uuid import UUID

import asyncpg

from config import get_settings
from sessions.rules import Sample, build_sessions, is_on_bed

logger = logging.getLogger(__name__)

# How far back a tick re-examines. Wide enough to re-close a session whose
# 30-minute absence straddles the window edge, cheap enough to run every minute.
LOOKBACK = timedelta(minutes=1440 + 60)


async def _active_device_ids(pool: asyncpg.Pool, since: datetime) -> list[str]:
    rows = await pool.fetch(
        """
        SELECT DISTINCT device_id
        FROM sec_data
        WHERE time >= $1
        """,
        since,
    )
    return [r["device_id"] for r in rows]


async def _load_samples(
    pool: asyncpg.Pool, device_id: str, start: datetime, end: datetime
) -> list[Sample]:
    rows = await pool.fetch(
        """
        SELECT time, heart_rate, resp_rate, status
        FROM sec_data
        WHERE device_id = $1 AND time >= $2 AND time < $3
        ORDER BY time
        """,
        device_id, start, end,
    )
    return [
        Sample(t=r["time"], hr=r["heart_rate"], rr=r["resp_rate"], status=r["status"])
        for r in rows
    ]


async def _summarize(
    pool: asyncpg.Pool, device_id: str, start: datetime, end: datetime
) -> asyncpg.Record | None:
    """Aggregate min_data over one session window.

    FILTER (WHERE ... > 0) is mandatory, not cosmetic: p.4 2.4.1 says the pad
    reports 0 when it cannot measure, so averaging those in would drag every
    night's heart rate toward zero in proportion to time spent out of bed.
    """
    return await pool.fetchrow(
        """
        SELECT (AVG(heart_rate) FILTER (WHERE heart_rate > 0))::real AS hr_avg,
                MIN(heart_rate) FILTER (WHERE heart_rate > 0)         AS hr_min,
                MAX(heart_rate) FILTER (WHERE heart_rate > 0)         AS hr_max,
               (AVG(resp_rate)  FILTER (WHERE resp_rate  > 0))::real  AS rr_avg,
               SUM(movement)::int                                        AS movement_total,
               SUM(snore_count)::int                                     AS snore_total,
               SUM(resp_disorder)::int                                   AS resp_disorder_total
        FROM min_data
        WHERE device_id = $1 AND time >= $2 AND time < $3
        """,
        device_id, start, end,
    )


async def rebuild_device(pool: asyncpg.Pool, device_id: str, since: datetime) -> int:
    """Recompute this device's sessions over [since, now) and upsert them.

    Upserting on (device_id, started_at) is what makes a re-run idempotent: a
    session that gains an end time between ticks updates in place instead of
    appearing twice.
    """
    settings = get_settings()
    now = datetime.now(timezone.utc)
    samples = await _load_samples(pool, device_id, since, now)
    if not samples:
        return 0

    windows = build_sessions(
        samples,
        now=now,
        open_seconds=settings.session_open_seconds,
        close_seconds=settings.session_close_seconds,
        max_minutes=settings.session_max_minutes,
    )

    for w in windows:
        end = w.ended_at or now
        row = await _summarize(pool, device_id, w.started_at, end)
        duration = int((w.ended_at - w.started_at).total_seconds()) if w.ended_at else None
        await pool.execute(
            """
            INSERT INTO sleep_sessions
              (device_id, started_at, ended_at, duration_s,
               hr_avg, hr_min, hr_max, rr_avg,
               movement_total, snore_total, resp_disorder_total,
               sit_up_count, wake_count, computed_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, now())
            ON CONFLICT (device_id, started_at) DO UPDATE SET
              ended_at            = EXCLUDED.ended_at,
              duration_s          = EXCLUDED.duration_s,
              hr_avg              = EXCLUDED.hr_avg,
              hr_min              = EXCLUDED.hr_min,
              hr_max              = EXCLUDED.hr_max,
              rr_avg              = EXCLUDED.rr_avg,
              movement_total      = EXCLUDED.movement_total,
              snore_total         = EXCLUDED.snore_total,
              resp_disorder_total = EXCLUDED.resp_disorder_total,
              sit_up_count        = EXCLUDED.sit_up_count,
              wake_count          = EXCLUDED.wake_count,
              computed_at         = now()
            """,
            device_id, w.started_at, w.ended_at, duration,
            row["hr_avg"] if row else None,
            row["hr_min"] if row else None,
            row["hr_max"] if row else None,
            row["rr_avg"] if row else None,
            row["movement_total"] if row else None,
            row["snore_total"] if row else None,
            row["resp_disorder_total"] if row else None,
            w.sit_up_count, w.wake_count,
        )
    return len(windows)


async def rebuild_all(pool: asyncpg.Pool) -> int:
    since = datetime.now(timezone.utc) - LOOKBACK
    total = 0
    for device_id in await _active_device_ids(pool, since):
        try:
            total += await rebuild_device(pool, device_id, since)
        except Exception:  # noqa: BLE001
            # One bad device must not stop the others, and must not kill the task.
            logger.exception("session rebuild failed device=%s", device_id)
    return total


# ── Read paths used by the router (Phase 03) ──────────────────────────────────

_SESSION_COLUMNS = """
    id, device_id, started_at, ended_at, duration_s,
    hr_avg, hr_min, hr_max, rr_avg,
    movement_total, snore_total, resp_disorder_total,
    sit_up_count, wake_count
"""


async def list_sessions(
    pool: asyncpg.Pool, device_id: str,
    start: datetime | None, end: datetime | None, limit: int,
) -> list[asyncpg.Record]:
    return await pool.fetch(
        f"""
        SELECT {_SESSION_COLUMNS}
        FROM sleep_sessions
        WHERE device_id = $1
          AND ($2::timestamptz IS NULL OR started_at >= $2)
          AND ($3::timestamptz IS NULL OR started_at <  $3)
        ORDER BY started_at DESC
        LIMIT $4
        """,
        device_id, start, end, limit,
    )


async def get_session(pool: asyncpg.Pool, session_id: UUID) -> asyncpg.Record | None:
    return await pool.fetchrow(
        f"SELECT {_SESSION_COLUMNS} FROM sleep_sessions WHERE id = $1", session_id
    )


async def get_timeline(
    pool: asyncpg.Pool, *, device_id: str,
    start: datetime, end: datetime | None, interval: str,
) -> list[dict]:
    """Bucketed series for one night — the only call the detail screen makes.

    `interval` is a server-owned constant looked up from the router's whitelist,
    never a value from the query string; it is interpolated because time_bucket()
    takes an interval literal, not a bind parameter.

    Buckets with no rows are simply absent from the result. That is deliberate:
    the app draws a hole where data is missing rather than joining across it,
    because a line spanning a 40-minute dropout is a reading nobody took.
    """
    stop = end or datetime.now(timezone.utc)

    minute_rows = await pool.fetch(
        f"""
        SELECT time_bucket('{interval}', time) AS t,
               (AVG(heart_rate) FILTER (WHERE heart_rate > 0))::real AS hr,
               (AVG(resp_rate)  FILTER (WHERE resp_rate  > 0))::real AS rr,
               SUM(movement)::int      AS movement,
               SUM(snore_count)::int   AS snore,
               SUM(resp_disorder)::int AS resp_disorder
        FROM min_data
        WHERE device_id = $1 AND time >= $2 AND time < $3
        GROUP BY t ORDER BY t
        """,
        device_id, start, stop,
    )

    # Occupancy and event codes live in sec_data, so they come from a second
    # query bucketed the same way and are joined in Python — cheaper to read
    # than a nested aggregate, and it keeps each query on its own index.
    sec_rows = await pool.fetch(
        f"""
        SELECT time_bucket('{interval}', time) AS t,
               MAX(heart_rate)                    AS hr_max,
               MAX(resp_rate)                     AS rr_max,
               array_agg(DISTINCT status) FILTER (WHERE status IS NOT NULL) AS events
        FROM sec_data
        WHERE device_id = $1 AND time >= $2 AND time < $3
        GROUP BY t ORDER BY t
        """,
        device_id, start, stop,
    )
    sec_by_t = {r["t"]: r for r in sec_rows}

    points: list[dict] = []
    for t in sorted({*(r["t"] for r in minute_rows), *sec_by_t}):
        m = next((r for r in minute_rows if r["t"] == t), None)
        s = sec_by_t.get(t)
        # bed_state comes from the same hr/rr rule the session builder uses, not
        # from `status` — no status code means "currently in bed" (p.4 2.4.1).
        on_bed = bool(s) and is_on_bed(s["hr_max"], s["rr_max"])
        points.append(
            {
                "t": t,
                "hr": m["hr"] if m else None,
                "rr": m["rr"] if m else None,
                "movement": m["movement"] if m else None,
                "snore": m["snore"] if m else None,
                "resp_disorder": m["resp_disorder"] if m else None,
                "bed_state": "on_bed" if on_bed else "off_bed",
                "events": sorted(s["events"]) if s and s["events"] else [],
            }
        )
    return points
