# Weekly Sun Exposure Precomputation Pipeline

This document describes the weekly rolling computation pipeline for sun exposure data. The system computes exposure for the current week (1,008 timestamps), regenerating fresh data on each run.

## Architecture

```
Data Flow:
Benches → Timestamps (weekly) → Sun Positions → Exposure
                ↑                       ↓
                └────── Raster Data (DEM/DSM) ←──────┘
```

### Components

1. **Benches** (`03_import_benches.sql`)
   - Bench locations from `data/osm/graz_benches.geojson`
   - Elevation extracted from DEM raster (+ 1.2m sitting height)
   - Stored as GEOGRAPHY(POINT, 4326)

2. **Timestamps** (`04_generate_timestamps.sql`)
   - Rolling 7-day window (today + 6 days)
   - 10-minute intervals (144 per day)

3. **Sun Positions** (`05_compute_sun_positions.sql`)
   - Astronomical calculations using suncalc_postgres
   - Azimuth and elevation for each timestamp

4. **Horizons** (`compute_all_bench_horizons()`)
   - Precomputed horizon profiles for each bench
   - 2° azimuth bins with interpolation out to 8 km
   - Uses downsampled 10m DEM for efficiency

5. **Exposure** (`06_compute_exposure.sql`)
   - Line-of-sight analysis using horizon gate + near-field DSM
   - Adaptive step sizes for ~40% faster computation
   - TRUE (sunny) or FALSE (shady)

6. **Results** (`07_compute_next_week.sql`)
   - Statistics and visualization
   - Daily and bench-level breakdowns

## Quick Start

```bash
# Run the complete weekly pipeline
./compute_next_week.sh
```

## Execution Steps

| Step | Description | Duration |
|------|-------------|----------|
| 1 | Clean old computation data | < 1s |
| 2 | Generate weekly timestamps | < 1s |
| 3 | Compute sun positions | < 1s |
| 4 | Load exposure functions | < 1s |
| 5 | Precompute DEM horizons | 2-5 min |
| 6 | Compute exposure | 10-20 min |
| 7 | Display results | < 1s |

## File Structure

```
precomputation/
├── 01_setup_extensions.sql        # Install PostGIS, TimescaleDB, suncalc_postgres
├── 02_import_rasters.sql          # DSM/DEM raster import verification
├── 03_import_benches.sql          # Import benches from OSM, update elevations
├── 04_generate_timestamps.sql     # Generate rolling 7-day timestamps
├── 05_compute_sun_positions.sql   # Compute sun positions for the week
├── 06_compute_exposure.sql        # Line-of-sight computation (optimized)
├── 07_compute_next_week.sql       # Results and statistics display
└── compute_next_week.sh           # Shell script for full pipeline
```

## Core Functions

### Timestamp Functions

| Function | Description |
|----------|-------------|
| `generate_weekly_timestamps()` | Creates 7 days of 10-minute intervals |
| `get_timestamp_stats()` | Returns timestamp statistics |

### Sun Position Functions

| Function | Description |
|----------|-------------|
| `compute_weekly_sun_positions()` | Computes all sun positions for the week |
| `get_sun_position_stats()` | Returns statistics about sun positions |

### Exposure Functions

| Function | Description |
|----------|-------------|
| `is_exposed_optimized()` | Core line-of-sight function with adaptive steps |
| `compute_exposure_next_days_optimized(7)` | Computes exposure for N days |
| `compute_exposure_optimized(start, end, batch_size)` | Computes for specific date range |
| `compute_all_bench_horizons()` | Precomputes horizon profiles |
| `get_exposure_computation_stats()` | Monitor computation progress |

### Horizon Functions

| Function | Description |
|----------|-------------|
| `get_horizon_angle()` | Returns interpolated horizon angle for bench/azimuth |
| `compute_bench_horizon()` | Computes horizon profile for a single bench |

## Algorithm

### Line-of-Sight Calculation

The `is_exposed_optimized()` function performs a two-stage visibility analysis:

1. **Horizon Gate**: Precomputed DEM-based horizon profile (2° bins with interpolation). If solar elevation is below the interpolated horizon angle, exposure is false.
2. **Near-Field LOS** (≤500 m): Adaptive step check on DSM for local obstacles.

### Adaptive Step Sizes

| Distance Range | Step Size | Rationale |
|----------------|-----------|-----------|
| 0-100m | 2m | Critical near-field; obstacles have highest angular impact |
| 100-200m | 5m | Medium range; balanced coverage |
| 200-500m | 10m | Far range; distant obstacles have less angular effect |

Expected improvement: ~40% faster computation.

### Horizon Interpolation

The `get_horizon_angle()` function interpolates between 2° bins, eliminating ~2° angular blind spots at bin boundaries.

## Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `distance` | 500m | Near-field LOS range |
| `step_size` | Adaptive | 2m/5m/10m based on distance |
| `sitting_height` | 1.2m | Included in bench.elevation |
| `horizon_bins` | 2° | With linear interpolation |
| `horizon_range` | 8km | Precomputed horizon profile range |

## Data Volume

| Metric | Value |
|--------|-------|
| Weekly timestamps | 1,008 |
| Daylight positions | ~365 |
| Exposure records | ~18,250 |
| Storage | ~5-10MB |

## Validation

```sql
-- Check timestamp completeness
SELECT validate_weekly_timestamps();

-- Check sun position ranges
SELECT * FROM validate_sun_positions();

-- Overall statistics
SELECT * FROM get_exposure_computation_stats();

-- Bench-level breakdown
SELECT
    b.id,
    COUNT(*) as total_intervals,
    COUNT(CASE WHEN e.exposed THEN 1 END) as sunny_intervals,
    ROUND(COUNT(CASE WHEN e.exposed THEN 1 END) * 100.0 / COUNT(*), 1) as sunny_pct
FROM exposure e
JOIN benches b ON e.bench_id = b.id
GROUP BY b.id
ORDER BY sunny_intervals DESC;
```

## Coordinate Systems

| Data Type | SRID | Description |
|-----------|------|-------------|
| Benches | EPSG:4326 | WGS84 lat/lon |
| Rasters | EPSG:3857 | Web Mercator |
| Internal | Auto | Transformed in functions |

## Troubleshooting

### No benches found

```sql
-- Check bench count
SELECT COUNT(*) FROM benches;

-- Check elevation
SELECT COUNT(*) FROM benches WHERE elevation IS NOT NULL;
```

### No DSM data available

```sql
-- Verify rasters exist
SELECT COUNT(*) FROM dsm_raster;
SELECT COUNT(*) FROM dem_raster;
```

### Computation too slow

```sql
-- Increase work memory
SET work_mem = '1GB';

-- Reduce batch size
SELECT compute_exposure_optimized(CURRENT_DATE, CURRENT_DATE + 6, 10);
```

## Documentation

- [Precomputation README](precomputation/README.md)
- [Database Schema](database/README.md)
- [Backend Architecture](../docs/architecture.md)
- [Deployment Guide](../docs/DEPLOYMENT.md)
