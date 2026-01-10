# Precomputation Pipeline

This directory contains SQL scripts and documentation for the **weekly rolling sun exposure computation** using pure PostgreSQL. No external Python scripts are required.

## Quick Start

```bash
# Run the complete weekly pipeline
cd infrastructure/docker
./compute_next_week.sh
```

Or manually:

```bash
cd infrastructure/docker

# Clear old data
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "
DELETE FROM exposure;
DELETE FROM sun_positions;
DELETE FROM timestamps;
"

# Run pipeline steps
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/03_import_benches.sql
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/04_generate_timestamps.sql
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/05_compute_sun_positions.sql
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_exposure_next_days_optimized(7);"
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/07_compute_next_week.sql
```

## Structure

```
precomputation/
├── 01_setup_extensions.sql          # Install PostgreSQL extensions
├── 02_import_rasters.sql            # DSM/DEM raster import verification
├── 03_import_benches.sql            # Import benches from OSM, update elevations
├── 04_generate_timestamps.sql       # Generate rolling 7-day timestamps
├── 05_compute_sun_positions.sql     # Compute sun positions for the week
├── 06_compute_exposure.sql          # Line-of-sight computation (optimized)
├── 07_compute_next_week.sql         # Results and statistics display
├── 08_qgis_tables.sql               # QGIS visualization tables
└── README.md                        # This file
precomputation/
├── 01_setup_extensions.sql          # Install PostgreSQL extensions
├── 02_import_rasters.sql            # DSM/DEM raster import verification
├── 03_import_benches.sql            # Import benches from OSM, update elevations
├── 04_generate_timestamps.sql       # Generate rolling 7-day timestamps
├── 05_compute_sun_positions.sql     # Compute sun positions for the week
├── 06_compute_exposure.sql          # Line-of-sight computation (optimized)
├── 07_compute_next_week.sql         # Results and statistics display
├── compute_next_week.sh             # Shell script for full pipeline
└── README.md                        # This file
```

## Prerequisites

- PostgreSQL 14+ with PostGIS, TimescaleDB, and suncalc_postgres extension
- DSM/DEM raster files (GeoTIFF format) in `data/raw/` directory
- OSM bench data in `data/osm/` directory (for reference)
- Recommended: 4GB+ database memory for optimal performance

## Installation (Docker)

### First Time Setup

```bash
cd infrastructure/docker

# Rebuild PostgreSQL container with extensions
docker-compose build postgres
docker-compose up -d postgres

# Wait for container to be ready
sleep 5
```

### Import Data

```bash
# Verify and import rasters
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/02_import_rasters.sql

# Import benches (includes elevation update from DEM)
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/03_import_benches.sql
```

### Run Precomputation

```bash
# Generate timestamps for current week
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/04_generate_timestamps.sql

# Compute sun positions
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/05_compute_sun_positions.sql

# Compute exposure (15-30 minutes)
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_exposure_next_days_optimized(7);"

# View results
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/07_compute_next_week.sql
```

## Usage

### Available Functions

```sql
-- Generate fresh timestamps for the week
SELECT generate_weekly_timestamps();

-- Compute sun positions for the week
SELECT compute_weekly_sun_positions();

-- Compute exposure for next 7 days (recommended)
SELECT compute_exposure_next_days_optimized(7);

-- Compute exposure for specific date range
SELECT compute_exposure_optimized('2026-01-10', '2026-01-16', 25);

-- Test single bench on a specific date
SELECT compute_single_bench_exposure(7, CURRENT_DATE);

-- Monitor progress
SELECT * FROM get_exposure_computation_stats();

-- View bench statistics
SELECT * FROM v_bench_stats;
```

### View Results

```sql
-- Overall statistics
SELECT * FROM get_exposure_computation_stats();

-- Daily breakdown
SELECT 
    t.ts::DATE as date,
    COUNT(*) as records,
    ROUND(COUNT(CASE WHEN e.exposed THEN 1 END) * 100.0 / COUNT(*), 1) as sunny_pct
FROM exposure e
JOIN timestamps t ON e.ts_id = t.id
GROUP BY t.ts::DATE
ORDER BY t.ts::DATE;

-- Top 10 sunniest benches
SELECT 
    b.id,
    COUNT(CASE WHEN e.exposed THEN 1 END) as sunny_hours,
    ROUND(COUNT(CASE WHEN e.exposed THEN 1 END) * 100.0 / 365, 1) as sunny_pct
FROM exposure e
JOIN benches b ON e.bench_id = b.id
GROUP BY b.id
ORDER BY sunny_hours DESC
LIMIT 10;
```

## Performance

### Adaptive Configuration

The pipeline automatically adjusts settings based on hardware:

