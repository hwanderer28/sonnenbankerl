# Weather API Integration - Open-Meteo Forecasts

> **Status: REFACTORED** (2026-01-21)
>
> Upgraded from current-only GeoSphere to Open-Meteo forecasts with 48-hour prediction capability.

## Summary of Changes

| Aspect | Before | After |
|--------|--------|-------|
| Weather Source | GeoSphere TAWES (current only) | Open-Meteo (48h forecasts) |
| Cloud Cover | Sunshine seconds (10min window) | Hourly cloud cover % |
| Sunny Threshold | `sunshine_seconds > 0` | `cloud_cover_percent < 20` |
| "Next Sunny" | Not possible | 48-hour forecast horizon |
| Data Storage | In-memory cache only | `weather_cache` table in DB |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Precomputation (SQL)                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ exposure table: "clear sky" potential sun exposure        │  │
│  │ → computed for all benches, all timestamps, all days      │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Weather Adjustment Layer                        │
│  ┌────────────────────┐  ┌──────────────────────────────────┐  │
│  │ Open-Meteo API     │  │ weather_cache DB table           │  │
│  │ - Hourly forecasts │  │ - 48h horizon                    │  │
│  │ - cloud_cover_%    │  │ - Updated every 5 min            │  │
│  │ - sunshine_seconds │  │ - Region-based (50km grid)       │  │
│  └────────────────────┘  └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Query Response                               │
│  - Effective exposure = clear_sky AND weather_adjusted          │
│  - "Next sunny" from forecast data                              │
│  - Hourly granularity for predictions                           │
└─────────────────────────────────────────────────────────────────┘
```

## New Components

### Database Migration (`004_weather_cache.sql`)

```sql
CREATE TABLE weather_cache (
    region_id VARCHAR(50) NOT NULL,      -- e.g., "graz_470_154"
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    forecast_time TIMESTAMPTZ NOT NULL,
    cloud_cover_percent INTEGER,         -- 0-100
    sunshine_duration_seconds INTEGER,
    is_sunny BOOLEAN GENERATED AS (cloud_cover_percent < 20) STORED,
    fetched_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (region_id, forecast_time)
);

-- Functions for weather-aware queries
CREATE OR REPLACE FUNCTION get_weather_adjusted_exposure(bench_id, time)
CREATE OR REPLACE FUNCTION get_next_sunny_period(bench_id, from_time, max_hours)
```

### Weather Service (`weather_openmeteo.py`)

Key functions:

| Function | Purpose |
|----------|---------|
| `update_weather_for_region(lat, lon)` | Fetch and store 168h forecast |
| `update_all_region_forecasts()` | Update all bench regions |
| `is_sunny_at_time(lat, lon, time)` | Check if sunny at specific time |
| `get_next_sunny_time(lat, lon, from_time, max_hours)` | Find next sunny hour |
| `cleanup_old_forecasts(retention_hours)` | Remove stale data |

### Configuration (`config.py`)

```python
openmeteo_cache_ttl: int = 300          # 5 minutes
openmeteo_forecast_hours: int = 168     # 7 days
cloud_cover_threshold: int = 20         # Sunny if < 20%
weather_update_interval: int = 300      # Update every 5 min
```

## Data Flow

### "Is it sunny now?"

```
Request: GET /api/benches/{id}
    │
    ▼
get_bench_sun_status(bench_id)
    │
    ├─→ get_current_exposure(bench_id, now)  -- Clear sky data
    │       │
    │       ▼
    │   Returns: True/False (no clouds)
    │
    └─→ is_sunny_at_time(lat, lon, now)  -- Weather check
            │
            ├─→ Query weather_cache table
            │   │
            │   └─→ cloud_cover_percent < 20%?
            │
            └─→ If no cache: assume clear sky (optimistic)
    
    Returns: "sunny"/"shady"/"unknown", next_change, minutes
```

### "When is the bench next sunny?"

```
Request: GET /api/benches/{id}
    │
    ▼
get_next_sun_change_with_weather(bench_id, lat, lon, now, current_status)
    │
    ├─→ Search forward from now (max 48h)
    │   │
    │   ├─→ For each hour:
    │   │   ├─→ Check clear_sky_exposed
    │   │   └─→ Check cloud_cover_percent
    │   │
    │   └─→ Return first hour where both = sunny
    │
    └─→ If no forecast data: use clear_sky only (fallback)

Returns: next_sunny_timestamp or None
```

## API Integration

### Background Update Schedule

Recommended cron or scheduler:

```bash
# Update weather forecasts every 5 minutes
*/5 * * * * cd /app && python -m app.services.weather_openmeteo.update_all

# Cleanup old forecasts daily (keep 7 days)
0 2 * * * psql -c "SELECT cleanup_weather_cache(168)"
```

### Testing

```bash
# Test Open-Meteo integration
cd backend
source venv/bin/activate
python -c "
import asyncio
from app.services.weather_openmeteo import update_weather_for_region
result = asyncio.run(update_weather_for_region(47.07, 15.44))
print(f'Updated {result[0]} forecasts, success={result[1]}')
"

# Check cache contents
psql -c "SELECT region_id, COUNT(*) FROM weather_cache GROUP BY region_id;"
```

## Migration from Old System

### Old Architecture (GeoSphere TAWES)

```
┌─────────────────────────┐
│   GeoSphere TAWES API   │
│   - Current only        │
│   - 10min intervals     │
│   - Sunshine seconds    │
└────────────┬────────────┘
             │
             ▼
    ┌────────┴────────┐
    │  In-memory      │
    │  cache (10min)  │
    └────────┬────────┘
             │
             ▼
    Weather gate: if not sunny → all benches "shady"
```

### New Architecture (Open-Meteo)

```
┌─────────────────────────┐
│    Open-Meteo API       │
│   - 48h forecasts       │
│   - Hourly resolution   │
│   - Cloud cover %       │
└────────────┬────────────┘
             │
             ▼
    ┌────────┴────────┐
    │  weather_cache  │
    │  DB table       │
    │  (7 day TTL)    │
    └────────┬────────┘
             │
             ▼
    Weather-adjusted exposure:
    - clear_sky AND cloud_cover < 20%
    - "Next sunny" from forecasts
```

## Backward Compatibility

The old GeoSphere-based `weather.py` service is preserved for:

1. Legacy compatibility
2. Current-condition fallback
3. Alternative data source

However, the primary weather integration now uses Open-Meteo forecasts.

## Sunset Strategy

The GeoSphere integration can be deprecated once Open-Meteo is confirmed working in production:

1. Remove GeoSphere config from `config.py`
2. Remove `services/weather.py`
3. Update API docs

## Sources

- [Open-Meteo Forecast API](https://open-meteo.com/en/docs/forecast-api)
- [Cloud Cover Documentation](https://open-meteo.com/en/docs/marine-weather-api#hourly=cloudcover)
