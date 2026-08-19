"""Application configuration — loaded from environment variables."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, case_sensitive=False, extra="ignore")

    env: str = "dev"
    api_domain: str = ""
    mqtt_domain: str = ""

    database_url: str
    redis_url: str

    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expire_days: int = 30

    mqtt_host: str = "mosquitto"
    mqtt_port: int = 1883
    mqtt_username: str = ""                # subscriber (backend) username
    mqtt_password: str = ""                # subscriber (backend) password
    mqtt_device_username: str = ""         # shared credentials handed to ESP32 via BLE
    mqtt_device_password: str = ""

    fcm_credentials_path: str = ""

    # SMTP email (FastAPI-Mail). Empty mail_server → dev mode (log OTP to stdout, no real send).
    mail_username: str = ""
    mail_password: str = ""
    mail_from: str = "hi@sleeptech.me"
    mail_from_name: str = "SleepTech"
    mail_server: str = ""
    mail_port: int = 465
    mail_ssl_tls: bool = True
    mail_starttls: bool = False
    use_credentials: bool = True
    validate_certs: bool = True

    # Cloudflare Turnstile — empty secret → skip verification in dev (logs warning)
    turnstile_secret_key: str = ""
    turnstile_verify_url: str = "https://challenges.cloudflare.com/turnstile/v0/siteverify"

    # Contact form destination
    contact_to_email: str = "hi@sleeptech.me"

    # Sleep-session boundaries, from the Legact Pro V2 protocol PDF p.2. Kept
    # configurable because the on-bed rule (hr>0 OR rr>0) is an inference: the
    # protocol says 0 also means "could not be computed", so a noisy sensor can
    # look like an empty bed. Expect to retune these against a real night.
    session_open_seconds: int = 30
    session_close_seconds: int = 1800
    session_max_minutes: int = 1440
    session_tick_seconds: int = 60


@lru_cache
def get_settings() -> Settings:
    return Settings()
