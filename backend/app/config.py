from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """Application configuration settings"""

    database_url: str = "postgresql://postgres:postgres@localhost:5432/sonnenbankerl"

    api_port: int = 8000
    environment: str = "development"

    allowed_origins: str = "*"

    geosphere_api_url: str = "https://dataset.api.hub.geosphere.at"
    geosphere_station_id: str = "11290"
    weather_cache_ttl: int = 600

    openmeteo_cache_ttl: int = 300
    openmeteo_forecast_hours: int = 168
    cloud_cover_threshold: int = 20
    weather_update_interval: int = 300

    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()
