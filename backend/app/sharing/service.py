"""Device-sharing DB operations."""

from uuid import UUID

import asyncpg


async def create_invite(
    pool: asyncpg.Pool, owner_id: UUID, device_id: str, email: str
) -> dict | None:
    """Insert an invite row. Returns None if the caller doesn't own the device."""
    # Caller must own the device
    owner_ok = await pool.fetchrow(
        "SELECT 1 FROM devices WHERE id = $1 AND owner_id = $2",
        device_id, owner_id,
    )
    if owner_ok is None:
        return None

    # If invited email belongs to an existing user, resolve it now so accept is trivial
    invited_user = await pool.fetchrow(
        "SELECT id FROM users WHERE email = $1",
        email,
    )

    row = await pool.fetchrow(
        """
        INSERT INTO device_shares (device_id, owner_id, invited_email, shared_with_id)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (device_id, invited_email) DO UPDATE
          SET shared_with_id = EXCLUDED.shared_with_id
        WHERE device_shares.accepted = FALSE
        RETURNING id, device_id, invited_email, accepted, created_at, accepted_at
        """,
        device_id, owner_id, email,
        invited_user["id"] if invited_user else None,
    )
    if row is None:
        # Already accepted — don't silently clobber. Re-return existing row.
        row = await pool.fetchrow(
            """
            SELECT id, device_id, invited_email, accepted, created_at, accepted_at
            FROM device_shares
            WHERE device_id = $1 AND invited_email = $2
            """,
            device_id, email,
        )
    return dict(row)


async def accept_invite(
    pool: asyncpg.Pool, user_id: UUID, share_id: UUID
) -> bool:
    """Accept an invite if its email matches the caller's email. Returns True on success."""
    # Get caller email
    me = await pool.fetchrow("SELECT email FROM users WHERE id = $1", user_id)
    if me is None:
        return False
    row = await pool.fetchrow(
        """
        UPDATE device_shares
        SET accepted = TRUE,
            accepted_at = now(),
            shared_with_id = $1
        WHERE id = $2
          AND invited_email = $3
          AND accepted = FALSE
        RETURNING device_id
        """,
        user_id, share_id, me["email"],
    )
    return row is not None


async def list_shared_with_me(pool: asyncpg.Pool, user_id: UUID) -> list[dict]:
    rows = await pool.fetch(
        """
        SELECT s.id AS share_id, s.device_id, d.name,
               ou.email AS owner_email, s.accepted_at
        FROM device_shares s
        JOIN devices d  ON d.id = s.device_id
        JOIN users   ou ON ou.id = s.owner_id
        WHERE s.shared_with_id = $1
          AND s.accepted = TRUE
        ORDER BY s.accepted_at DESC
        """,
        user_id,
    )
    return [dict(r) for r in rows]


async def list_shares_for_device(
    pool: asyncpg.Pool, owner_id: UUID, device_id: str
) -> list[dict]:
    """Owner-only: list everyone this device has been invited to / shared with."""
    rows = await pool.fetch(
        """
        SELECT s.id, s.device_id, s.invited_email, s.accepted, s.created_at, s.accepted_at
        FROM device_shares s
        JOIN devices d ON d.id = s.device_id
        WHERE d.owner_id = $1 AND s.device_id = $2
        ORDER BY s.created_at DESC
        """,
        owner_id, device_id,
    )
    return [dict(r) for r in rows]


async def delete_share(
    pool: asyncpg.Pool, user_id: UUID, share_id: UUID
) -> bool:
    """Delete if caller is owner or shared-with. Also cleans up the formerly-shared
    user's alert_thresholds row so the alert engine stops firing for a revoked viewer.
    Returns True on delete."""
    async with pool.acquire() as conn:
        async with conn.transaction():
            share = await conn.fetchrow(
                "SELECT device_id, shared_with_id FROM device_shares WHERE id = $1",
                share_id,
            )
            if share is None:
                return False
            result = await conn.execute(
                """
                DELETE FROM device_shares
                WHERE id = $1 AND (owner_id = $2 OR shared_with_id = $2)
                """,
                share_id, user_id,
            )
            if not result.endswith(" 1"):
                return False
            # Clean up the formerly-shared user's thresholds, unless they also
            # happen to own the device (in which case keep their thresholds).
            if share["shared_with_id"]:
                await conn.execute(
                    """
                    DELETE FROM alert_thresholds
                    WHERE device_id = $1 AND user_id = $2
                      AND NOT EXISTS (
                        SELECT 1 FROM devices WHERE id = $1 AND owner_id = $2
                      )
                    """,
                    share["device_id"],
                    share["shared_with_id"],
                )
            return True
