"""Auth endpoints — /auth/register, /auth/login, /auth/me, /auth/fcm-token."""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from auth.models import FcmTokenUpdate, Token, UserCreate, UserLogin, UserOut
from auth.service import create_access_token, dummy_verify, hash_password, verify_password
from database import get_db_pool_from_request
from dependencies import get_current_user_id

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def register(
    payload: UserCreate,
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> UserOut:
    pwd_hash = hash_password(payload.password)
    try:
        row = await pool.fetchrow(
            "INSERT INTO users (email, password_hash) VALUES ($1, $2) "
            "RETURNING id, email",
            payload.email,
            pwd_hash,
        )
    except asyncpg.UniqueViolationError:
        raise HTTPException(status.HTTP_409_CONFLICT, "email already registered")
    return UserOut(id=row["id"], email=row["email"])


@router.post("/login", response_model=Token)
async def login(
    payload: UserLogin,
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> Token:
    row = await pool.fetchrow(
        "SELECT id, password_hash FROM users WHERE email = $1",
        payload.email,
    )
    if row is None:
        # burn equivalent bcrypt time so attackers can't enumerate emails by timing
        dummy_verify()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid credentials")
    if not verify_password(payload.password, row["password_hash"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid credentials")
    return Token(access_token=create_access_token(row["id"]))


@router.get("/me", response_model=UserOut)
async def me(
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> UserOut:
    row = await pool.fetchrow("SELECT id, email FROM users WHERE id = $1", user_id)
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "user not found")
    return UserOut(id=row["id"], email=row["email"])


@router.patch("/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
async def update_fcm_token(
    payload: FcmTokenUpdate,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> None:
    await pool.execute(
        "UPDATE users SET fcm_token = $1 WHERE id = $2",
        payload.fcm_token,
        user_id,
    )
