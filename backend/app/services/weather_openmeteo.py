import asyncio
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Dict, Tuple
import json

import aiohttp
from app.config import settings
from app.db.connection import get_pool

logger = logging.getLogger(__name__)

OPENMETEO_BASE_URL = "https://api.open-meteo.com/v1/forecast"

CLOUD_COVER_THRESHOLD = 20

OPENMETEO_CACHE_TTL = 300

_region_cache: Dict[str, datetime] = {}
_forecast_cache: Dict[Tuple[str, datetime], dict] = {}


def _get_region_id(lat: float, lon: float) -> str:
    return f"graz_{int(lat * 10)}_{int(lon * 10)}"


def _is_cache_valid(cached_at: datetime) -> bool:
    age = (datetime.now(timezone.utc) - cached_at).total_seconds()
    return age < OPENMETEO_CACHE_TTL


async def _fetch_openmeteo_forecast(lat: float, lon: float) -> Optional[dict]:
    params = {
        "latitude": lat,
        "longitude": lon,
        "hourly": "cloudcover,sunshine_duration",
        "forecast_hours": 168,
        "timezone": "Europe/Vienna",
    }

    url = f"{OPENMETEO_BASE_URL}?{ '&'.join(f'{k}={v}' for k, v in params.items()) }"

    logger.info(f"Fetching weather forecast from Open-Meteo: lat={lat}, lon={lon}")

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=30)) as response:
                if response.status != 200:
                    error_text = await response.text()
                    logger.error(f"Open-Meteo API error {response.status}: {error_text}")
                    return None

                data = await response.json()
                return data

    except asyncio.TimeoutError:
        logger.error("Open-Meteo API request timed out")
        return None
    except Exception as e:
        logger.error(f"Error fetching Open-Meteo forecast: {e}")
        return None


async def _parse_forecast(data: dict) -> List[dict]:
    hourly = data.get("hourly", {})
    times = hourly.get("time", [])
    cloudcover = hourly.get("cloudcover", [])
    sunshine = hourly.get("sunshine_duration", [])

    forecasts = []
    for i, t in enumerate(times):
        forecast_time = datetime.fromisoformat(t.replace("+02:00", "+02:00").replace("+01:00", "+01:00"))
        cloudcover_val = cloudcover[i] if i < len(cloudcover) else None
        sunshine_val = sunshine[i] if i < len(sunshine) else None

        forecasts.append({
            "forecast_time": forecast_time,
            "cloud_cover_percent": cloudcover_val,
            "sunshine_duration_seconds": sunshine_val,
        })

    return forecasts


async def _store_forecast_in_db(
    region_id: str, lat: float, lon: float, forecasts: List[dict]
) -> int:
    pool = await get_pool()
    stored = 0

    query = """
        INSERT INTO weather_cache (region_id, latitude, longitude, forecast_time, cloud_cover_percent, sunshine_duration_seconds, fetched_at)
        VALUES ($1, $2, $3, $4, $5, $6, NOW())
        ON CONFLICT (region_id, forecast_time)
        DO UPDATE SET
            cloud_cover_percent = EXCLUDED.cloud_cover_percent,
            sunshine_duration_seconds = EXCLUDED.sunshine_duration_seconds,
            fetched_at = EXCLUDED.fetched_at
    """

    try:
        async with pool.acquire() as conn:
            for f in forecasts:
                if f["forecast_time"] is None:
                    continue
                await conn.execute(
                    query,
                    region_id,
                    lat,
                    lon,
                    f["forecast_time"],
                    f["cloud_cover_percent"],
                    f["sunshine_duration_seconds"],
                )
                stored += 1
    except Exception as e:
        logger.error(f"Error storing weather forecast in DB: {e}")

    return stored


async def update_weather_for_region(lat: float, lon: float) -> Tuple[int, bool]:
    region_id = _get_region_id(lat, lon)

    data = await _fetch_openmeteo_forecast(lat, lon)
    if data is None:
        return 0, False

    forecasts = await _parse_forecast(data)
    if not forecasts:
        return 0, False

    stored = await _store_forecast_in_db(region_id, lat, lon, forecasts)
    logger.info(f"Stored {stored} weather forecasts for region {region_id}")

    return stored, True


