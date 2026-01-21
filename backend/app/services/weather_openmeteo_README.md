# Weather Service - Open-Meteo Integration

## Overview

This service fetches weather forecasts from Open-Meteo and stores them in the database for weather-aware sun exposure queries.

## Quick Start

### Fetch Weather for a Region

```python
import asyncio
from app.services.weather_openmeteo import update_weather_for_region

# Fetch 7-day forecast for Graz
result = asyncio.run(update_weather_for_region(47.07, 15.44))
print(f"Stored {result[0]} forecasts, success={result[1]}")
```

### Check if Sunny at a Specific Time

```python
import asyncio
from datetime import datetime, timezone
from app.services.weather_openmeteo import is_sunny_at_time

now = datetime.now(timezone.utc)
is_sunny = asyncio.run(is_sunny_at_time(47.07, 15.44, now))
print(f"Sunny now: {is_sunny}")
```

### Find Next Sunny Period

```python
import asyncio
from datetime import datetime, timezone
from app.services.weather_openmeteo import get_next_sunny_time

now = datetime.now(timezone.utc)
next_sunny = asyncio.run(get_next_sunny_time(47.07, 15.44, now, max_hours=48))
print(f"Next sunny: {next_sunny}")
```

## Configuration

Settings in `backend/app/config.py`:

| Setting | Default | Description |
|---------|---------|-------------|
| `openmeteo_cache_ttl` | 300 | Cache validity in seconds (5 min) |
| `openmeteo_forecast_hours` | 168 | Forecast horizon in hours (7 days) |
| `cloud_cover_threshold` | 20 | Sunny if cloud cover < 20% |
| `weather_update_interval` | 300 | Update frequency in seconds |

## Database Schema

The `weather_cache` table stores forecasts:

| Column | Type | Description |
|--------|------|-------------|
| `region_id` | VARCHAR(50) | Region identifier (e.g., "graz_470_154") |
| `latitude` | DOUBLE | Region center latitude |
| `longitude` | DOUBLE | Region center longitude |
| `forecast_time` | TIMESTAMPTZ | Time being forecasted |
| `cloud_cover_percent` | INTEGER | Cloud cover percentage (0-100) |
| `sunshine_duration_seconds` | INTEGER | Sunshine in this hour |
| `is_sunny` | BOOLEAN | Computed: cloud_cover < 20% |
| `fetched_at` | TIMESTAMPTZ | When forecast was fetched |

## Region ID Format

Benches are grouped into ~50km regions for cache efficiency:

```
graz_470_154
     │   │
     │   └─ Longitude × 10
     └───── Latitude × 10
```

## Scheduling

### Cron Schedule (Every 5 Minutes)

```bash
# In crontab -e
*/5 * * * * cd /home/jonas/areas/uni/25W/VU_LBS/sonnenbankerl/backend && python -c "
import asyncio
from app.services.weather_openmeteo import update_all_region_forecasts
results = asyncio.run(update_all_region_forecasts())
for region, count in results.items():
    print(f'{region}: {count} forecasts')
"
```

### Daily Cleanup

```bash
# In crontab -e (2 AM daily)
0 2 * * * psql -d sonnenbankerl -c "SELECT cleanup_weather_cache(168);"
```

## Monitoring

### Check Cache Status

```sql
-- Total records per region
SELECT region_id, COUNT(*) as hours, MIN(fetched_at) as oldest
FROM weather_cache
GROUP BY region_id;

-- Sunny hours in next 24h
SELECT region_id,
       COUNT(*) FILTER (WHERE is_sunny) as sunny_hours,
       COUNT(*) as total_hours
FROM weather_cache
WHERE forecast_time > NOW()
  AND forecast_time < NOW() + INTERVAL '24 hours'
GROUP BY region_id;
```

### Health Check

```bash
# Check if weather data exists for current time
psql -d sonnenbankerl -c "
SELECT region_id, forecast_time, cloud_cover_percent, is_sunny
FROM weather_cache
WHERE forecast_time >= date_trunc('hour', NOW())
  AND forecast_time < date_trunc('hour', NOW()) + INTERVAL '1 hour'
LIMIT 5;
```

## Troubleshooting

### No Weather Data

If queries return `None` for cloud cover:

1. Check if forecasts were fetched:
   ```sql
   SELECT MAX(fetched_at) FROM weather_cache;
   ```

2. Run manual fetch:
   ```bash
   cd backend
   python -c "
   import asyncio
   from app.services.weather_openmeteo import update_all_region_forecasts
   asyncio.run(update_all_region_forecasts())
   "
   ```

3. Check API connectivity:
   ```bash
   curl "https://api.open-meteo.com/v1/forecast?latitude=47.07&longitude=15.44&hourly=cloudcover_total"
   ```

### Stale Data

If forecasts are older than expected:

1. Check update scheduler is running
2. Manually trigger update:
   ```python
   from app.services.weather_openmeteo import cleanup_old_forecasts
   cleanup_old_forecasts(168)  # Keep 7 days
   ```

### API Errors

Open-Meteo is free with no rate limits. If errors persist:

1. Check network connectivity
2. Verify Open-Meteo API status: https://status.open-meteo.com
3. Check logs for specific error messages

## API Reference

### update_weather_for_region(lat, lon) -> (int, bool)

Fetches and stores forecasts for a region.

**Returns:** `(stored_count, success)`

### update_all_region_forecasts() -> Dict[str, int]

Updates all regions with benches.

**Returns:** `{region_id: stored_count, ...}`

### is_sunny_at_time(lat, lon, target_time) -> Optional[bool]

Checks if it's sunny at a specific time.

**Returns:** `True` (sunny), `False` (cloudy), `None` (no data)

### get_next_sunny_time(lat, lon, from_time, max_hours) -> Optional[datetime]

Finds next sunny hour within the horizon.

**Returns:** `datetime` of next sunny hour, or `None`

### cleanup_old_forecasts(retention_hours) -> int

Removes forecasts older than retention period.

**Returns:** Number of deleted records
