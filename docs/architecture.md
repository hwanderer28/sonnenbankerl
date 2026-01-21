# Backend Architecture

Backend infrastructure for the Sonnenbankerl application.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter Mobile App                     │
│                    (iOS/Android Clients)                    │
└──────────────────────┬──────────────────────────────────────┘
                         │ HTTPS/REST API
                         │
┌──────────────────────▼──────────────────────────────────────┐
│                     YOUR VPS SERVER                         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │            API Gateway / Load Balancer                │  │
│  │                    (Traefik)                          │  │
│  │              - SSL/TLS termination                    │  │
│  │              - Rate limiting                          │  │
│  │              - Request routing                        │  │
│  └─────────────┬──────────────────────┬──────────────────┘  │
│                │                      │                     │
│  ┌─────────────▼──────────┐  ┌────────▼──────────────────┐  │
│  │   REST API Service     │  │  Static File Service      │  │
│  │       (FastAPI)        │  │  (Optional: API docs)     │  │
│  │                        │  │                           │  │
│  │ - Bench queries        │  └───────────────────────────┘  │
│  │ - Weather integration  │                                 │
│  │ - Exposure queries     │                                 │
│  └─────────────┬──────────┘                                 │
│                │                                            │
│  ┌─────────────▼──────────────────────────────────────────┐ │
│  │         PostgreSQL Database                            │ │
│  │         + PostGIS + TimescaleDB                        │ │
│  │                                                        │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │ │
│  │  │   benches    │  │  timestamps  │  │ sun_positions│  │ │
│  │  │  (PostGIS)   │  └──────────────┘  └──────────────┘  │ │
│  │  └──────────────┘                                      │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │  exposure (TimescaleDB hypertable)               │  │ │
│  │  │  - Precomputed sun/shade data                    │  │ │
│  │  │  - 10-min intervals for 7-day window             │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │  weather_cache                                   │  │ │
│  │  │  - Hourly cloud cover forecasts (48h)            │  │ │
│  │  │  - Updated every 5 min                           │  │ │
│  │  │  - Region-based (50km grid)                      │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │      Precomputation Pipeline                          │  │
│  │      - Runs on demand (compute_next_week.sh)          │  │
│  │      - Pure SQL computation                           │  │
│  │      - Updates exposure table                         │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │      Weather Scheduler                                │  │
│  │      - Fetches Open-Meteo forecasts every 5 min       │  │
│  │      - Stores in weather_cache table                  │  │
│  │      - Cleanup old records (7 day retention)          │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                         │
                         │ External API calls
                         │
           ┌─────────────▼────────────┐
           │    Open-Meteo API        │
           │  (Weather forecasts)     │
           │  - Cloud cover %         │
           │  - Sunshine duration     │
           └──────────────────────────┘
