"""Mailgun email delivery for OTP codes (verification + password reset)."""

import logging

import httpx

from config import get_settings

logger = logging.getLogger(__name__)


async def send_otp_email(to_email: str, otp: str, purpose: str) -> None:
    """Send a 6-digit OTP to *to_email* via Mailgun REST API.

    If MAILGUN_API_KEY is not configured the call is skipped with a warning
    so that local development works without email credentials.
    """
    settings = get_settings()
    if not settings.mailgun_api_key:
        logger.warning("MAILGUN_API_KEY not set — skipping email send to %s", to_email)
        return

    subject = (
        "Verify your email – SleepPad"
        if purpose == "verify"
        else "Reset your password – SleepPad"
    )
    html = _build_html(otp, purpose)

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"https://api.mailgun.net/v3/{settings.mailgun_domain}/messages",
            auth=("api", settings.mailgun_api_key),
            data={
                "from": settings.email_from,
                "to": [to_email],
                "subject": subject,
                "html": html,
            },
            timeout=10.0,
        )
        resp.raise_for_status()


def _build_html(otp: str, purpose: str) -> str:
    action = "verify your email" if purpose == "verify" else "reset your password"
    return f"""
    <div style="font-family:Inter,sans-serif;max-width:480px;margin:auto;padding:32px">
      <h2 style="color:#6366f1">SleepPad</h2>
      <p>Your code to {action}:</p>
      <div style="font-size:36px;font-weight:700;letter-spacing:8px;color:#6366f1;margin:24px 0">{otp}</div>
      <p style="color:#888;font-size:13px">This code expires in 10 minutes. Do not share it with anyone.</p>
    </div>
    """
