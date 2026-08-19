"""Password hashing + JWT signing/verification."""

from datetime import datetime, timedelta, timezone
from uuid import UUID

from jose import JWTError, jwt
from passlib.context import CryptContext

from config import get_settings

_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Pre-computed bcrypt hash used by `dummy_verify` to burn the same CPU time
# whether or not a user exists, mitigating email-enumeration via login timing.
_DUMMY_HASH = _pwd_context.hash("dummy-password-never-valid")


def hash_password(plain: str) -> str:
    return _pwd_context.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return _pwd_context.verify(plain, hashed)


def dummy_verify() -> None:
    """Run bcrypt against a dummy hash to equalize login response time."""
    _pwd_context.verify("dummy-password-never-valid", _DUMMY_HASH)


def create_access_token(user_id: UUID) -> str:
    settings = get_settings()
    expire = datetime.now(timezone.utc) + timedelta(days=settings.jwt_expire_days)
    payload = {"sub": str(user_id), "exp": expire}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> UUID:
    """Return user_id embedded in token. Raises ValueError on any failure."""
    settings = get_settings()
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        sub = payload.get("sub")
        if not sub:
            raise ValueError("token missing sub claim")
        return UUID(sub)
    except (JWTError, ValueError) as exc:
        raise ValueError(f"invalid token: {exc}") from exc