```

## Component Breakdown

### 1. Database Layer

**Technology Stack:**
- PostgreSQL 14+
- PostGIS (spatial data)
- TimescaleDB (time-series)
- suncalc_postgres (sun position calculations)

**Database Schema:**

```sql
-- Bench locations with spatial data
CREATE TABLE benches (
    id SERIAL PRIMARY KEY,
    osm_id BIGINT UNIQUE,
    geom GEOGRAPHY(POINT, 4326) NOT NULL,
    elevation FLOAT,
    name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX benches_geom_idx ON benches USING GIST(geom);

-- Timestamp intervals (10-minute resolution)
CREATE TABLE timestamps (
    id SERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL UNIQUE
);
CREATE INDEX timestamps_ts_idx ON timestamps(ts);

-- Precomputed sun positions for Graz
CREATE TABLE sun_positions (
    ts_id INT NOT NULL REFERENCES timestamps(id) ON DELETE CASCADE,
    azimuth_deg FLOAT NOT NULL CHECK (azimuth_deg >= 0 AND azimuth_deg < 360),
    elevation_deg FLOAT NOT NULL CHECK (elevation_deg >= -90 AND elevation_deg <= 90),
    PRIMARY KEY (ts_id)
);

-- Sun exposure data (TimescaleDB hypertable)
CREATE TABLE exposure (
    ts_id INT NOT NULL REFERENCES timestamps(id) ON DELETE CASCADE,
    bench_id INT NOT NULL REFERENCES benches(id) ON DELETE CASCADE,
    exposed BOOLEAN NOT NULL,
    PRIMARY KEY (ts_id, bench_id)
);
SELECT create_hypertable('exposure', 'ts_id', chunk_time_interval => 8640);
CREATE INDEX exposure_bench_ts_idx ON exposure (bench_id, ts_id DESC);
CREATE INDEX exposure_bench_id_idx ON exposure (bench_id);

-- Precomputed horizon profiles for efficient LOS checks
CREATE TABLE bench_horizon (
    bench_id INT NOT NULL REFERENCES benches(id) ON DELETE CASCADE,
    azimuth_deg INTEGER NOT NULL,
    max_angle_deg DOUBLE PRECISION NOT NULL,
    PRIMARY KEY (bench_id, azimuth_deg)
);

-- Weather forecasts (cloud cover, Open-Meteo)
CREATE TABLE weather_cache (
    region_id VARCHAR(50) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    forecast_time TIMESTAMPTZ NOT NULL,
    cloud_cover_percent INTEGER,
    sunshine_duration_seconds INTEGER,
    is_sunny BOOLEAN GENERATED AS (cloud_cover_percent < 20) STORED,
    fetched_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (region_id, forecast_time)
);

-- Raster tables (loaded via raster2pgsql)
-- dsm_raster: 1m resolution surface model
-- dem_raster: ground elevation model
```

**Storage Estimates:**
- Weekly exposure data: ~10-20 MB
- Weather cache (48h × regions): ~1-5 MB
- DSM/DEM rasters for Graz: 500 MB - 2 GB

**Performance Optimizations:**
- TimescaleDB compression for exposure table
- Spatial indexes on geography columns
- Partitioning by time (automatic with TimescaleDB)
- Batch database queries (eliminates N+1 pattern)
- Adaptive line-of-sight step sizes (~40% faster)
- Region-based weather caching (50km grid)

### 2. REST API Service

**Technology:** Python with FastAPI

```python
from fastapi import FastAPI, Query
from typing import List
import asyncpg

app = FastAPI()

@app.get("/api/benches")
async def get_benches(
    lat: float,
    lon: float,
    radius: float = Query(1000, description="Radius in meters")
):
    # Returns benches within radius with current sun/shade status
    pass
```

**API Endpoints:**

```
GET  /api/benches
     Query params:
       - lat: float (required)
       - lon: float (required)
       - radius: float (optional, default: 1000m)
     Returns: List of benches with current sun/shade status

GET  /api/benches/{bench_id}
     Returns: Bench details with current status and next change time
```

**Response Example:**
```json
{
  "benches": [
    {
      "id": 1,
      "name": "Park Bench #1",
      "location": {"lat": 47.07, "lon": 15.44},
      "elevation": 368.2,
      "distance": 150,
      "current_status": "sunny",
      "sun_until": "2026-01-15T14:30:00Z",
      "remaining_minutes": 45
    }
  ],
  "window_start": "2026-01-15T00:00:00Z",
  "window_end": "2026-01-21T23:59:59Z"
}
```

### 3. Precomputation Pipeline

**Technology:** Pure PostgreSQL (no external Python)

**Scripts:**
- `compute_next_week.sh` - Full pipeline automation
- `06_compute_exposure.sql` - Line-of-sight computation
- `03_import_benches.sql` - Bench data import

**Execution:**
```bash
./compute_next_week.sh  # 15-30 minutes total
```

### 4. External Services

**Open-Meteo API**
- Hourly cloud cover forecasts for 48+ hours
- Updates every 5-10 minutes
- Free, no API key required
- Endpoint: `https://api.open-meteo.com/v1/forecast`
- Parameters: `cloudcover_total`, `sunshine_duration`
- Sunny threshold: `cloud_cover_percent < 20%`

**GeoSphere Austria API** (legacy/current fallback)
- Current weather conditions from TAWES stations
- Sunshine duration in seconds (10-minute window)
- Used as fallback if Open-Meteo unavailable

## Deployment

See [Deployment Guide](../docs/DEPLOYMENT.md) for instructions.

## Documentation

- [Sun detailed setupshine Calculation Pipeline](../docs/sunshine_calculation_pipeline.md)
- [Database Schema](../database/README.md)
- [Precomputation Pipeline](../precomputation/README.md)
