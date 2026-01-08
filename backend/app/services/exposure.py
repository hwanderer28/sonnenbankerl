from datetime import datetime, timedelta
from typing import Optional, Tuple
import logging

from app.db.queries import get_current_exposure, get_next_sun_change
from app.services.weather import is_sunny as check_weather_sunny

logger = logging.getLogger(__name__)


def round_to_10min(dt: datetime) -> datetime:
    """Round datetime to nearest 10-minute interval"""
    return dt.replace(second=0, microsecond=0, minute=(dt.minute // 10) * 10)


async def get_bench_sun_status(
    bench_id: int, skip_weather_check: bool = False
) -> Tuple[str, Optional[datetime], Optional[int]]:
    """
    Get current sun status for a bench

    Args:
        bench_id: Bench ID
        skip_weather_check: If True, skip weather gate (for testing/debugging)

    Returns:
        Tuple of (status, sun_until, remaining_minutes)
        - status: "sunny", "shady", or "unknown"
        - sun_until: Timestamp when status changes (or None)
        - remaining_minutes: Minutes until status changes (or None)
    """
    now = datetime.utcnow()
    rounded_time = round_to_10min(now)

    try:
        # Weather gate: If no sunshine, all benches are shady
        if not skip_weather_check:
            weather_sunny = await check_weather_sunny()
            if not weather_sunny:
                logger.debug(
                    f"Weather gate: no sunshine, bench {bench_id} marked as shady"
                )
                return "shady", None, None

        # Get current exposure status from precomputed data
        exposed = await get_current_exposure(bench_id, rounded_time)

        if exposed is None:
            # No data available, return unknown
            logger.warning(f"No exposure data for bench {bench_id} at {rounded_time}")
            return "unknown", None, None

        status = "sunny" if exposed else "shady"

        # Get next change time
        next_change = await get_next_sun_change(bench_id, rounded_time, exposed)

        if next_change:
            time_diff = next_change - now
            remaining_minutes = int(time_diff.total_seconds() / 60)
            return status, next_change, remaining_minutes
        else:
            # No change found in available data
            return status, None, None

    except Exception as e:
        logger.error(f"Error getting sun status for bench {bench_id}: {e}")
        return "unknown", None, None
