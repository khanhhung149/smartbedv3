"""Redis connection — shared singleton initialized in lifespan."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import redis.asyncio as redis
from fastapi import FastAPI, Request

from config import get_settings


@asynccontextmanager
async def redis_lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    client = redis.from_url(settings.redis_url, decode_responses=True)
    app.state.redis = client
    try:
        yield
    finally:
        await client.aclose()


def get_redis_from_request(request: Request) -> redis.Redis:
    return request.app.state.redis


def online_key(device_id: str) -> str:
    return f"device:{device_id}:online"


# Redis set containing all currently-paired device_ids.
# Populated on startup (warm_paired_cache), updated on pair/unpair,
# read on every MQTT publish via SISMEMBER to avoid hot-path SQL.
PAIRED_DEVICES_KEY = "paired_devices"
