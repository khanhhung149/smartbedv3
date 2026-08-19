"""Sleep Pad Platform — FastAPI entry point.

Phase 04: alert engine, FCM, and family-sharing routes wired in.
"""

import asyncio
import logging
import os
from collections.abc import AsyncIterator
from contextlib import AsyncExitStack, asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pathlib import Path

from alerts.engine import run_alert_engine
from alerts.router import router as alerts_router
from auth.router import router as auth_router
from contact.router import router as contact_router
from data.router import router as data_router
from database import init_pool
from devices.router import router as devices_router
from devices.service import warm_paired_cache
from fcm import init_fcm
from mqtt.subscriber import run_subscriber
from redis_client import redis_lifespan
from sessions.builder import run_session_builder
from sessions.router import router as sessions_router
from sharing.router import router as sharing_router
from watch.router import router as watch_router
from watch.worker import run_watch_data_worker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Initialize DB pool + Redis + MQTT subscriber + alert engine. AsyncExitStack guarantees cleanup."""
    async with AsyncExitStack() as stack:
        pool = await init_pool()
        app.state.db_pool = pool
        stack.push_async_callback(pool.close)

        await stack.enter_async_context(redis_lifespan(app))

        count = await warm_paired_cache(pool, app.state.redis)
        logging.getLogger(__name__).info("warmed paired_devices cache: %d entries", count)

        init_fcm()  # no-op if no credentials file

        stop_event = asyncio.Event()
        app.state.stop_event = stop_event

        mqtt_task = asyncio.create_task(
            run_subscriber(pool, app.state.redis, stop_event),
            name="mqtt-subscriber",
        )
        alerts_task = asyncio.create_task(
            run_alert_engine(pool, app.state.redis, stop_event),
            name="alert-engine",
        )
        watch_task = asyncio.create_task(
            run_watch_data_worker(pool, app.state.redis, stop_event),
            name="watch-data-worker",
        )
        sessions_task = asyncio.create_task(
            run_session_builder(pool, app.state.redis, stop_event),
            name="session-builder",
        )
        # Every task created above must appear here, or shutdown leaves it
        # running and asyncio reports it as never retrieved.
        stack.push_async_callback(
            _stop_tasks, stop_event,
            [mqtt_task, alerts_task, watch_task, sessions_task],
        )

        yield


async def _stop_tasks(stop_event: asyncio.Event, tasks: list[asyncio.Task]) -> None:
    stop_event.set()
    for t in tasks:
        t.cancel()
    for t in tasks:
        try:
            await t
        except (asyncio.CancelledError, Exception):  # noqa: BLE001
            pass


app = FastAPI(
    title="Sleep Pad Platform API",
    version="0.4.0",
    docs_url="/docs",
    lifespan=lifespan,
)

_PROD_ORIGINS = [
    "https://sleeptech.me",
    "https://www.sleeptech.me",
    "http://localhost:5173",
    "http://localhost:4173",
]

# The Flutter web client sends its JWT in an Authorization header and is served
# from whatever port the dev server picked that run, so neither the fixed origin
# list nor the header list can accommodate it. Both are widened for dev only —
# ENV is set per environment file, and prod keeps exactly the list above.
_is_dev = os.getenv("ENV", "").lower() == "dev"

app.add_middleware(
    CORSMiddleware,
    allow_origins=_PROD_ORIGINS,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?$" if _is_dev else None,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"] if _is_dev else ["Content-Type"],
    allow_credentials=False,
)

app.include_router(auth_router)
app.include_router(devices_router)
app.include_router(data_router)
app.include_router(alerts_router)
app.include_router(sharing_router)
app.include_router(contact_router)
app.include_router(watch_router)
app.include_router(sessions_router)

# Dashboard local web (Phase 01): /dashboard — xem realtime + xem lại một đêm.
# Serve tĩnh từ app/static/. Trang tự gọi /api/data/{id}/samples với JWT (token người dùng
# nhập trên trang, hoặc ?token=... trong URL) — đúng quyền của người dùng đó.
app.mount(
    "/dashboard",
    StaticFiles(directory=Path(__file__).resolve().parent / "static"),
    name="dashboard",
)


@app.get("/health")
async def health() -> dict:
    """Liveness probe — used by Docker healthcheck and load balancers."""
    return {
        "status": "ok",
        "env": os.getenv("ENV", "unknown"),
        "api_domain": os.getenv("API_DOMAIN", ""),
    }


@app.get("/")
async def root() -> dict:
    return {"service": "sleeppad-api", "version": app.version}
