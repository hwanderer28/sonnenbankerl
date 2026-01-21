import asyncio
import logging
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger
from datetime import datetime

from app.config import settings
from app.services.weather_openmeteo import (
    update_all_region_forecasts,
    cleanup_old_forecasts,
)

logger = logging.getLogger(__name__)

scheduler = AsyncIOScheduler()


async def weather_update_job():
    """Update all weather forecasts and cleanup old records."""
    try:
        logger.info("Starting scheduled weather update...")

        results = await update_all_region_forecasts()
        total = sum(results.values())
        logger.info(f"Weather update complete: {total} hours across {len(results)} regions")

        deleted = await cleanup_old_forecasts(168)
        if deleted > 0:
            logger.info(f"Cleaned up {deleted} old forecast records")

    except Exception as e:
        logger.error(f"Weather update job failed: {e}")


def start_scheduler():
    """Start the background scheduler for weather updates."""
    interval_minutes = settings.weather_update_interval // 60 or 5

    scheduler.add_job(
        weather_update_job,
        trigger=IntervalTrigger(minutes=interval_minutes),
        id="weather_update",
        name="Update weather forecasts",
        replace_existing=True,
    )

    scheduler.start()
    logger.info(f"Weather scheduler started (interval: {interval_minutes} minutes)")


def stop_scheduler():
    """Shutdown the scheduler gracefully."""
    scheduler.shutdown(wait=False)
    logger.info("Weather scheduler stopped")


def run_weather_update_once():
    """Run weather update immediately (for testing/manual runs)."""
    asyncio.run(weather_update_job())
