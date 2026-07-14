"""
App configuration via Pydantic Settings.

All config is env-driven (12-factor app) so a typo or missing value fails fast
at startup instead of surfacing as a confusing runtime error later.
"""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    environment: str = "development"
    log_level: str = "INFO"

    cors_origins: str = "http://localhost:3000"

    gemini_api_key: str = ""
    gemini_model_id: str = "gemini-flash-latest"

    # "local" writes conversation JSON to memory_dir; "firestore" uses GCP Firestore.
    memory_backend: str = "local"
    memory_dir: str = "../memory"
    gcp_project: str = ""

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


settings = Settings()
