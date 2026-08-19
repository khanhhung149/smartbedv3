"""Pydantic models for the contact form endpoint."""

from pydantic import BaseModel, EmailStr, Field


class ContactRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    email: EmailStr
    subject: str = Field(..., min_length=5, max_length=200)
    message: str = Field(..., min_length=10, max_length=2000)
    turnstile_token: str = Field(..., alias="cf-turnstile-response")

    model_config = {"populate_by_name": True}
