import asyncpg
from datetime import datetime, timezone
from uuid import UUID

from ai.sleep_features import extract, SleepFeatures
from ai.sleep_score import score, SleepScore

async def features_for_session(pool: asyncpg.Pool, session_id: UUID) -> SleepFeatures | None:
    """Đọc cửa sổ từ sleep_sessions, nạp min_data trong cửa sổ, rồi extract."""
    sess = await pool.fetchrow(
        "SELECT device_id, started_at, ended_at FROM sleep_sessions WHERE id = $1", 
        session_id
    )
    if not sess:
        return None
    
    device_id = sess["device_id"]
    start = sess["started_at"]
    end = sess["ended_at"] or datetime.now(timezone.utc)
    
    rows = await pool.fetch(
        """
        SELECT time, status, heart_rate, resp_rate, movement, snore_count, resp_disorder
        FROM min_data
        WHERE device_id = $1 AND time >= $2 AND time < $3
        ORDER BY time ASC
        """,
        device_id, start, end
    )
    
    minutes = [dict(r) for r in rows]
    return extract(device_id, minutes)

async def score_for_session(pool: asyncpg.Pool, session_id: UUID) -> SleepScore | None:
    """Gọi features_for_session và chấm điểm."""
    f = await features_for_session(pool, session_id)
    if not f:
        return None
    return score(f)
