# GeoSphere Austria Weather API Integration Plan

> **Status: IMPLEMENTED** (2026-01-08)
>
> All phases completed. Weather API integration is functional and integrated with the exposure service.

## Goal
Integrate the GeoSphere Austria Weather API to provide real-time "is it sunny" data for Graz. This acts as a **sunshine gate** - if weather says "no sun", the app tells users no benches can be in sunshine.

---

## Existing Backend Structure (branch: `backend`)

The backend already has a working structure:

```
backend/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI app, router registration
│   ├── config.py            # Pydantic Settings (needs weather config added)
│   ├── api/
│   │   ├── __init__.py
│   │   ├── benches.py       # GET /api/benches, GET /api/benches/{id}
│   │   └── health.py        # GET /api/health
│   ├── models/
│   │   ├── __init__.py
│   │   └── bench.py         # BenchListItem, BenchDetail, Location
│   ├── services/
│   │   ├── __init__.py
│   │   └── exposure.py      # get_bench_sun_status() - KEY INTEGRATION POINT
│   └── db/
│       ├── __init__.py
│       ├── connection.py    # asyncpg connection pool
│       └── queries.py       # SQL queries
├── requirements.txt         # fastapi, uvicorn, asyncpg, pydantic
└── Dockerfile
```

**Key Patterns to Follow:**
- **Config**: `pydantic_settings.BaseSettings` with `.env` file
- **Models**: Pydantic `BaseModel` with `Field(description=...)`
- **Services**: Async functions, use `logging.getLogger(__name__)`
- **API**: `APIRouter`, `response_model`, `HTTPException` for errors

---

## Key Finding: API Data Source

**TAWES Station Data** (`tawes-v1-10min`)
- **Endpoint**: `https://dataset.api.hub.geosphere.at/v1/station/current/tawes-v1-10min`
- **Mode**: Current (real-time)
- **Update frequency**: Every 10 minutes
- **Key parameter**: `SO` (Sonnenscheindauer / sunshine duration in seconds)
- **Graz stations**:
  - `11290` - Graz Universitaet (367m)
  - `11240` - Graz-Thalerhof-Flughafen (340m)

**Logic**: If `SO > 0` in the last 10 minutes → sunny. If `SO = 0` → cloudy/overcast.

---

## Implementation Steps

### Step 1: Update Configuration
**File**: `backend/app/config.py` (MODIFY existing)

Add these settings to the existing `Settings` class:

```python
# GeoSphere Weather API
geosphere_api_url: str = "https://dataset.api.hub.geosphere.at"
geosphere_station_id: str = "11290"  # Graz Universitaet
weather_cache_ttl: int = 600  # 10 minutes
```

### Step 2: Create Weather Models
**File**: `backend/app/models/weather.py` (NEW)

Following the pattern from `bench.py`:

```python
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

class WeatherStatus(BaseModel):
    """Current weather status for sunshine gate"""
    is_sunny: bool = Field(..., description="Whether there is currently sunshine")
    sunshine_seconds: int = Field(..., description="Seconds of sunshine in last 10 min")
    station_id: str = Field(..., description="Weather station ID")
    station_name: str = Field(..., description="Weather station name")
    timestamp: datetime = Field(..., description="Data timestamp from API")
    cached_at: Optional[datetime] = Field(None, description="When data was cached")
    message: str = Field(..., description="Human-readable status message")

class WeatherResponse(BaseModel):
    """API response for weather endpoint"""
    status: WeatherStatus
    cache_hit: bool = Field(..., description="Whether response came from cache")
```

### Step 3: Create Weather Service
**File**: `backend/app/services/weather.py` (NEW)

Following the pattern from `exposure.py`:

```python
import aiohttp
import logging
from datetime import datetime
from typing import Optional
from app.config import settings
from app.models.weather import WeatherStatus

logger = logging.getLogger(__name__)

# Simple in-memory cache
_weather_cache: Optional[WeatherStatus] = None
_cache_time: Optional[datetime] = None

STATION_NAMES = {
    "11290": "Graz Universitaet",
    "11240": "Graz-Thalerhof-Flughafen",
}

async def fetch_weather_from_api() -> WeatherStatus:
    """Fetch current weather from GeoSphere TAWES API"""
    url = f"{settings.geosphere_api_url}/v1/station/current/tawes-v1-10min"
    params = {
        "parameters": "SO",
        "station_ids": settings.geosphere_station_id
    }
    # ... implementation with aiohttp

async def get_current_weather() -> WeatherStatus:
    """Get current weather, using cache if valid"""
    # Check cache validity
    # Return cached or fetch new

async def is_sunny() -> bool:
    """Simple helper for other services"""
    status = await get_current_weather()
    return status.is_sunny
```

### Step 4: Create Weather API Endpoint
**File**: `backend/app/api/weather.py` (NEW)

