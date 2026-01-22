from datetime import datetime, timezone, timedelta
from typing import Optional, Tuple
import logging

from app.db.queries import (
    get_current_exposure,
    get_next_sun_change,
    get_bench_status_batch,
    get_bench_by_id,
)
from app.services.weather import is_sunny as check_weather_sunny
from app.services.weather_openmeteo import (
    is_sunny_at_time,
    get_next_sunny_time,
    update_weather_for_region,
)

logger = logging.getLogger(__name__)

CLOUD_COVER_THRESHOLD = 20


def round_to_10min(dt: datetime) -> datetime:
    """Round datetime to nearest 10-minute interval"""
    return dt.replace(second=0, microsecond=0, minute=(dt.minute // 10) * 10)


def round_to_hour(dt: datetime) -> datetime:
    """Round datetime to nearest hour (30-minute threshold)"""
    if dt.minute >= 30:
        dt = dt + timedelta(hours=1)
    return dt.replace(minute=0, second=0, microsecond=0)


async def get_bench_sun_status_batch(
    bench_ids: list[int],
    skip_weather_check: bool = False
) -> dict[int, Tuple[str, Optional[datetime], Optional[int]]]:
    """
    Get current sun status for multiple benches in a single query.
    More efficient than calling get_bench_sun_status() for each bench.

    Args:
        bench_ids: List of bench IDs
        skip_weather_check: If True, skip weather gate (for testing/debugging)

    Returns:
        Dict mapping bench_id to tuple of (status, sun_until, remaining_minutes)
    """
    now = datetime.now(timezone.utc)
    rounded_time = round_to_hour(now)
    result = {}

    try:
        batch_results = await get_bench_status_batch(bench_ids, rounded_time)

        for row in batch_results:
            bench_id = row['bench_id']
            clear_sky_exposed = row['exposed']

            if clear_sky_exposed is None:
                result[bench_id] = ("unknown", None, None)
                continue

            bench = await get_bench_by_id(bench_id)
            if bench is None:
                result[bench_id] = ("unknown", None, None)
                continue

            lat = bench['lat']
            lon = bench['lon']

            is_weather_sunny = await is_sunny_at_time(lat, lon, rounded_time)

            is_effectively_sunny = (
                is_weather_sunny is True and clear_sky_exposed
            )
            effective_status = "sunny" if is_effectively_sunny else "shady"

            next_change = await get_next_sun_change_with_weather(
                bench_id, lat, lon, rounded_time, is_effectively_sunny
            )

            if next_change:
                if next_change.tzinfo is None:
                    next_change = next_change.replace(tzinfo=timezone.utc)
                time_diff = next_change - now
                remaining_minutes = int(time_diff.total_seconds() / 60)
                result[bench_id] = (effective_status, next_change, remaining_minutes)
            else:
                result[bench_id] = (effective_status, None, None)

        for bench_id in bench_ids:
            if bench_id not in result:
                result[bench_id] = ("unknown", None, None)

        return result

    except Exception as e:
        logger.error(f"Error batch getting sun status: {e}")
        for bench_id in bench_ids:
            result[bench_id] = ("unknown", None, None)
        return result


async def get_next_sun_change_with_weather(
    bench_id: int,
    lat: float,
    lon: float,
    current_time: datetime,
    current_is_sunny: bool
) -> Optional[datetime]:
    """
    Get next sun status change considering both clear-sky data and weather forecasts.

    A bench is effectively sunny only when BOTH:
    1. Weather is sunny (cloud_cover < threshold)
    2. Bench has clear-sky line-of-sight to sun

    Args:
        bench_id: Bench ID
        lat: Bench latitude
        lon: Bench longitude
        current_time: Current time
        current_is_sunny: Current effective sunny status

    Returns:
        Timestamp of next status change, or None
    """
    now = datetime.now(timezone.utc)
    search_end = now + timedelta(hours=48)

    target_status = not current_is_sunny
    candidate_times = []

    rounded_time = current_time.replace(minute=0, second=0, microsecond=0)
    check_time = rounded_time + timedelta(hours=1)

    while check_time < search_end:
        clear_sky_exposed = await get_current_exposure(bench_id, check_time)
        if clear_sky_exposed is None:
            check_time += timedelta(hours=1)
            continue

        is_weather_sunny = await is_sunny_at_time(lat, lon, check_time)

        is_effectively_sunny = (
            is_weather_sunny is True and clear_sky_exposed
        )

        if target_status:
            if is_effectively_sunny:
                return check_time
            elif is_weather_sunny is None and not clear_sky_exposed:
                candidate_times.append(check_time)
        else:
            if not is_effectively_sunny:
                return check_time
            elif is_weather_sunny is None and clear_sky_exposed:
                candidate_times.append(check_time)

        check_time += timedelta(hours=1)

    if candidate_times:
        return candidate_times[0]

    return None


async def get_bench_sun_status(
    bench_id: int, skip_weather_check: bool = False
) -> Tuple[str, Optional[datetime], Optional[int]]:
    """
    Get current sun status for a bench with weather-aware predictions.

    Args:
        bench_id: Bench ID
        skip_weather_check: If True, skip weather gate (for testing/debugging)

    Returns:
        Tuple of (status, sun_until, remaining_minutes)
        - status: "sunny", "shady", or "unknown"
        - sun_until: Timestamp when status changes to opposite (considering weather)
        - remaining_minutes: Minutes until status changes (or None)
    """
    now = datetime.now(timezone.utc)
    rounded_time = round_to_hour(now)

    try:
        bench = await get_bench_by_id(bench_id)
        if bench is None:
            logger.warning(f"Bench {bench_id} not found")
            return "unknown", None, None

        lat = bench['lat']
        lon = bench['lon']

        clear_sky_exposed = await get_current_exposure(bench_id, rounded_time)

        if clear_sky_exposed is None:
            logger.warning(f"No exposure data for bench {bench_id} at {rounded_time}")
            return "unknown", None, None

        is_weather_sunny = await is_sunny_at_time(lat, lon, rounded_time)

        is_effectively_sunny = (
            is_weather_sunny is True and clear_sky_exposed
        )
        effective_status = "sunny" if is_effectively_sunny else "shady"

        next_change = await get_next_sun_change_with_weather(
            bench_id, lat, lon, rounded_time, is_effectively_sunny
        )

        if next_change:
            if next_change.tzinfo is None:
                next_change = next_change.replace(tzinfo=timezone.utc)

            time_diff = next_change - now
            remaining_minutes = int(time_diff.total_seconds() / 60)
            if remaining_minutes < 0:
                remaining_minutes = None
            return effective_status, next_change, remaining_minutes
        else:
            return effective_status, None, None

    except Exception as e:
        logger.error(f"Error getting sun status for bench {bench_id}: {e}")
        return "unknown", None, None
