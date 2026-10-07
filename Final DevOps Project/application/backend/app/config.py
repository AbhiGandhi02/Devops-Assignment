"""Runtime settings. Everything comes from environment variables so the same
image runs in docker compose, in Kubernetes (ConfigMap + Secret) and in tests."""
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    database_url: str
    app_env: str
    app_version: str
    log_level: str
    welcome_message: str


def get_settings() -> Settings:
    return Settings(
        database_url=os.getenv("DATABASE_URL", "sqlite:///./readtrack.db"),
        app_env=os.getenv("APP_ENV", "local"),
        app_version=os.getenv("APP_VERSION", "dev"),
        log_level=os.getenv("LOG_LEVEL", "INFO"),
        welcome_message=os.getenv("WELCOME_MESSAGE", "Track what you read."),
    )