async def update_all_region_forecasts() -> Dict[str, int]:
    pool = await get_pool()

    query = """
        SELECT DISTINCT ON (region_id)
            'graz_' || floor(ST_Y(geom::geometry)::numeric * 10)::int || '_' || floor(ST_X(geom::geometry)::numeric * 10)::int as region_id,
            round(ST_Y(geom::geometry)::numeric, 1) as lat,
            round(ST_X(geom::geometry)::numeric, 1) as lon
        FROM benches
        WHERE geom IS NOT NULL
        ORDER BY region_id
    """

    results = {}
    try:
        async with pool.acquire() as conn:
            rows = await conn.fetch(query)
            regions = [dict(row) for row in rows]
    except Exception as e:
        logger.error(f"Error fetching bench regions: {e}")
        return results

    for region in regions:
        region_id = region["region_id"]
        lat = float(region["lat"])
        lon = float(region["lon"])

        stored, success = await update_weather_for_region(lat, lon)
        results[region_id] = stored

        await asyncio.sleep(0.5)

    return results


async def get_cloud_cover_at_time(
    lat: float, lon: float, target_time: datetime
) -> Optional[int]:
    region_id = _get_region_id(lat, lon)
    target_hour = target_time.replace(minute=0, second=0, microsecond=0)

    pool = await get_pool()

    query = """
        SELECT cloud_cover_percent, fetched_at
        FROM weather_cache
        WHERE region_id = $1
          AND forecast_time = $2
        ORDER BY fetched_at DESC
        LIMIT 1
    """

    try:
        async with pool.acquire() as conn:
            row = await conn.fetchrow(query, region_id, target_hour)
            if row:
                cache_valid = _is_cache_valid(row["fetched_at"])
                return row["cloud_cover_percent"]
            return None
    except Exception as e:
        logger.error(f"Error getting cloud cover for region {region_id}: {e}")
        return None


async def is_sunny_at_time(lat: float, lon: float, target_time: datetime) -> Optional[bool]:
    cloud_cover = await get_cloud_cover_at_time(lat, lon, target_time)
    if cloud_cover is None:
        return None
    return cloud_cover < CLOUD_COVER_THRESHOLD


async def get_next_sunny_time(
    lat: float, lon: float,
    from_time: datetime,
    max_hours: int = 48
) -> Optional[datetime]:
    region_id = _get_region_id(lat, lon)
    end_time = from_time + timedelta(hours=max_hours)

    pool = await get_pool()

    query = """
        SELECT forecast_time
        FROM weather_cache
        WHERE region_id = $1
          AND forecast_time > $2
          AND forecast_time < $3
          AND cloud_cover_percent < $4
        ORDER BY forecast_time
        LIMIT 1
    """

    try:
        async with pool.acquire() as conn:
            row = await conn.fetchrow(
                query, region_id, from_time, end_time, CLOUD_COVER_THRESHOLD
            )
            return row["forecast_time"] if row else None
    except Exception as e:
        logger.error(f"Error finding next sunny time for region {region_id}: {e}")
        return None


async def cleanup_old_forecasts(retention_hours: int = 168) -> int:
    pool = await get_pool()

    query = "SELECT cleanup_weather_cache($1)"

    try:
        async with pool.acquire() as conn:
            result = await conn.fetchval(query, retention_hours)
            return result
    except Exception as e:
        logger.error(f"Error cleaning up weather cache: {e}")
        return 0


async def get_weather_summary(lat: float, lon: float) -> dict:
    region_id = _get_region_id(lat, lon)
    now = datetime.now(timezone.utc)
    end = now + timedelta(hours=24)

    pool = await get_pool()

    query = """
        SELECT
            MIN(cloud_cover_percent) as min_cloudcover,
            MAX(cloud_cover_percent) as max_cloudcover,
            COUNT(*) as total_hours,
            SUM(CASE WHEN cloud_cover_percent < 20 THEN 1 ELSE 0 END) as sunny_hours
        FROM weather_cache
        WHERE region_id = $1
          AND forecast_time > $2
          AND forecast_time < $3
    """

    try:
        async with pool.acquire() as conn:
            row = await conn.fetchrow(query, region_id, now, end)
            if row:
                return {
                    "region_id": region_id,
                    "min_cloudcover": row["min_cloudcover"],
                    "max_cloudcover": row["max_cloudcover"],
                    "total_hours": row["total_hours"],
                    "sunny_hours": row["sunny_hours"],
                }
    except Exception as e:
        logger.error(f"Error getting weather summary for {region_id}: {e}")

    return {"region_id": region_id, "error": "Unable to fetch weather data"}


async def run_weather_update_once():
    """Run weather update immediately (for testing/manual runs)."""
    logger.info("Running immediate weather update...")
    results = await update_all_region_forecasts()
    total = sum(results.values())
    logger.info(f"Weather update complete: {total} hours across {len(results)} regions")

    deleted = await cleanup_old_forecasts(168)
    if deleted > 0:
        logger.info(f"Cleaned up {deleted} old forecast records")