| Hardware | Workers | Work Mem | Batch Size |
|----------|---------|----------|------------|
| High-end (8+ cores) | 8 | 1GB | 25 |
| Mid-range (4-7 cores) | 4 | 512MB | 15 |
| Low-end/VPS | 2 | 256MB | 10 |

### Expected Runtime

| Step | Time | Records |
|------|------|---------|
| Timestamps | < 1s | 1,008 |
| Sun Positions | < 1s | 1,008 |
| Exposure | 15-30 min | ~18,250 |

### Manual Tuning

```sql
-- Increase parallel workers
SET max_parallel_workers_per_gather = 8;
SET max_parallel_workers = 8;

-- Increase work memory
SET work_mem = '1GB';

-- Optimize for SSD
SET random_page_cost = 1.1;
SET effective_cache_size = '4GB';
```

## Algorithm

### Line-of-Sight Calculation

The `is_exposed_optimized()` function performs:

1. **Sun position**: Calculated using suncalc_postgres extension
2. **Ray casting**: 1000m ray from bench toward sun (10m steps)
3. **DSM sampling**: Sample terrain height along ray
4. **Obstacle detection**: Compare terrain height vs sun line
5. **Result**: TRUE (sunny) or FALSE (shady)

### Key Parameters

- **Ray distance**: 1000m (max)
- **Step size**: 10m (sampling interval)
- **Bench height**: DEM elevation + 1.2m (sitting height)
- **Nighttime skip**: Sun elevation ≤ 0° (skipped for performance)

## Data Sources

### DSM/DEM Rasters
- **Source**: Bundesamt für Eich- und Vermessungswesen (BEV)
- **Resolution**: 1m (DSM), 10m (DEM)
- **Format**: GeoTIFF
- **Coordinate System**: EPSG:3857 (Web Mercator)

### Bench Locations
- **Source**: OpenStreetMap
- **Query**: Overpass API for amenity=bench in Graz
- **Format**: GeoJSON
- **Coordinate System**: EPSG:4326 (WGS84)

## Coordinate Systems

| Data Type | SRID | Description |
|-----------|------|-------------|
| Benches | EPSG:4326 | WGS84 lat/lon |
| Rasters | EPSG:3857 | Web Mercator |
| Transformation | Automatic | In `is_exposed_optimized()` |

## Monitoring

### During Computation

```sql
-- Check progress
SELECT 
    COUNT(*) as records,
    COUNT(DISTINCT bench_id) as benches
FROM exposure;

-- Check current activity
SELECT 
    pid,
    state,
    NOW() - query_start as duration,
    query
FROM pg_stat_activity
WHERE state = 'active';
```

### After Completion

```sql
-- Overall statistics
SELECT * FROM get_exposure_computation_stats();

-- Database size
SELECT 
    pg_size_pretty(pg_total_relation_size('exposure')) as exposure_size,
    pg_size_pretty(pg_total_relation_size('dsm_raster')) as dsm_size;

-- Query performance
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
WHERE query LIKE '%exposure%'
ORDER BY total_time DESC
LIMIT 5;
```

## Troubleshooting

### Out of Memory
```sql
-- Reduce parallel workers temporarily
SET max_parallel_workers_per_gather = 2;
SET work_mem = '256MB';
```

### Slow Computation
```sql
-- Optimize PostgreSQL configuration
ALTER SYSTEM SET shared_buffers = '2GB';
ALTER SYSTEM SET effective_cache_size = '6GB';
SELECT pg_reload_conf();
```

### No Data Generated
```sql
-- Check if benches exist
SELECT COUNT(*) FROM benches;

-- Check if rasters exist
SELECT COUNT(*) FROM dsm_raster;
SELECT COUNT(*) FROM dem_raster;

-- Verify timestamps
SELECT MIN(ts), MAX(ts) FROM timestamps;
```

### Wrong Elevations
```sql
-- Re-run elevation update
SELECT update_bench_elevations();

-- Check elevation range
SELECT MIN(elevation), MAX(elevation) FROM benches;
```

## Maintenance

### Clear All Computed Data

```sql
DELETE FROM exposure;
DELETE FROM sun_positions;
DELETE FROM timestamps;
```

### Reset Bench Elevations

```sql
-- Set to NULL first, then update
UPDATE benches SET elevation = NULL;
SELECT update_bench_elevations();
```

### Check Index Health

```sql
-- Check for missing indexes
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE tablename IN ('benches', 'timestamps', 'sun_positions', 'exposure');
```

## Documentation

- [Detailed Pipeline Documentation](../docs/sunshine_calculation_pipeline.md)
- [Backend Architecture](../docs/architecture.md)
- [Database Schema](../database/README.md)
- [Deployment Guide](../docs/DEPLOYMENT.md)
