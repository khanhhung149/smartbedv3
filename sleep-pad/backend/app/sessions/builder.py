"""Background sleep-session builder.

Every tick it re-derives sessions from the last day or so of sec_data and
upserts them. Re-deriving rather than appending is deliberate: a session that is
still open gains its end time on a later tick, and the upsert on
(device_id, started_at) makes repeated ticks converge instead of duplicating.

Shaped after alerts/engine.py, including the rule that every exception is caught
and logged — a crash in here must never take down the lifespan.
"""

import asyncio
import logging

import asyncpg
import redis.asyncio as redis

from config import get_settings
from sessions.service import rebuild_all

logger = logging.getLogger(__name__)


async def run_session_builder(
    pool: asyncpg.Pool, rds: redis.Redis, stop: asyncio.Event
) -> None:
    """Runs until `stop` is set. `rds` is unused today; kept for signature
    symmetry with the other lifespan tasks so wiring stays uniform."""
    tick = get_settings().session_tick_seconds
    logger.info("session builder started (tick=%ds)", tick)
    while not stop.is_set():
        try:
            await asyncio.wait_for(stop.wait(), timeout=tick)
            break  # stop was set
        except asyncio.TimeoutError:
            pass
        try:
            count = await rebuild_all(pool)
            if count:
                logger.debug("session builder upserted %d session(s)", count)
        except Exception:  # noqa: BLE001
            logger.exception("session builder tick failed")
    logger.info("session builder stopped")
