import aiohttp
import logging
from datetime import datetime, timezone
from typing import Optional, Tuple

from app.config import settings
from app.models.weather import WeatherStatus

logger = logging.getLogger(__name__)

# Simple in-memory cache
_weather_cache: Optional[WeatherStatus] = None
_cache_time: Optional[datetime] = None

# Station name mapping
STATION_NAMES = {
    "11290": "Graz Universitaet",
    "11240": "Graz-Thalerhof-Flughafen",
    "11238": "Graz/Strassgang",
    "11291": "Graz Universitaet/Heinrichstrasse",
}


def _is_cache_valid() -> bool:
    """Check if cached weather data is still valid"""
    if _weather_cache is None or _cache_time is None:
        return False

    age = (datetime.now(timezone.utc) - _cache_time).total_seconds()
    return age < settings.weather_cache_ttl


def _create_status_message(is_sunny: bool, sunshine_seconds: int) -> str:
    """Create human-readable status message"""
    if is_sunny:
        minutes = sunshine_seconds // 60
        if minutes >= 10:
            return "Sunny conditions - benches may be in sunlight"
        else:
            return f"Partial sunshine ({minutes} min in last 10 min) - some benches may be sunny"
    else:
        return "Overcast/cloudy - no benches currently in direct sunlight"


async def fetch_weather_from_api() -> WeatherStatus:
    """
    Fetch current weather from GeoSphere TAWES API

    Returns:
        WeatherStatus with current sunshine data

    Raises:
        Exception if API call fails
    """
    url = f"{settings.geosphere_api_url}/v1/station/current/tawes-v1-10min"
    params = {"parameters": "SO", "station_ids": settings.geosphere_station_id}

    logger.info(f"Fetching weather from GeoSphere API: {url}")

    async with aiohttp.ClientSession() as session:
        async with session.get(url, params=params, timeout=10) as response:
            if response.status != 200:
                error_text = await response.text()
                logger.error(f"GeoSphere API error {response.status}: {error_text}")
                raise Exception(f"GeoSphere API returned status {response.status}")

            data = await response.json()

    # Parse GeoJSON response
    try:
        # Extract timestamp from response
        timestamps = data.get("timestamps", [])
        if timestamps:
            api_timestamp = datetime.fromisoformat(
                timestamps[0].replace("+00:00", "+00:00")
            )
        else:
            api_timestamp = datetime.now(timezone.utc)

        # Extract sunshine duration from features
        features = data.get("features", [])
        if not features:
            raise ValueError("No features in API response")

        feature = features[0]
        properties = feature.get("properties", {})
        parameters = properties.get("parameters", {})
        so_data = parameters.get("SO", {})
        sunshine_data = so_data.get("data", [])

        if not sunshine_data:
            raise ValueError("No sunshine data in API response")

        sunshine_seconds = int(sunshine_data[0]) if sunshine_data[0] is not None else 0
        is_sunny = sunshine_seconds > 0

        station_id = settings.geosphere_station_id
        station_name = STATION_NAMES.get(station_id, f"Station {station_id}")

        status = WeatherStatus(
            is_sunny=is_sunny,
            sunshine_seconds=sunshine_seconds,
            station_id=station_id,
            station_name=station_name,
            timestamp=api_timestamp,
            cached_at=datetime.now(timezone.utc),
            message=_create_status_message(is_sunny, sunshine_seconds),
        )

        logger.info(
            f"Weather fetched: is_sunny={is_sunny}, sunshine_seconds={sunshine_seconds}"
        )
        return status

    except (KeyError, IndexError, ValueError) as e:
        logger.error(f"Error parsing GeoSphere API response: {e}")
        raise Exception(f"Failed to parse GeoSphere API response: {e}")


async def get_current_weather(force_refresh: bool = False) -> Tuple[WeatherStatus, bool]:
    """
    Get current weather status, using cache if valid

    Args:
        force_refresh: If True, bypass cache and fetch fresh data

    Returns:
        Tuple of (WeatherStatus, cache_hit)
    """
    global _weather_cache, _cache_time

    # Check cache first (unless force refresh)
    if not force_refresh and _is_cache_valid():
        logger.debug("Returning cached weather data")
        return _weather_cache, True

    # Fetch fresh data
    try:
        status = await fetch_weather_from_api()
        _weather_cache = status
        _cache_time = datetime.now(timezone.utc)
        return status, False

    except Exception as e:
        logger.error(f"Failed to fetch weather: {e}")

        # Return stale cache if available
        if _weather_cache is not None:
            logger.warning("Returning stale cached weather data due to API error")
            return _weather_cache, True

        # No cache available, raise error
        raise


async def is_sunny() -> bool:
    """
    Simple helper function to check if it's currently sunny

    Returns:
        True if there is sunshine, False otherwise
    """
    try:
        status, _ = await get_current_weather()
        return status.is_sunny
    except Exception as e:
        logger.error(f"Could not determine sunshine status: {e}")
        # Conservative default: assume not sunny if we can't determine
        return False


async def get_sunshine_seconds() -> int:
    """
    Get the number of sunshine seconds in the last 10 minutes

    Returns:
        Sunshine duration in seconds (0-600)
    """
    try:
        status, _ = await get_current_weather()
        return status.sunshine_seconds
    except Exception:
        return 0
