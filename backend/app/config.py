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


@lru_cache
def get_settings() -> Settings:
    return Settings()
