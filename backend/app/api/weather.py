from fastapi import APIRouter, HTTPException, Query
from typing import Optional
from datetime import datetime, timezone
import logging

from app.models.weather import WeatherResponse
from app.services.weather import get_current_weather
from app.services.weather_openmeteo import (
    is_sunny_at_time,
    get_next_sunny_time,
    get_weather_summary,
    update_weather_for_region,
    run_weather_update_once,
)
from app.services.scheduler import scheduler

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


@router.get("/weather/forecast")
async def get_weather_forecast(
    lat: float = Query(..., description="Latitude"),
    lon: float = Query(..., description="Longitude"),
    hours: int = Query(24, description="Hours to forecast", le=168)
):
    """
    Get weather forecast for a location

    Returns cloud cover and sunshine predictions for the specified location.

    Args:
        lat: Latitude of the location
        lon: Longitude of the location
        hours: Number of hours to forecast (max 168 = 7 days)

    Returns:
        Weather summary with cloud cover predictions
    """
    logger.info(f"Forecast request: lat={lat}, lon={lon}, hours={hours}")

    try:
        summary = await get_weather_summary(lat, lon)
        return {
            "location": {"lat": lat, "lon": lon},
            "forecast_hours": hours,
            **summary
        }
    except Exception as e:
        logger.error(f"Error fetching weather forecast: {e}")
        raise HTTPException(
            status_code=503,
            detail="Weather forecast service temporarily unavailable.",
        )


@router.get("/weather/forecast/is-sunny")
async def check_forecast_sunny(
    lat: float = Query(..., description="Latitude"),
    lon: float = Query(..., description="Longitude"),
    at: Optional[datetime] = Query(None, description="Time to check (default: now)")
):
    """
    Check if it will be sunny at a specific time

    Returns whether the weather is expected to be sunny at the specified time.

    Args:
        lat: Latitude of the location
        lon: Longitude of the location
        at: Time to check (ISO format, default: now)

    Returns:
        Sunny status with cloud cover percentage
    """
    check_time = at or datetime.now(timezone.utc)

    try:
        cloud_cover = await is_sunny_at_time(lat, lon, check_time)

        if cloud_cover is None:
            return {
                "time": check_time.isoformat(),
                "is_sunny": None,
                "cloud_cover_percent": None,
                "status": "no_data"
            }

        return {
            "time": check_time.isoformat(),
            "is_sunny": cloud_cover,
            "cloud_cover_percent": None,
            "status": "cloudy" if not cloud_cover else "sunny"
        }
    except Exception as e:
        logger.error(f"Error checking sunny status: {e}")
        raise HTTPException(
            status_code=503,
            detail="Weather service temporarily unavailable.",
        )


@router.get("/weather/forecast/next-sunny")
async def get_next_sunny(
    lat: float = Query(..., description="Latitude"),
    lon: float = Query(..., description="Longitude"),
    hours: int = Query(48, description="Search horizon in hours", le=168)
):
    """
    Find next sunny period

    Returns the next time when weather is expected to be sunny.

    Args:
        lat: Latitude of the location
        lon: Longitude of the location
        hours: Search horizon in hours (max 168 = 7 days)

    Returns:
        Next sunny timestamp and time until then
    """
    from_time = datetime.now(timezone.utc)

    try:
        next_sunny = await get_next_sunny_time(lat, lon, from_time, hours)

        if next_sunny is None:
            return {
                "from_time": from_time.isoformat(),
                "search_hours": hours,
                "next_sunny": None,
                "status": "no_sunny_period"
            }

        time_diff = (next_sunny - from_time).total_seconds() / 60

        return {
            "from_time": from_time.isoformat(),
            "search_hours": hours,
            "next_sunny": next_sunny.isoformat() if hasattr(next_sunny, 'isoformat') else str(next_sunny),
            "minutes_until": int(time_diff),
            "status": "found"
        }
    except Exception as e:
        logger.error(f"Error finding next sunny: {e}")
        raise HTTPException(
            status_code=503,
            detail="Weather service temporarily unavailable.",
        )


@router.post("/weather/update")
async def trigger_weather_update():
    """
    Manually trigger weather forecast update

    This endpoint triggers an immediate update of all weather forecasts.
    Usually, updates happen automatically every 5 minutes.

    Returns:
        Update status and number of forecasts updated
    """
    logger.info("Manual weather update triggered via API")

    try:
        run_weather_update_once()
        return {
            "status": "success",
            "message": "Weather update completed"
        }
    except Exception as e:
        logger.error(f"Error triggering weather update: {e}")
        raise HTTPException(
            status_code=500,
            detail="Failed to update weather forecasts.",
        )


@router.get("/weather/scheduler/status")
async def get_scheduler_status():
    """
    Get weather scheduler status

    Returns whether the automatic weather update scheduler is running.

    Returns:
        Scheduler status and next scheduled update
    """
    job = scheduler.get_job("weather_update")

    if job is None:
        return {
            "running": False,
            "message": "Scheduler not configured"
        }

    return {
        "running": True,
        "next_run": job.next_run_time.isoformat() if job.next_run_time else None,
        "job_id": job.id,
        "job_name": job.name
    }
