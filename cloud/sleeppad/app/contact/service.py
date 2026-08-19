"""Contact form service: Turnstile verification + email forwarding."""

import logging

import httpx
from fastapi_mail import FastMail, MessageSchema, MessageType

from auth.email_service import _conn_config
from config import get_settings
from contact.models import ContactRequest

logger = logging.getLogger(__name__)


async def verify_turnstile(token: str, remote_ip: str | None) -> bool:
    """Verify a Cloudflare Turnstile token.

    Dev fallback: if TURNSTILE_SECRET_KEY is empty, log a warning and return True
    so local dev works without Turnstile credentials.
    """
    s = get_settings()
    if not s.turnstile_secret_key:
        logger.warning(
            "TURNSTILE_SECRET_KEY not set — skipping Turnstile verification (dev mode)"
        )
        return True

    data: dict[str, str] = {
        "secret": s.turnstile_secret_key,
        "response": token,
    }
    if remote_ip:
        data["remoteip"] = remote_ip

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(s.turnstile_verify_url, data=data)
            resp.raise_for_status()
            result = resp.json()
            return bool(result.get("success", False))
    except Exception:
        logger.exception("Turnstile verification request failed")
        return False


async def send_contact_email(payload: ContactRequest) -> None:
    """Send the contact form message to the configured contact inbox.

    Uses FastAPI-Mail. Dev fallback: if MAIL_SERVER is empty, logs to stdout.
    Reply-to is set to the submitter's email so inbox replies go directly to them.
    """
    s = get_settings()
    if not s.mail_server:
        logger.info(
            "EMAIL[dev] contact from=%s subject=%s (MAIL_SERVER unset, skipping send)",
            payload.email,
            payload.subject,
        )
        return

    msg = MessageSchema(
        subject=f"[SleepTech Contact] {payload.subject}",
        recipients=[s.contact_to_email],
        reply_to=[payload.email],
        body=_build_contact_html(payload),
        subtype=MessageType.html,
    )
    try:
        await FastMail(_conn_config(s)).send_message(msg)
    except Exception:
        logger.exception(
            "SMTP send failed for contact from=%s subject=%s", payload.email, payload.subject
        )


def _build_contact_html(p: ContactRequest) -> str:
    return f"""
    <div style="font-family:Inter,sans-serif;max-width:600px;margin:auto;padding:32px">
      <h2 style="color:#6366f1">SleepTech — Contact Form</h2>
      <table style="width:100%;border-collapse:collapse;margin-bottom:24px">
        <tr>
          <td style="padding:8px 0;font-weight:600;width:100px;color:#555">From</td>
          <td style="padding:8px 0">{p.name} &lt;{p.email}&gt;</td>
        </tr>
        <tr>
          <td style="padding:8px 0;font-weight:600;color:#555">Subject</td>
          <td style="padding:8px 0">{p.subject}</td>
        </tr>
      </table>
      <div style="background:#f8f8ff;border-left:4px solid #6366f1;padding:16px 20px;border-radius:4px">
        <p style="margin:0;white-space:pre-wrap;line-height:1.6">{p.message}</p>
      </div>
      <p style="color:#888;font-size:12px;margin-top:24px">
        Reply to this email to respond directly to {p.name}.
      </p>
    </div>
    """
