from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """Application configuration settings"""

    # Database
    database_url: str = "postgresql://postgres:postgres@localhost:5432/sonnenbankerl"

    # API
    api_port: int = 8000
    environment: str = "development"

    # CORS
    allowed_origins: str = "*"

    # GeoSphere Weather API
    geosphere_api_url: str = "https://dataset.api.hub.geosphere.at"
    geosphere_station_id: str = "11290"  # Graz Universitaet
    weather_cache_ttl: int = 600  # 10 minutes in seconds

    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()
