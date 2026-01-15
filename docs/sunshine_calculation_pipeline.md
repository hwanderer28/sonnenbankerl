# Weekly Sun Exposure Precomputation Pipeline

This document describes the **weekly rolling computation pipeline** for sun exposure data. Instead of precomputing a full year (52,560 timestamps), the system now computes only the current week (1,008 timestamps), regenerating fresh data on each run.

## Key Differences from Yearly Approach

| Aspect | Yearly (Old) | Weekly (New) |
|--------|--------------|--------------|
| Timestamps | 52,560 | 1,008 |
| Records | ~2.6M | ~18,250 |
| Runtime | Hours to days | 15-30 minutes |
| Data retention | Full year | Rolling 7 days |
| Updates | Every 6 months | On-demand/manual |

## Architecture

```
Data Flow:
Benches (21, Stadtpark subset) → Timestamps (weekly) → Sun Positions → Exposure (final)
               ↑                                               ↓
               └────────────── Raster Data (DEM/DSM) ←─────────┘
```

### Components

1. **Benches** (`03_import_benches.sql`)
   - 21 park benches from `data/osm/graz_benches.geojson`
   - Elevation extracted from DEM raster (+ 1.2m sitting height)
   - Stored as GEOGRAPHY(POINT, 4326)

2. **Timestamps** (`04_generate_timestamps.sql`)
   - Rolling 7-day window (today + 6 days)
   - 10-minute intervals (144 per day)
   - Stored in Europe/Vienna timezone

3. **Sun Positions** (`05_compute_sun_positions.sql`)
   - Astronomical calculations using suncalc_postgres
   - Azimuth and elevation for each timestamp
   - ~365 daylight positions per week

4. **Horizons** (`compute_all_bench_horizons()`)
   - Precomputed horizon profiles for each bench
   - 2° azimuth bins out to 8 km
   - Uses downsampled 10m DEM for efficiency
   - Enables fast LOS gate checking

5. **Exposure** (`06_compute_exposure.sql`)
   - Line-of-sight analysis using horizon gate + near-field DSM checks
   - 21 benches × ~1000 timestamps (day/night) ≈ 21k records/week
   - TRUE (sunny) or FALSE (shady)

6. **Results** (`07_compute_next_week.sql`)
   - Statistics and visualization
   - Daily and bench-level breakdowns

## Quick Start

### Automated (Recommended)

```bash
# Run the complete weekly pipeline
./compute_next_week.sh
```

### Manual Step-by-Step

```bash
cd infrastructure/docker

# Step 1: Clear old data and import benches (21 benches from geojson)
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "TRUNCATE benches CASCADE; TRUNCATE sun_positions; TRUNCATE exposure; DELETE FROM timestamps WHERE ts >= CURRENT_DATE; TRUNCATE bench_horizon;"
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/03_import_benches.sql

# Step 2: Generate weekly timestamps
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/04_generate_timestamps.sql

# Step 3: Compute sun positions
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/05_compute_sun_positions.sql

# Step 4: Precompute horizons (2° bins to 8 km) - Required for efficient LOS
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_all_bench_horizons();"

# Step 5: Compute exposure using horizon gate + near-field LOS (15-30 minutes)
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_exposure_next_days_optimized(7);"

# Step 6: View results
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/07_compute_next_week.sql
```

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
| `validate_weekly_timestamps()` | Validates timestamp completeness |
| `get_timestamp_stats()` | Returns timestamp statistics |

### Sun Position Functions

| Function | Description |
|----------|-------------|
| `compute_weekly_sun_positions()` | Computes all sun positions for the week |
| `validate_sun_positions()` | Validates sun position calculations |
| `get_sun_position_stats()` | Returns statistics about sun positions |

### Exposure Functions

| Function | Description |
|----------|-------------|
| `is_exposed_optimized()` | Core line-of-sight function (optimized) |
| `compute_exposure_next_days_optimized(7)` | Computes exposure for N days |
| `compute_exposure_optimized(start, end, batch_size)` | Computes for specific date range |
| `compute_single_bench_exposure(bench_id, date)` | Test single bench |
| `get_exposure_computation_stats()` | Monitor computation progress |

### Utility Functions

