"""Firebase Cloud Messaging wrapper.

In dev, the FCM credentials file is typically absent or a stub. `init_fcm`
detects that and leaves the module in a no-op state — `send_push` then
returns False without raising. Alerts still get logged to the `alerts`
table; only the push delivery is skipped.

The firebase-admin SDK uses synchronous HTTPS internally. `send_push` is
an async wrapper that offloads the blocking call via `asyncio.to_thread`
so the event loop (alert engine tick, MQTT ingest) never stalls on FCM.
"""

import asyncio
import logging
import os

import firebase_admin
from firebase_admin import credentials, messaging

logger = logging.getLogger(__name__)
_initialized = False


def init_fcm() -> bool:
    """Initialize Firebase Admin once. Returns True on success, False in dev/no-creds."""
    global _initialized
    if _initialized:
        return True
    path = os.getenv("FCM_CREDENTIALS_PATH", "").strip()
    if not path or not os.path.isfile(path):
        logger.warning("FCM not configured (no credentials at %s) — push disabled", path or "(unset)")
        return False
    # A valid service-account JSON is ~2KB. A stub `{}` file is smaller.
    if os.path.getsize(path) < 100:
        logger.warning("FCM credentials file looks like a stub — push disabled")
        return False
    try:
        cred = credentials.Certificate(path)
        firebase_admin.initialize_app(cred)
        _initialized = True
        logger.info("FCM initialized")
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("FCM init failed: %s — push disabled", exc)
        return False


async def send_push(
    fcm_token: str, title: str, body: str, data: dict | None = None
) -> bool:
    """Fire-and-forget push. Swallow errors (stale tokens, network) — alerts still DB-logged."""
    if not _initialized or not fcm_token:
        return False
    try:
        msg = messaging.Message(
            token=fcm_token,
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
        )
        # firebase-admin is sync — don't stall the event loop.
        await asyncio.to_thread(messaging.send, msg)
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("FCM send failed (token=%s...): %s", fcm_token[:12], exc)
        return False
