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
) -> dict:
    """Aggregate one session window, taking each channel from where it exists.

    Vitals come from sec_data, not min_data. The LSM-800-T pad speaks the TAOSG
    protocol — a 66-byte block once a second — and emits no per-minute frame at
    all, so min_data stays empty forever for it and a summary built on min_data
    alone reports every vital as NULL. sec_data also carries heart rate and
    respiration at 1 Hz, which is a finer average over the same window than the
    per-minute frame ever was.

    Movement, snoring and respiratory-disorder counts come from the per-second
    event codes in sec_data.status (2 = movement, 7 = snoring, 8 = weak
    breathing), counted as episodes rather than seconds. min_data carried the
    same three channels as per-minute totals, but this pad never fills it.

    FILTER (WHERE ... > 0) is mandatory, not cosmetic: p.4 2.4.1 says the pad
    reports 0 when it cannot measure, so averaging those in would drag every
    night's heart rate toward zero in proportion to time spent out of bed.
    """
    vitals = await pool.fetchrow(
        """
        SELECT (AVG(heart_rate) FILTER (WHERE heart_rate > 0))::real AS hr_avg,
                MIN(heart_rate) FILTER (WHERE heart_rate > 0)        AS hr_min,
                MAX(heart_rate) FILTER (WHERE heart_rate > 0)        AS hr_max,
               (AVG(resp_rate)  FILTER (WHERE resp_rate  > 0))::real AS rr_avg
        FROM sec_data
        WHERE device_id = $1 AND time >= $2 AND time < $3
        """,
        device_id, start, end,
    )
    # Đếm ĐỢT, không đếm giây: một lần trở mình kéo dài vài giây vẫn là một lần.
    # Mỗi giây mang mã sự kiện của riêng nó (p.4 §2.4.1), nên một đợt = một giây
    # có mã X mà giây liền trước không có mã X.
    #
    # Nguồn là sec_data chứ không phải min_data, cùng lý do như phần sinh hiệu ở
    # trên: pad LSM-800-T không phát khung phút nên min_data rỗng vĩnh viễn, và
    # ô "Trở mình" trong app hiện dấu gạch dù đêm 21/08 có 570 giây mang mã 2.
    #
    # snore_total — Sensor Fusion (Voice Node + Pad):
    # Không còn dùng status=7 của đệm rung (kém nhạy). Thay vào đó:
    # 1. Lấy sự kiện ngáy từ room_snore_events (Voice Node, AI).
    # 2. Kẹp điều kiện: đệm phải đang báo heart_rate > 0 (có người nằm).
    #    → Loại bỏ tiếng ồn phòng trống, tiếng ngáy người khác ở phòng bên cạnh.
    # 3. Hệ số quy đổi: 1 event = 30s = 0.5 phút. CHƯA CALIBRATE bằng ngáy thật —
    #    con số 0,5 chỉ suy từ thiết kế firmware (3 cửa sổ 1s liên tiếp mới xác
    #    nhận một event). 80 sự kiện dùng để "kiểm" hôm 21/08 hoá ra là script
    #    mosquitto_pub lặp mỗi 37s (77/78 khoảng cách bằng đúng 37,0s — không
    #    cảm biến âm thanh thật nào đều vậy), nên KHÔNG phải bằng chứng calibration
    #    thật. Phải đo lại bằng tiếng ngáy thật trước khi tin số phút này.
    counters = await pool.fetchrow(
        """
        WITH s AS (
            SELECT status, LAG(status) OVER (ORDER BY time) AS truoc
            FROM sec_data
            WHERE device_id = $1 AND time >= $2 AND time < $3
        )
        SELECT COUNT(*) FILTER (WHERE status = 2 AND truoc IS DISTINCT FROM 2)::int
                   AS movement_total,
               COUNT(*) FILTER (WHERE status = 8 AND truoc IS DISTINCT FROM 8)::int
                   AS resp_disorder_total
        FROM s
        """,
        device_id, start, end,
    )

    # Đếm số phút có người nằm trên đệm (dùng làm tập hợp để giao với snore events).
    # Dùng date_trunc('minute') để gom theo phút — khớp với granularity của timeline.
    occupied_minutes_rows = await pool.fetch(
        """
        SELECT DISTINCT date_trunc('minute', time) AS minute
        FROM sec_data
        WHERE device_id = $1 AND time >= $2 AND time < $3 AND heart_rate > 0
        """,
        device_id, start, end,
    )
    occupied_minutes = {r["minute"] for r in occupied_minutes_rows}

    # Lấy tất cả sự kiện ngáy từ Voice Node trong khung giờ này.
    snore_rows = await pool.fetch(
        "SELECT t FROM room_snore_events WHERE t >= $1 AND t < $2",
        start, end,
    )
    # Logic AND (Sensor Fusion): chỉ tính tiếng ngáy khi đệm đang có người nằm.
    # 1 event = 0.5 phút ngáy — xem cảnh báo "CHƯA CALIBRATE" phía trên _summarize.
    snore_events_on_bed = sum(
        1 for r in snore_rows
        if r["t"].replace(second=0, microsecond=0) in occupied_minutes
    )
    snore_total_minutes = round(snore_events_on_bed * 0.5)

    return {
        **dict(vitals or {}),
        **dict(counters or {}),
        "snore_total": snore_total_minutes,
    }


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
            row.get("hr_avg"),
            row.get("hr_min"),
            row.get("hr_max"),
            row.get("rr_avg"),
            row.get("movement_total"),
            row.get("snore_total"),
            row.get("resp_disorder_total"),
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
               SUM(movement)::int      AS movement,
               SUM(resp_disorder)::int AS resp_disorder
        FROM min_data
        WHERE device_id = $1 AND time >= $2 AND time < $3
        GROUP BY t ORDER BY t
        """,
        device_id, start, stop,
    )

    # Vitals, occupancy and event codes all come from sec_data, bucketed the
    # same way and joined in Python — cheaper to read than a nested aggregate,
    # and it keeps each query on its own index. min_data above contributes only
    # the channels sec_data has no equivalent for.
    sec_rows = await pool.fetch(
        f"""
        SELECT time_bucket('{interval}', time) AS t,
               MAX(heart_rate)                    AS hr_max,
               MAX(resp_rate)                     AS rr_max,
               (AVG(heart_rate) FILTER (WHERE heart_rate > 0))::real AS hr,
               (AVG(resp_rate)  FILTER (WHERE resp_rate  > 0))::real AS rr,
               array_agg(DISTINCT status) FILTER (WHERE status IS NOT NULL) AS events
        FROM sec_data
        WHERE device_id = $1 AND time >= $2 AND time < $3
        GROUP BY t ORDER BY t
        """,
        device_id, start, stop,
    )
    sec_by_t = {r["t"]: r for r in sec_rows}

    # Phase 02 — Sensor Fusion cho Timeline:
    # Lấy tất cả sự kiện ngáy từ Voice Node trong khung giờ.
    # Gom vào dict theo time_bucket (giống interval) trong Python — tránh JOIN chéo DB.
    # Chỉ gài mã sự kiện 7 ("Ngáy") vào bucket nếu đệm đang báo on_bed (hr_max > 0).
    snore_voice_rows = await pool.fetch(
        f"""
        SELECT time_bucket('{interval}', t) AS bucket,
               COUNT(*)::int AS cnt
        FROM room_snore_events
        WHERE t >= $1 AND t < $2
        GROUP BY bucket
        """,
        start, stop,
    )
    snore_by_bucket = {r["bucket"]: r["cnt"] for r in snore_voice_rows}

    points: list[dict] = []
    for t in sorted({*(r["t"] for r in minute_rows), *sec_by_t, *snore_by_bucket}):
        m = next((r for r in minute_rows if r["t"] == t), None)
        s = sec_by_t.get(t)
        # bed_state comes from the same hr/rr rule the session builder uses, not
        # from `status` — no status code means "currently in bed" (p.4 2.4.1).
        on_bed = bool(s) and is_on_bed(s["hr_max"], s["rr_max"])

        # Mã sự kiện 7 ("Ngáy") từ Voice Node: chỉ gài vào nếu đệm on_bed.
        # Không thêm 7 vào khi phòng trống để tránh nhiễu môi trường.
        base_events = sorted(s["events"]) if s and s["events"] else []
        voice_snore_count = snore_by_bucket.get(t, 0)
        if on_bed and voice_snore_count > 0 and 7 not in base_events:
            base_events = sorted(base_events + [7])

        points.append(
            {
                "t": t,
                # hr/rr từ sec_data (1 Hz) chứ không phải min_data: pad LSM-800-T
                # nói giao thức TAOSG, không phát khung phút, nên min_data rỗng
                # vĩnh viễn và biểu đồ nhịp tim của một đêm sẽ trống trơn.
                "hr": s["hr"] if s else None,
                "rr": s["rr"] if s else None,
                "movement": m["movement"] if m else None,
                # snore: số sự kiện Voice Node trong bucket (thay thế min_data.snore_count
                # vốn luôn rỗng với LSM-800-T). Chỉ tính khi on_bed.
                "snore": voice_snore_count if on_bed else 0,
                "resp_disorder": m["resp_disorder"] if m else None,
                "bed_state": "on_bed" if on_bed else "off_bed",
                "events": base_events,
            }
        )
    return points

