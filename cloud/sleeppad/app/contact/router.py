"""Contact form router: rate-limit → Turnstile → email forward."""

import logging

from fastapi import APIRouter, BackgroundTasks, HTTPException, Request, status
from redis.asyncio import Redis

from contact.models import ContactRequest
from contact.service import send_contact_email, verify_turnstile

logger = logging.getLogger(__name__)

router = APIRouter(tags=["contact"])

# Rate-limit: 3 submissions per IP per hour
_RL_MAX = 3
_RL_TTL = 3600  # 1 hour in seconds


def _get_client_ip(request: Request) -> str:
    """Extract real client IP — prefers CF-Connecting-IP (set by cloudflared tunnel)."""
    cf_ip = request.headers.get("cf-connecting-ip")
    if cf_ip:
        return cf_ip
    x_fwd = request.headers.get("x-forwarded-for")
    if x_fwd:
        return x_fwd.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


async def _check_rate_limit(redis: Redis, ip: str) -> None:
    """Raise HTTP 429 if the IP has exceeded the contact submission rate limit."""
    key = f"contact_rl:{ip}"
    count = int(await redis.incr(key))
    if count == 1:
        await redis.expire(key, _RL_TTL)
    if count > _RL_MAX:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many submissions. Try again in an hour.",
        )


@router.post("/contact", status_code=status.HTTP_204_NO_CONTENT)
async def submit_contact(
    payload: ContactRequest,
    background_tasks: BackgroundTasks,
    request: Request,
) -> None:
    """Receive contact form submission, verify Turnstile, then email asynchronously."""
    redis: Redis = request.app.state.redis
    ip = _get_client_ip(request)

    await _check_rate_limit(redis, ip)

    verified = await verify_turnstile(payload.turnstile_token, ip)
    if not verified:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="captcha failed",
        )

    background_tasks.add_task(send_contact_email, payload)
    logger.info("contact queued from ip=%s email=%s", ip, payload.email)