| Function | Description |
|----------|-------------|
| `update_bench_elevations()` | Updates bench elevations from DEM |
| `configure_performance_settings()` | Adaptive performance configuration |
| `get_optimal_batch_size()` | Returns optimal batch size for hardware |

## Configuration and Performance

### Adaptive Performance Settings

The pipeline automatically detects hardware and configures optimal settings:

```sql
-- Automatically applied based on CPU cores and memory:
-- High-end machines (8+ cores): 8 workers, 1GB work_mem, batch_size=25
-- Mid-range (4-7 cores): 4 workers, 512MB work_mem, batch_size=15
-- Low-end/VPS: 2 workers, 256MB work_mem, batch_size=10
```

### Manual Performance Tuning

For advanced users, settings can be adjusted manually:

```sql
-- Run before computation
SET max_parallel_workers_per_gather = 8;
SET max_parallel_workers = 8;
SET work_mem = '1GB';
SET parallel_tuple_cost = 0.01;
SET parallel_setup_cost = 100;
SET effective_cache_size = '4GB';
SET random_page_cost = 1.1;  -- For SSD storage
```

### Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `distance` | 500m | Max ray length for near-field line-of-sight |
| `step_size` | Adaptive | 2m (0-100m), 5m (100-200m), 10m (200-500m) |
| `sitting_height` | 1.2m | Bench height above ground (included in bench.elevation) |
| `graz_latitude` | 47.07°N | Graz city center latitude |
| `graz_longitude` | 15.44°E | Graz city center longitude |
| `horizon_bins` | 2° | Azimuth resolution with linear interpolation |
| `horizon_range` | 8km | Precomputed horizon profile range |

## Expected Results

### Typical Runtime

| Step | Time | Description |
|------|------|-------------|
| Timestamps | < 1s | ~1000 records |
| Sun Positions | < 1s | ~1000 records |
| Horizon Precomputation | 2-5 min | 180 bins × 21 benches |
| Exposure | 10-20 min | ~18,250 records (with adaptive steps) |

### Data Volume

- **Weekly timestamps**: 1,008 (7 days × 144 intervals)
- **Daylight positions**: ~365 (varies by season)
- **Exposure records**: ~18,250 (50 benches × 365 daylight)
- **Storage**: ~5-10MB (compressed)

### Typical Results (Winter)

- **Daylight hours**: ~8-9 hours per day
- **Daylight intervals**: ~50-60 per day
- **Sunny percentage**: 60-80% (varies by bench location)

### Typical Results (Summer)

- **Daylight hours**: ~15-16 hours per day
- **Daylight intervals**: ~90-100 per day
- **Sunny percentage**: 70-90% (varies by bench location)

## Data Validation

### Validation Checks

After computation, verify results with:

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
    COUNT(*) as total_hours,
    COUNT(CASE WHEN e.exposed THEN 1 END) as sunny_hours,
    ROUND(COUNT(CASE WHEN e.exposed THEN 1 END) * 100.0 / COUNT(*), 1) as sunny_pct
FROM exposure e
JOIN benches b ON e.bench_id = b.id
GROUP BY b.id
ORDER BY sunny_hours DESC
LIMIT 10;
```

### Typical Validation Results

```
Completeness: PASS - Expected 1008, Got 1008
Elevation Range: PASS - Min: -62°, Max: 19°
Azimuth Range: PASS - Min: -150°, Max: 150°
```

## Algorithm Improvements

### Adaptive Line-of-Sight Step Sizes

The `is_exposed_optimized()` function uses adaptive step sizes for more efficient ray casting:

| Distance Range | Step Size | Samples | Rationale |
|----------------|-----------|---------|-----------|
| 0-100m | 2m | 50 | Critical near-field; obstacles have highest angular impact |
| 100-200m | 5m | 20 | Medium range; balanced coverage |
| 200-500m | 10m | 30 | Far range; distant obstacles have less angular effect |

**Expected improvement**: ~40% faster computation while maintaining accuracy.

### Horizon Angle Interpolation

The `get_horizon_angle()` function now interpolates between 2° bins instead of using simple bin lookup:

```
Azimuth 1.5°: Uses 0° bin (old) → Interpolates between 0° and 2° (new)
```

This eliminates ~2° angular blind spots at bin boundaries, providing smoother horizon profiles.

## Coordinate Systems

- **Benches**: EPSG:4326 (WGS84 lat/lon)
- **Rasters (DEM/DSM)**: EPSG:3857 (Web Mercator)
- **Transformation**: Automatic in `is_exposed_optimized()` function

## Troubleshooting

### Issue: "No DSM data available"

**Cause**: Coordinate transformation error or bench outside raster bounds

**Solution**:
```sql
-- Check bench coordinates
SELECT id, ST_AsText(geom) FROM benches;

