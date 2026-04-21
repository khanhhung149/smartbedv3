"""Postgres connection pool — shared via FastAPI lifespan."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import asyncpg
from fastapi import FastAPI, Request

from config import get_settings


async def init_pool() -> asyncpg.Pool:
    settings = get_settings()
    return await asyncpg.create_pool(
        dsn=settings.database_url,
        min_size=2,
        max_size=10,
        command_timeout=30,
    )


@asynccontextmanager
async def db_lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Attach the connection pool to app.state for the app's lifetime."""
    pool = await init_pool()
    app.state.db_pool = pool
    try:
        yield
    finally:
        await pool.close()


async def get_db_pool_from_request(request: Request) -> asyncpg.Pool:
    """FastAPI dependency — retrieve the app-wide pool from request state."""
    return request.app.state.db_pool
