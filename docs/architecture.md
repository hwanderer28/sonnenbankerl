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
│  │      Monitoring & Logging                             │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                        │
                        │ External API calls
                        │
          ┌─────────────▼────────────┐
          │  GeoSphere Austria API   │
          │  (Weather data)          │
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
SELECT create_hypertable('exposure', 'ts_id', chunk_time_interval => INTERVAL '1 month');
CREATE INDEX exposure_bench_ts_idx ON exposure (bench_id, ts_id DESC);
CREATE INDEX exposure_bench_id_idx ON exposure (bench_id);

-- Precomputed horizon profiles for efficient LOS checks
CREATE TABLE bench_horizon (
    bench_id INT NOT NULL REFERENCES benches(id) ON DELETE CASCADE,
    azimuth_deg INTEGER NOT NULL,
    max_angle_deg DOUBLE PRECISION NOT NULL,
    PRIMARY KEY (bench_id, azimuth_deg)
);

-- Raster tables (loaded via raster2pgsql)
-- dsm_raster: 1m resolution surface model
-- dem_raster: ground elevation model
```

**Storage Estimates:**
- Weekly exposure data: ~10-20 MB
- DSM/DEM rasters for Graz: 500 MB - 2 GB

**Performance Optimizations:**
- TimescaleDB compression for exposure table
- Spatial indexes on geography columns
- Partitioning by time (automatic with TimescaleDB)
- Batch database queries (eliminates N+1 pattern)
- Adaptive line-of-sight step sizes (~40% faster)

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

**GeoSphere Austria API**
- Weather data for cloud cover
- Used to mark benches as "shady" when overcast

## Deployment

See [Deployment Guide](../docs/DEPLOYMENT.md) for instructions.

## Documentation

- [Sun detailed setupshine Calculation Pipeline](../docs/sunshine_calculation_pipeline.md)
- [Database Schema](../database/README.md)
- [Precomputation Pipeline](../precomputation/README.md)
