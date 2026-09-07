import asyncio
import argparse
from uuid import UUID

import asyncpg

# Add app to path to import config and service
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from config import get_settings
from ai.service import features_for_session, score_for_session

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", type=str, help="UUID của session")
    parser.add_argument("--device", type=str, help="Thiết bị (nếu không có session, lấy session cuối của thiết bị)")
    args = parser.parse_args()
    
    settings = get_settings()
    pool = await asyncpg.create_pool(settings.database_url)
    
    session_id = None
    if args.session:
        session_id = UUID(args.session)
    elif args.device:
        row = await pool.fetchrow(
            "SELECT id FROM sleep_sessions WHERE device_id = $1 ORDER BY started_at DESC LIMIT 1",
            args.device
        )
        if row:
            session_id = row["id"]
            
    if not session_id:
        row = await pool.fetchrow("SELECT id FROM sleep_sessions ORDER BY started_at DESC LIMIT 1")
        if row:
            session_id = row["id"]
            
    if not session_id:
        print("Không tìm thấy session nào trong database.")
        await pool.close()
        return
        
    print(f"--- NGHIỆM THU SESSION {session_id} ---")
    f = await features_for_session(pool, session_id)
    if not f:
        print("extract() trả về None (session không đủ 10 phút dữ liệu occupied từ min_data).")
        await pool.close()
        return
        
    print("\n=== SleepFeatures ===")
    for k, v in f.as_prompt_facts().items():
        print(f"{k}: {v}")
        
    s = await score_for_session(pool, session_id)
    if s:
        print("\n=== SleepScore ===")
        print(f"Total: {s.total} (Band: {s.band})")
        for c in s.components:
            print(f" - {c.label}: {c.points}/{c.weight} ({c.value} {c.unit})")

    print("\n=== Đối chiếu chéo với sec_data & sleep_sessions ===")
    sess_row = await pool.fetchrow("SELECT * FROM sleep_sessions WHERE id = $1", session_id)
    start = sess_row["started_at"]
    end = sess_row["ended_at"] or f.session_end
    
    sec_stats = await pool.fetchrow(
        """
        SELECT 
            COUNT(*) FILTER (WHERE status = 2) as sec_mov_count,
            COUNT(*) FILTER (WHERE status = 7) as sec_snore_count
        FROM sec_data
        WHERE device_id = $1 AND time >= $2 AND time < $3
        """,
        f.device_id, start, end
    )
    
    print(f"1. Cử động (movement_total): SleepFeatures = {f.movement_total} | sec_data (mã 2) = {sec_stats['sec_mov_count']}")
    print(f"2. Nhịp tim trung bình: SleepFeatures.hr_mean = {f.hr_mean} | sleep_sessions.hr_avg = {sess_row['hr_avg']}")
    print(f"3. Nhịp tim đỉnh: SleepFeatures.hr_max = {f.hr_max} | sleep_sessions.hr_max = {sess_row['hr_max']}")
    print(f"4. Ngáy (snore_total): SleepFeatures = {f.snore_total} | sec_data (mã 7) = {sec_stats['sec_snore_count']} | sleep_sessions.snore_total = {sess_row['snore_total']}")
    
    print("\nLƯU Ý:")
    print("- Nhịp tim trung bình trong SleepFeatures (chỉ tính phút ngủ) sẽ thường thấp hơn sleep_sessions (tính cả phút thức/cử động trên giường).")
    print("- Nếu snore_total và resp_disorder_total bằng 0: chưa phân biệt được 'không có' với 'đệm không báo lỗi', cần thử nghiệm ngáy thực tế để xác minh.")

    await pool.close()

if __name__ == "__main__":
    asyncio.run(main())