Following the pattern from `benches.py`:

```python
from fastapi import APIRouter, HTTPException
import logging
from app.models.weather import WeatherResponse
from app.services.weather import get_current_weather

logger = logging.getLogger(__name__)
router = APIRouter()

@router.get("/weather/current", response_model=WeatherResponse)
async def get_weather():
    """Get current weather status for Graz"""
    # ... implementation
```

### Step 5: Register Weather Router
**File**: `backend/app/main.py` (MODIFY existing)

Add import and router registration:

```python
from app.api import health, benches, weather  # Add weather

# Add this line with other router includes:
app.include_router(weather.router, prefix="/api", tags=["weather"])
```

### Step 6: Update Dependencies
**File**: `backend/requirements.txt` (MODIFY existing)

Add:
```
aiohttp==3.9.1
```

### Step 7: Integrate with Exposure Service (Optional - Phase 2)
**File**: `backend/app/services/exposure.py` (MODIFY existing)

Modify `get_bench_sun_status()` to check weather first:

```python
from app.services.weather import is_sunny

async def get_bench_sun_status(bench_id: int) -> Tuple[str, Optional[datetime], Optional[int]]:
    # Check weather gate first
    if not await is_sunny():
        return "shady", None, None  # No sun = all benches shady

    # Continue with existing exposure logic...
```

---

## Files Summary

| File | Action | Status | Purpose |
|------|--------|--------|---------|
| `backend/app/config.py` | MODIFY | ✅ Done | Add weather API settings |
| `backend/app/models/weather.py` | CREATE | ✅ Done | Weather data models |
| `backend/app/services/weather.py` | CREATE | ✅ Done | GeoSphere API client + caching |
| `backend/app/api/weather.py` | CREATE | ✅ Done | REST endpoint |
| `backend/app/main.py` | MODIFY | ✅ Done | Register weather router |
| `backend/requirements.txt` | MODIFY | ✅ Done | Add aiohttp |
| `backend/app/services/exposure.py` | MODIFY | ✅ Done | Weather gate integration |
| `backend/tests/test_weather_integration.py` | CREATE | ✅ Done | Integration test (live API) |
| `backend/tests/test_weather_unit.py` | CREATE | ✅ Done | Unit tests with mocked API |
| `backend/pytest.ini` | CREATE | ✅ Done | Pytest configuration |

---

## API Reference

**GeoSphere TAWES Endpoint**:
```
GET https://dataset.api.hub.geosphere.at/v1/station/current/tawes-v1-10min
    ?parameters=SO
    &station_ids=11290

Format: GeoJSON
Auth: None required (CC-BY 4.0 license)
```

**Expected Response** (GeoJSON):
```json
{
  "type": "FeatureCollection",
  "timestamps": ["2026-01-08T14:00:00+00:00"],
  "features": [{
    "type": "Feature",
    "geometry": {
      "type": "Point",
      "coordinates": [15.448889, 47.077778]
    },
    "properties": {
      "station": "11290",
      "parameters": {
        "SO": {
          "name": "Sonnenscheindauer",
          "unit": "s",
          "data": [360]
        }
      }
    }
  }]
}
```

**Our Weather Endpoint**:
```
GET /api/weather/current

Response:
{
  "status": {
    "is_sunny": true,
    "sunshine_seconds": 360,
    "station_id": "11290",
    "station_name": "Graz Universitaet",
    "timestamp": "2026-01-08T14:00:00Z",
    "cached_at": "2026-01-08T14:01:23Z",
    "message": "Sunny conditions - benches may be in sunlight"
  },
  "cache_hit": false
}
```

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| API timeout | Return last cached value (stale but available) |
| API error (4xx/5xx) | Log error, return cached or "unknown" status |
| No cache + API error | Return error response with 503 status |
| Invalid response format | Log warning, return "unknown" status |

---

## Testing Checklist

- [x] Mock GeoSphere API responses
- [x] Test sunny detection (`SO > 0`)
- [x] Test cloudy detection (`SO = 0`)
- [x] Test cache hit/miss
- [x] Test cache expiration after TTL
- [x] Test API timeout handling
- [x] Test API error handling
- [x] Test integration with exposure service

---

## Sources

