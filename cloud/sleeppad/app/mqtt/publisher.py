"""One-shot MQTT publishes (e.g. remote factory_reset).

The subscriber in `subscriber.py` owns the persistent connection.  Commands
are rare (only on device removal), so opening a short-lived client per
publish is simpler than threading a shared handle through the request path.
Retained flag is used so offline devices receive the message when they next
connect.
"""

import logging

import aiomqtt

from config import get_settings

logger = logging.getLogger(__name__)


async def publish_device_cmd(device_id: str, payload: str, *, retain: bool = True) -> None:
    settings = get_settings()
    topic = f"sleeppad/{device_id}/cmd"
    try:
        async with aiomqtt.Client(
            hostname=settings.mqtt_host,
            port=settings.mqtt_port,
            username=settings.mqtt_username or None,
            password=settings.mqtt_password or None,
            identifier="sleeppad-fastapi-publisher",
        ) as client:
            await client.publish(topic, payload=payload, qos=1, retain=retain)
            logger.info("published cmd topic=%s payload=%s retain=%s", topic, payload, retain)
    except aiomqtt.MqttError:
        # Best-effort — failure is non-fatal for the caller; next device reconnect
        # will read the retained message (if broker persisted it).
        logger.exception("failed to publish cmd topic=%s", topic)
