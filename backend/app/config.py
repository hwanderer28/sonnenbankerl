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
    
    class Config:
        env_file = ".env"
        case_sensitive = False


settings = Settings()
