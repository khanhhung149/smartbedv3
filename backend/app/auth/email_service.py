"""SMTP email delivery via FastAPI-Mail.

Dev mode: when MAIL_SERVER is empty, OTPs are logged to stdout instead of
being sent. Read them via `docker compose logs fastapi`.
Prod mode: real SMTP send (MXroute via env vars in .env.prod).
"""

import logging

from fastapi_mail import ConnectionConfig, FastMail, MessageSchema, MessageType

from config import Settings, get_settings

logger = logging.getLogger(__name__)


def _conn_config(s: Settings) -> ConnectionConfig:
    return ConnectionConfig(
        MAIL_USERNAME=s.mail_username,
        MAIL_PASSWORD=s.mail_password,
        MAIL_FROM=s.mail_from,
        MAIL_FROM_NAME=s.mail_from_name,
        MAIL_SERVER=s.mail_server,
        MAIL_PORT=s.mail_port,
        MAIL_SSL_TLS=s.mail_ssl_tls,
        MAIL_STARTTLS=s.mail_starttls,
        USE_CREDENTIALS=s.use_credentials,
        VALIDATE_CERTS=s.validate_certs,
    )


async def send_otp_email(to_email: str, otp: str, purpose: str) -> None:
    """Send a 6-digit OTP to *to_email* via SMTP, or log it in dev mode."""
    s = get_settings()
    if not s.mail_server:
        # Dev fallback — surface OTP in container logs so devs can complete the flow without SMTP creds.
        logger.info(
            "EMAIL[dev] to=%s purpose=%s otp=%s (MAIL_SERVER unset, skipping send)",
            to_email,
            purpose,
            otp,
        )
        return

    subject = (
        "Verify your email – SleepTech"
        if purpose == "verify"
        else "Reset your password – SleepTech"
    )
    msg = MessageSchema(
        subject=subject,
        recipients=[to_email],
        body=_build_html(otp, purpose),
        subtype=MessageType.html,
    )
    try:
        await FastMail(_conn_config(s)).send_message(msg)
    except Exception:
        # Background-task failure: log but don't break user-facing flow (register/forgot already returned 2xx).
        logger.exception("SMTP send failed for %s purpose=%s", to_email, purpose)


def _build_html(otp: str, purpose: str) -> str:
    action = "verify your email" if purpose == "verify" else "reset your password"
    return f"""
    <div style="font-family:Inter,sans-serif;max-width:480px;margin:auto;padding:32px">
      <h2 style="color:#6366f1">SleepTech</h2>
      <p>Your code to {action}:</p>
      <div style="font-size:36px;font-weight:700;letter-spacing:8px;color:#6366f1;margin:24px 0">{otp}</div>
      <p style="color:#888;font-size:13px">This code expires in 10 minutes. Do not share it with anyone.</p>
    </div>
    """