-- Verify raster bounds
SELECT ST_XMin(rast), ST_XMax(rast), ST_YMin(rast), ST_YMax(rast) FROM dsm_raster;
```

### Issue: Computation too slow

**Cause**: Insufficient PostgreSQL configuration

**Solution**:
```sql
-- Increase work memory
SET work_mem = '1GB';

-- Reduce batch size for lower memory usage
-- Batch size is automatically optimized, but can be set manually:
SELECT compute_exposure_optimized(CURRENT_DATE, CURRENT_DATE + 6, 10);
```

### Issue: Wrong bench elevations

**Cause**: Benches not updated from DEM

**Solution**:
```sql
-- Re-run elevation update
SELECT update_bench_elevations();

-- Verify elevations
SELECT id, elevation FROM benches ORDER BY elevation;
```

### Issue: Timestamps not in expected range

**Cause**: Old timestamps from previous computation

**Solution**:
```sql
-- Clear and regenerate
DELETE FROM timestamps;
SELECT generate_weekly_timestamps();
```

## API Integration

The computed exposure data is ready for API consumption:

```sql
-- Get exposure for all benches on a specific date
SELECT * FROM exposure e
JOIN timestamps t ON e.ts_id = t.id
WHERE t.ts::DATE = CURRENT_DATE;

-- Get sunny benches for next 6 hours
SELECT b.id, b.geom, COUNT(*) as sunny_hours
FROM exposure e
JOIN benches b ON e.bench_id = b.id
JOIN timestamps t ON e.ts_id = t.id
WHERE e.exposed = true
  AND t.ts BETWEEN NOW() AND NOW() + INTERVAL '6 hours'
GROUP BY b.id, b.geom
ORDER BY sunny_hours DESC;

-- Get bench details with sun exposure
SELECT 
    b.id,
    ST_X(b.geom) as lon,
    ST_Y(b.geom) as lat,
    b.elevation,
    COUNT(CASE WHEN e.exposed THEN 1 END) as sunny_hours,
    COUNT(CASE WHEN NOT e.exposed THEN 1 END) as shady_hours
FROM benches b
LEFT JOIN exposure e ON b.id = e.bench_id
GROUP BY b.id;
```

## Maintenance

### Clear Data for Fresh Computation

```sql
DELETE FROM exposure;
DELETE FROM sun_positions;
DELETE FROM timestamps;
```

### Check Disk Usage

```sql
SELECT 
    'exposure' as table_name,
    pg_size_pretty(pg_total_relation_size('exposure')) as size
UNION ALL
SELECT 
    'dsm_raster',
    pg_size_pretty(pg_total_relation_size('dsm_raster'));
```

### Monitor Computation Progress

```sql
-- During computation
SELECT 
    COUNT(*) as computed,
    COUNT(DISTINCT bench_id) as benches_done
FROM exposure;

-- After completion
SELECT * FROM get_exposure_computation_stats();
```

## Future Improvements

- [ ] Add caching for frequently requested queries
- [ ] Implement incremental computation (only compute changed data)
- [ ] Add support for custom date ranges
- [ ] Implement parallel computation across multiple days
- [ ] Include weather data integration (cloud cover)
- [ ] Historical data retention for trend analysis
- [ ] Automated weekly cron job
- [x] Adaptive LOS step sizes (~40% faster)
- [x] Horizon angle interpolation (eliminates ~2° blind spots)
- [x] Batch API queries (fixes N+1 pattern)

## See Also

- [Precomputation README](precomputation/README.md)
- [Backend Architecture](../docs/architecture.md)
- [Database Schema](database/README.md)
- [Deployment Guide](../docs/DEPLOYMENT.md)
