#!/usr/bin/env python3
"""Write one synthetic night straight into sec_data + min_data.

Runs inside the `fastapi` container, which already has asyncpg and DATABASE_URL:

  docker compose -f docker-compose.yml -f docker-compose.dev.yml \
      -f docker-compose.local.yml --env-file .env.dev \
      exec fastapi python /app/scripts/seed-night.py --device-id TEST000001 --hours 8

It bypasses MQTT on purpose. What needs proving here is the session rules, and
ingest already runs for real — pushing 28 800 messages through the broker would
test the part that is not in question and make the fixture slow and flaky.
"""

import argparse
import asyncio
import math
import os
import random
import sys
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

import asyncpg


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--device-id", required=True)
    ap.add_argument("--start", help="ISO start time, UTC. Default: `--hours` before now")
    ap.add_argument("--hours", type=float, default=8.0)
    ap.add_argument(
        "--gap-minutes", type=int, default=0,
        help="minutes out of bed, inserted mid-night. >30 splits the night in two",
    )
    ap.add_argument(
        "--zero-hr-half", action="store_true",
        help="report hr=0 for the second half — the fixture that proves "
             "AVG(...) FILTER (WHERE heart_rate > 0) is doing its job",
    )
    ap.add_argument(
        "--owner-email",
        help="user the seeded device belongs to. Defaults to the oldest account, "
             "which is fine on a fresh database and surprising on any other",
    )
    ap.add_argument("--seed", type=int, default=42, help="RNG seed, so runs are comparable")
    ap.add_argument("--yes", action="store_true", help="skip the non-local host prompt")
    return ap.parse_args()


def confirm_target(dsn: str, assume_yes: bool) -> None:
    host = urlparse(dsn).hostname or ""
    print(f"target database host: {host}")
    if host in {"localhost", "127.0.0.1", "postgres", "::1"} or assume_yes:
        return
    # This script writes fabricated readings. Doing that to a database holding
    # real people's nights would corrupt their reports irreversibly.
    reply = input(f"'{host}' is not a local database. Type the host again to continue: ")
    if reply.strip() != host:
        sys.exit("aborted")


async def main() -> None:
    args = parse_args()
    rng = random.Random(args.seed)

    dsn = os.environ["DATABASE_URL"]
    confirm_target(dsn, args.yes)

    start = (
        datetime.fromisoformat(args.start).replace(tzinfo=timezone.utc)
        if args.start
        else datetime.now(timezone.utc) - timedelta(hours=args.hours)
    )
    total_seconds = int(args.hours * 3600)
    half = total_seconds // 2

    # The gap sits in the middle of the night so both halves stay long enough to
    # qualify as sessions on their own.
    gap_seconds = args.gap_minutes * 60
    gap_start = half - gap_seconds // 2 if gap_seconds else -1
    gap_end = gap_start + gap_seconds

    conn = await asyncpg.connect(dsn)
    try:
        if args.owner_email:
            owner = await conn.fetchval(
                "SELECT id FROM users WHERE email = $1", args.owner_email
            )
            if owner is None:
                sys.exit(f"no user with email {args.owner_email}")
        else:
            owner = await conn.fetchval("SELECT id FROM users ORDER BY created_at LIMIT 1")
            if owner is None:
                sys.exit("no users in the database — register one first")
        print(f"device owner: {owner}")
        await conn.execute(
            """
            INSERT INTO devices (id, owner_id, name)
            VALUES ($1, $2, $3)
            ON CONFLICT (id) DO NOTHING
            """,
            args.device_id, owner, f"seed {args.device_id}",
        )

        sec_rows, min_rows, snore_voice_rows = [], [], []
        snore_from, snore_to = int(total_seconds * 0.35), int(total_seconds * 0.45)

        for i in range(total_seconds):
            t = start + timedelta(seconds=i)
            out_of_bed = gap_start <= i < gap_end

            if out_of_bed:
                hr, rr, status = 0, 0.0, 0x01           # 01 = off bed
            else:
                # Slow circadian drift plus second-to-second jitter, so the chart
                # has shape without pretending to be a real physiological model.
                hr = int(62 + 5 * math.sin(i / 3600) + rng.gauss(0, 1.5))
                rr = round(15 + 2 * math.sin(i / 2400) + rng.gauss(0, 0.6), 1)
                # Rarest codes are tested first. Ordered the other way the
                # 15-minute movement branch swallows them, because both 7200 and
                # 5400 divide by 900 — which is how the first run produced
                # sit_up_count = wake_count = 0.
                status = 0x04                            # 04 = asleep
                if i and i % 7200 == 0:
                    status = 0x03                        # 03 = sitting up
                elif i and i % 5400 == 0:
                    status = 0x05                        # 05 = awake
                elif snore_from <= i < snore_to and i % 37 == 0:
                    status = 0x07                        # 07 = snoring
                    # Also insert voice node snore event
                    snore_voice_rows.append((t, i * 1000, 0.85, 1200))
                elif i % 900 == 0:
                    status = 0x02                        # 02 = movement
                if args.zero_hr_half and i >= half:
                    hr = 0                               # sensor could not compute

            sec_rows.append((t, args.device_id, status, hr, rr, 0, 0, t))

            if i % 60 == 0:
                min_rows.append((
                    t, args.device_id, status, hr, rr,
                    0 if out_of_bed else rng.randint(0, 3),
                    2 if (not out_of_bed and snore_from <= i < snore_to) else 0,
                    1 if (not out_of_bed and i % 3600 == 0 and i) else 0,
                    0, 0.0, t,
                ))

        # Re-seeding the same window must not stack duplicate rows on top of the
        # previous run; sec_data/min_data have no unique key to conflict on.
        stop = start + timedelta(seconds=total_seconds)
        for table in ("sec_data", "min_data"):
            await conn.execute(
                f"DELETE FROM {table} WHERE device_id = $1 AND time >= $2 AND time < $3",
                args.device_id, start, stop,
            )
        await conn.execute(
            "DELETE FROM room_snore_events WHERE t >= $1 AND t < $2",
            start, stop,
        )

        await conn.copy_records_to_table(
            "sec_data", records=sec_rows,
            columns=["time", "device_id", "status", "heart_rate", "resp_rate",
                     "sdata", "pdata", "received_at"],
        )
        await conn.copy_records_to_table(
            "min_data", records=min_rows,
            columns=["time", "device_id", "status", "heart_rate", "resp_rate",
                     "movement", "snore_count", "resp_disorder", "pthd", "temp",
                     "received_at"],
        )
        if snore_voice_rows:
            await conn.copy_records_to_table(
                "room_snore_events", records=snore_voice_rows,
                columns=["t", "device_ms", "confidence", "duration_ms"],
            )
        print(
            f"seeded {len(sec_rows)} sec + {len(min_rows)} min rows "
            f"for {args.device_id} from {start.isoformat()} to {stop.isoformat()}"
            + (f", gap {args.gap_minutes}m" if gap_seconds else "")
            + (", second half hr=0" if args.zero_hr_half else "")
        )
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main())
