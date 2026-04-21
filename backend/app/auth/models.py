"""Pydantic schemas for auth endpoints."""

from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    id: UUID
    email: EmailStr


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class FcmTokenUpdate(BaseModel):
    fcm_token: str = Field(min_length=1, max_length=4096)
