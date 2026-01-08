from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class WeatherStatus(BaseModel):
    """Current weather status for sunshine gate"""

    is_sunny: bool = Field(..., description="Whether there is currently sunshine")
    sunshine_seconds: int = Field(
        ..., description="Seconds of sunshine in last 10 minutes"
    )
    station_id: str = Field(..., description="Weather station ID")
    station_name: str = Field(..., description="Weather station name")
    timestamp: datetime = Field(..., description="Data timestamp from API")
    cached_at: Optional[datetime] = Field(None, description="When data was cached")
    message: str = Field(..., description="Human-readable status message")


class WeatherResponse(BaseModel):
    """API response for weather endpoint"""

    status: WeatherStatus
    cache_hit: bool = Field(..., description="Whether response came from cache")
