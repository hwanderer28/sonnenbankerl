from fastapi import APIRouter, HTTPException, Query
import logging

from app.models.weather import WeatherResponse
from app.services.weather import get_current_weather

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/weather/current", response_model=WeatherResponse)
async def get_weather(
    refresh: bool = Query(False, description="Force refresh from API, bypass cache")
):
    """
    Get current weather status for Graz

    Returns the current sunshine status based on GeoSphere Austria TAWES station data.
    This endpoint is used as a "sunshine gate" - if not sunny, no benches can be in sunlight.

    Args:
        refresh: If True, bypass cache and fetch fresh data from API

    Returns:
        Current weather status with sunshine information
    """
    logger.info(f"Weather request received (refresh={refresh})")

    try:
        status, cache_hit = await get_current_weather(force_refresh=refresh)

        return WeatherResponse(status=status, cache_hit=cache_hit)

    except Exception as e:
        logger.error(f"Error fetching weather: {e}")
        raise HTTPException(
            status_code=503,
            detail="Weather service temporarily unavailable. Please try again later.",
        )
