"""Kiểm tiêu chí nghiệm thu còn thiếu của plan 260821-1541: "phòng có ngáy nhưng đệm không có
người nằm -> 0 phút ngáy". Gọi thẳng _summarize() thật trên Postgres đang chạy, không mock —
đúng cách đã dùng suốt phiên 24/08, vì hàm này phụ thuộc asyncpg.Pool nên không unit-test thuần
được như sleep_features/sleep_score.

Chạy:  python3 scripts/nghiem-thu-fusion-off-bed.py
"""

import asyncio
import sys
import os
from datetime import datetime, timedelta, timezone

import asyncpg

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from config import get_settings
from sessions.service import _summarize  # noqa: E402 — kiểm trực tiếp hàm private, cố ý


DEVICE_ID = "CNU10CDADC"


async def main() -> int:
    settings = get_settings()
    pool = await asyncpg.create_pool(settings.database_url)

    # Cửa sổ trống hoàn toàn: không có dòng sec_data nào ở đây cho DEVICE_ID, nên
    # occupied_minutes rỗng tự nhiên — không cần dựng "phòng trống" bằng cách khác.
    # Đặt xa trong tương lai để chắc chắn không đụng dữ liệu thật đang có.
    start = datetime(2030, 1, 1, tzinfo=timezone.utc)
    end = start + timedelta(minutes=10)
    snore_t = start + timedelta(minutes=5)

    await pool.execute(
        "INSERT INTO room_snore_events (t, device_ms, confidence, duration_ms, source) "
        "VALUES ($1, $2, $3, $4, $5)",
        snore_t, 999999, 0.9, 2000, "voice-node",
    )

    try:
        row = await _summarize(pool, DEVICE_ID, start, end)
        snore_total = row.get("snore_total")
        print(f"snore_total = {snore_total!r} (kỳ vọng 0 — phòng có ngáy nhưng đệm không có người)")
        ok = snore_total == 0
        print("PASS" if ok else "FAIL")
        return 0 if ok else 1
    finally:
        # Dọn ngay, không để dòng test lẫn vào bảng thật.
        await pool.execute(
            "DELETE FROM room_snore_events WHERE t = $1 AND device_ms = 999999", snore_t
        )
        await pool.close()


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