- [GeoSphere Austria Dataset API Documentation](https://dataset.api.hub.geosphere.at/v1/docs/)
- [Getting Started Guide](https://dataset.api.hub.geosphere.at/v1/docs/getting-started.html)
- [TAWES Station Metadata](https://dataset.api.hub.geosphere.at/v1/station/current/tawes-v1-10min/metadata)
- [GeoSphere Austria Data Hub](https://data.hub.geosphere.at/)

---

## Summary

1. ✅ **Modify** `config.py` - Add GeoSphere settings
2. ✅ **Create** `models/weather.py` - Pydantic models
3. ✅ **Create** `services/weather.py` - API client with caching
4. ✅ **Create** `api/weather.py` - REST endpoint
5. ✅ **Modify** `main.py` - Register router
6. ✅ **Modify** `requirements.txt` - Add aiohttp
7. ✅ **Integrate** weather gate into exposure service

---

## Implementation Notes (2026-01-08)

### What Was Built

**1. Configuration (`config.py`)**
- Added 3 new settings: `geosphere_api_url`, `geosphere_station_id`, `weather_cache_ttl`
- Default station: `11290` (Graz Universitaet)
- Default cache TTL: 600 seconds (10 minutes)

**2. Models (`models/weather.py`)**
- `WeatherStatus`: Core model with `is_sunny`, `sunshine_seconds`, `station_id`, `station_name`, `timestamp`, `cached_at`, `message`
- `WeatherResponse`: API response wrapper with `status` and `cache_hit`

**3. Weather Service (`services/weather.py`)**
- `fetch_weather_from_api()`: Direct API call to GeoSphere TAWES endpoint
- `get_current_weather(force_refresh)`: Cached weather retrieval
- `is_sunny()`: Simple boolean helper for other services
- `get_sunshine_seconds()`: Get raw sunshine duration
- In-memory cache with TTL validation
- Graceful fallback to stale cache on API errors

**4. API Endpoint (`api/weather.py`)**
- `GET /api/weather/current?refresh=false`
- Returns current sunshine status with cache info
- 503 error on service unavailable

**5. Exposure Integration (`services/exposure.py`)**
- Weather gate added to `get_bench_sun_status()`
- If `is_sunny() == False`, returns "shady" immediately
- Optional `skip_weather_check` parameter for testing
- Reduces unnecessary database queries when cloudy

### Data Flow

```
Request → /api/benches/{id}
              ↓
       get_bench_sun_status()
              ↓
       ┌── is_sunny()? ──┐
       │                 │
      NO                YES
       │                 │
       ↓                 ↓
  Return "shady"   Query DB for
  (skip DB)        exposure data
                        ↓
                  Return status
```

### Testing

**Test files in `backend/tests/`:**
- `test_weather_unit.py` - Unit tests with mocked API (28 tests)
- `test_weather_integration.py` - Integration tests against live API

**To run unit tests:**
```bash
cd backend
source venv/bin/activate
pip install -r requirements.txt
pytest tests/test_weather_unit.py -v
```

**To run integration tests (hits real API):**
```bash
pytest tests/test_weather_integration.py -v -s
```

**To run all tests:**
```bash
pytest -v
```

**To run the server:**
```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload
# Visit: http://localhost:8000/docs
```

### API Verification

The GeoSphere API was verified working:
```bash
curl "https://dataset.api.hub.geosphere.at/v1/station/current/tawes-v1-10min?parameters=SO&station_ids=11290"
```

Returns `SO` (Sonnenscheindauer/sunshine duration) in seconds for the last 10 minutes.

### Next Steps (Future Work)

- [x] Add unit tests with mocked API responses (completed 2026-01-12)
- [ ] Maybe support multiple stations with fallback
- [ ] Maybe add SYNOP cloud cover data for more accuracy

---

## Unit Tests (2026-01-12)

### What Was Added

Created comprehensive unit tests with mocked API responses at `backend/tests/test_weather_unit.py`.

**Test Coverage (28 tests):**

| Category | Tests |
|----------|-------|
| Sunny Detection | Full sun (600s), Partial sun (180s) |
| Cloudy Detection | SO = 0 |
| Cache Behavior | Miss on first call, Hit on second, Force refresh bypass |
| Cache Expiration | Expires after TTL, Valid within TTL |
| API Timeout | Returns stale cache, Raises without cache |
| API Errors | 4xx, 5xx, Returns stale cache on error |
| Invalid Responses | Wrong format, Missing SO data |
| Helper Functions | `is_sunny()`, `get_sunshine_seconds()`, Error defaults |
| Exposure Integration | Shady when cloudy, Skip weather check, DB query when sunny |
| Status Messages | Full sun, Partial sun, Cloudy |
| Station Mapping | Known stations, Unknown station fallback |

**Run Unit Tests:**
```bash
cd backend
source venv/bin/activate
pip install -r requirements.txt
pytest tests/test_weather_unit.py -v
```

**Run All Tests:**
```bash
pytest -v
```

**Files Added:**
- `tests/__init__.py` - Package marker
- `tests/test_weather_unit.py` - Unit tests with mocked API
- `tests/test_weather_integration.py` - Integration tests (live API)
- `pytest.ini` - Pytest configuration (asyncio_mode=auto)
- Updated `requirements.txt` - Added pytest, pytest-asyncio

**Notes:**
- Tests use `unittest.mock` to mock aiohttp responses
- Cache is reset between tests via fixture
- All 28 unit tests pass
- Integration tests require network access to GeoSphere API

