"""Auth endpoints — register, login, verify-email, resend-otp, forgot-password, reset-password, me, fcm-token."""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status

from auth.email_service import send_otp_email
from auth.models import (
    ChangePasswordRequest,
    FcmTokenUpdate,
    ForgotPasswordRequest,
    OtpVerifyRequest,
    ResendOtpRequest,
    ResetPasswordRequest,
    Token,
    UserCreate,
    UserLogin,
    UserOut,
)
from auth.otp_service import OtpRateLimitError, generate_and_store, verify
from auth.service import create_access_token, dummy_verify, hash_password, verify_password
from database import get_db_pool_from_request
from dependencies import get_current_user_id
from redis_client import get_redis_from_request
from sharing.service import resolve_pending_invites_for_email

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
async def register(
    payload: UserCreate,
    request: Request,
    background_tasks: BackgroundTasks,
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

    # Attach this new user to any cold invites addressed to their email before registration
    await resolve_pending_invites_for_email(pool, row["id"], payload.email)

    # Send email verification OTP — failure here must not break registration
    redis = get_redis_from_request(request)
    try:
        otp = await generate_and_store(redis, "verify", payload.email)
        background_tasks.add_task(send_otp_email, payload.email, otp, "verify")
    except OtpRateLimitError:
        pass  # Rate limited — registration succeeds, user must request resend manually

    # Return user info only; no token until email is verified
    return UserOut(id=row["id"], email=row["email"])


@router.post("/login", response_model=Token)
async def login(
    payload: UserLogin,
    request: Request,
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> Token:
    row = await pool.fetchrow(
        "SELECT id, password_hash, email_verified FROM users WHERE email = $1",
        payload.email,
    )
    if row is None:
        # Burn equivalent bcrypt time so attackers can't enumerate emails by timing
        dummy_verify()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid credentials")
    if not verify_password(payload.password, row["password_hash"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid credentials")
    if not row["email_verified"]:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "email not verified")
    return Token(access_token=create_access_token(row["id"]))


@router.post("/verify-email", response_model=Token)
async def verify_email(
    payload: OtpVerifyRequest,
    request: Request,
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> Token:
    redis = get_redis_from_request(request)
    ok = await verify(redis, "verify", payload.email, payload.otp)
    if not ok:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid or expired OTP")
    row = await pool.fetchrow(
        "UPDATE users SET email_verified=TRUE WHERE email=$1 RETURNING id",
        payload.email,
    )
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "user not found")
    return Token(access_token=create_access_token(row["id"]))


@router.post("/resend-otp", status_code=status.HTTP_204_NO_CONTENT)
async def resend_otp(
    payload: ResendOtpRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> None:
    redis = get_redis_from_request(request)
    row = await pool.fetchrow(
        "SELECT email_verified FROM users WHERE email=$1", payload.email
    )
    # Only send if user exists and is not yet verified
    if row and not row["email_verified"]:
        try:
            otp = await generate_and_store(redis, "verify", payload.email)
            background_tasks.add_task(send_otp_email, payload.email, otp, "verify")
        except OtpRateLimitError:
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "too many requests")


@router.post("/forgot-password", status_code=status.HTTP_204_NO_CONTENT)
async def forgot_password(
    payload: ForgotPasswordRequest,
    request: Request,
    background_tasks: BackgroundTasks,
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> None:
    redis = get_redis_from_request(request)
    row = await pool.fetchrow("SELECT id FROM users WHERE email=$1", payload.email)
    if row:
        try:
            otp = await generate_and_store(redis, "reset", payload.email)
            background_tasks.add_task(send_otp_email, payload.email, otp, "reset")
        except OtpRateLimitError:
            pass  # Always return 204 — never leak whether email exists


@router.post("/reset-password", status_code=status.HTTP_204_NO_CONTENT)
async def reset_password(
    payload: ResetPasswordRequest,
    request: Request,
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> None:
    redis = get_redis_from_request(request)
    ok = await verify(redis, "reset", payload.email, payload.otp)
    if not ok:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "invalid or expired OTP")
    pwd_hash = hash_password(payload.password)
    await pool.execute(
        "UPDATE users SET password_hash=$1 WHERE email=$2", pwd_hash, payload.email
    )


@router.get("/me", response_model=UserOut)
async def me(
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> UserOut:
    row = await pool.fetchrow("SELECT id, email FROM users WHERE id = $1", user_id)
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "user not found")
    return UserOut(id=row["id"], email=row["email"])


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    payload: ChangePasswordRequest,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> None:
    row = await pool.fetchrow("SELECT password_hash FROM users WHERE id=$1", user_id)
    if row is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "user not found")
    if not verify_password(payload.current_password, row["password_hash"]):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "incorrect current password")
    pwd_hash = hash_password(payload.new_password)
    await pool.execute("UPDATE users SET password_hash=$1 WHERE id=$2", pwd_hash, user_id)


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
