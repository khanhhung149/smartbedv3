"""Background alert engine.

Every 60s:
1. Load every (device_id, user_id, threshold, fcm_token) row from alert_thresholds.
2. Skip devices that are not currently online (Redis `device:{id}:online`).
3. Aggregate the last 1 minute of min_data (avg HR, avg RR, sum resp_disorder).
4. Compare against that user's thresholds → list of violations.
5. For each violation, use a 5-minute Redis dedup window so re-alerting is rate-limited.
6. On first violation in window: INSERT into alerts + send FCM push.
"""

import asyncio
import logging
from statistics import fmean

import asyncpg
import redis.asyncio as redis

from fcm import send_push

logger = logging.getLogger(__name__)

ALERT_TICK_SECONDS = 60
DEDUP_TTL_SECONDS = 300        # 5 min — don't re-alert same (device, user, metric)
ONLINE_KEY_FMT = "device:{}:online"


async def run_alert_engine(
    pool: asyncpg.Pool, rds: redis.Redis, stop: asyncio.Event
) -> None:
    """Runs forever until `stop` is set. Ticks every ALERT_TICK_SECONDS."""
    logger.info("alert engine started (tick=%ds)", ALERT_TICK_SECONDS)
    while not stop.is_set():
        try:
            await asyncio.wait_for(stop.wait(), timeout=ALERT_TICK_SECONDS)
            break  # stop was set
        except asyncio.TimeoutError:
            pass
        try:
            await _tick(pool, rds)
        except Exception:  # noqa: BLE001
            logger.exception("alert engine tick failed")
    logger.info("alert engine stopped")


async def _tick(pool: asyncpg.Pool, rds: redis.Redis) -> None:
    thresholds = await pool.fetch(
        """
        SELECT at.device_id, at.user_id,
               at.hr_high, at.hr_low, at.rr_high, at.rr_low,
               at.resp_disorder_count,
               u.fcm_token
        FROM alert_thresholds at
        JOIN users u ON u.id = at.user_id
        """
    )
    for t in thresholds:
        await _check_device_user(pool, rds, t)


async def _check_device_user(pool: asyncpg.Pool, rds: redis.Redis, t) -> None:
    device_id = t["device_id"]
    try:
        if not await rds.exists(ONLINE_KEY_FMT.format(device_id)):
            return
    except Exception:  # noqa: BLE001
        pass  # if Redis is down, fall through and check anyway

    rows = await pool.fetch(
        """
        SELECT heart_rate, resp_rate, resp_disorder
        FROM min_data
        WHERE device_id = $1 AND time > now() - interval '1 minute'
        """,
        device_id,
    )
    if not rows:
        return

    hrs = [r["heart_rate"] for r in rows if r["heart_rate"] is not None]
    rrs = [r["resp_rate"] for r in rows if r["resp_rate"] is not None]
    total_rd = sum((r["resp_disorder"] or 0) for r in rows)

    violations: list[tuple[str, float, float]] = []
    if hrs:
        avg_hr = fmean(hrs)
        if avg_hr > t["hr_high"]:
            violations.append(("hr_high", avg_hr, t["hr_high"]))
        if avg_hr < t["hr_low"]:
            violations.append(("hr_low", avg_hr, t["hr_low"]))
    if rrs:
        avg_rr = fmean(rrs)
        if avg_rr > t["rr_high"]:
            violations.append(("rr_high", avg_rr, t["rr_high"]))
        if avg_rr < t["rr_low"]:
            violations.append(("rr_low", avg_rr, t["rr_low"]))
    if total_rd > t["resp_disorder_count"]:
        violations.append(("resp_disorder", float(total_rd), t["resp_disorder_count"]))

    for metric, value, thr in violations:
        await _fire_alert(pool, rds, device_id, t["user_id"], t["fcm_token"], metric, value, thr)


async def _fire_alert(
    pool: asyncpg.Pool, rds: redis.Redis,
    device_id: str, user_id, fcm_token: str | None,
    metric: str, value: float, threshold: float,
) -> None:
    dedup_key = f"alert-suppress:{device_id}:{user_id}:{metric}"
    # SET NX EX → True iff we just claimed the key (first fire in 5 min window)
    try:
        claimed = await rds.set(dedup_key, "1", ex=DEDUP_TTL_SECONDS, nx=True)
    except Exception:  # noqa: BLE001
        claimed = True  # fail-open: deliver alert if Redis is down
    if not claimed:
        return

    await pool.execute(
        """
        INSERT INTO alerts (device_id, user_id, metric, value, threshold)
        VALUES ($1, $2, $3, $4, $5)
        """,
        device_id, user_id, metric, value, threshold,
    )
    logger.info(
        "alert fired device=%s user=%s metric=%s value=%.2f threshold=%.2f",
        device_id, user_id, metric, value, threshold,
    )
    if fcm_token:
        await send_push(
            fcm_token,
            title=f"Sleep Pad alert: {metric}",
            body=f"{metric} = {value:.1f} (threshold {threshold:g})",
            data={"device_id": device_id, "metric": metric, "value": value},
        )
