"""OTP generation, storage, and verification with Redis-backed rate limiting."""

import hmac
import secrets

from redis.asyncio import Redis

OTP_TTL = 600       # 10 min — OTP validity window
RL_TTL = 900        # 15 min — rate-limit window
MAX_ATTEMPTS = 5    # wrong guesses before OTP is invalidated
MAX_REQUESTS = 3    # OTP sends per email per RL_TTL window


class OtpRateLimitError(Exception):
    """Raised when the caller has exceeded the OTP send rate limit."""


async def generate_and_store(redis: Redis, purpose: str, email: str) -> str:
    """Generate a 6-digit OTP, enforce rate limit, store in Redis, return the code."""
    rl_key = f"otp_rl:{email}"
    count = int(await redis.incr(rl_key))
    if count == 1:
        # First increment — set the expiry for the rate-limit window
        await redis.expire(rl_key, RL_TTL)
    if count > MAX_REQUESTS:
        raise OtpRateLimitError()

    otp = str(secrets.randbelow(900000) + 100000)  # always 6 digits: 100000–999999

    # Atomically store OTP and reset any previous attempt counter
    pipe = redis.pipeline()
    pipe.set(f"otp:{purpose}:{email}", otp, ex=OTP_TTL)
    pipe.delete(f"otp_attempts:{purpose}:{email}")
    await pipe.execute()

    return otp


async def verify(redis: Redis, purpose: str, email: str, code: str) -> bool:
    """Return True if *code* matches the stored OTP and was not brute-forced.

    Side effects on success: deletes OTP + attempt counter.
    Side effects on brute-force: deletes OTP (invalidates it).
    """
    stored = await redis.get(f"otp:{purpose}:{email}")
    if not stored:
        return False

    attempts_key = f"otp_attempts:{purpose}:{email}"
    attempts = int(await redis.incr(attempts_key))
    if attempts == 1:
        # Tie attempts expiry to remaining OTP TTL
        await redis.expire(attempts_key, OTP_TTL)

    if attempts > MAX_ATTEMPTS:
        # Too many wrong guesses — invalidate OTP to prevent further brute-force
        await redis.delete(f"otp:{purpose}:{email}")
        return False

    if not hmac.compare_digest(stored, code):
        return False

    # Correct code — clean up
    pipe = redis.pipeline()
    pipe.delete(f"otp:{purpose}:{email}")
    pipe.delete(attempts_key)
    await pipe.execute()

    return True
