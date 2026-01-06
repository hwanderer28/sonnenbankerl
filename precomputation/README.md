# Pure PostgreSQL Precomputation

This directory contains SQL scripts and documentation for sun exposure data precomputation using pure PostgreSQL. No external Python scripts are required.

## Structure

```
precomputation/
├── 01_setup_extensions.sql      # Install required PostgreSQL extensions
├── 02_import_rasters.sql        # DSM/DEM raster import commands
├── 03_import_benches.sql        # OSM bench data import
├── 04_generate_timestamps.sql   # Create time intervals for computation
├── 05_compute_sun_positions.sql # Precompute sun positions
├── 06_compute_exposure.sql      # Main exposure computation
├── 07_maintenance.sql           # Ongoing maintenance procedures
└── README.md                    # This file
```

## Prerequisites

- PostgreSQL 14+ with PostGIS, TimescaleDB, and suncalc_postgres extension
- DSM/DEM raster files (GeoTIFF format)
- Access to OpenStreetMap data
- Sufficient database memory (recommended: 4GB+ shared_buffers)

## Installation

```bash
cd precomputation

# Execute setup scripts in order
psql -d sonnenbankerl -f 01_setup_extensions.sql
psql -d sonnenbankerl -f 02_import_rasters.sql
psql -d sonnenbankerl -f 03_import_benches.sql
psql -d sonnenbankerl -f 04_generate_timestamps.sql
psql -d sonnenbankerl -f 05_compute_sun_positions.sql
psql -d sonnenbankerl -f 06_compute_exposure.sql
```

## Usage

### 1. Import DSM/DEM Rasters

```sql
-- Import Digital Surface Model (1m resolution)
-- Run from command line:
raster2pgsql -s 4326 -I -C -M ../data/raw/dsm_graz_1m.tif dsm_raster | psql -d sonnenbankerl
raster2pgsql -s 4326 -I -C -M ../data/raw/dem_graz.tif dem_raster | psql -d sonnenbankerl
```

### 2. Import Bench Data from OSM

```sql
-- Download and import benches from OpenStreetMap
-- See 03_import_benches.sql for complete import procedure
```

### 3. Run Precomputation

```sql
-- Full computation for a year (takes hours/days)
-- Configure PostgreSQL for optimal performance first:
SET max_parallel_workers_per_gather = 4;
SET work_mem = '256MB';

-- Execute main computation (see 06_compute_exposure.sql)
-- This will automatically parallelize across available CPU cores
```

### Performance Configuration

**PostgreSQL settings for optimal performance:**
```sql
-- Set these in postgresql.conf or per-session:
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
ALTER SYSTEM SET work_mem = '256MB';
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
SELECT pg_reload_conf();
```

## Algorithm Overview

### Pure PostgreSQL Line-of-Sight (LOS) Calculation

The `is_exposed()` function performs:
1. Sun position calculation using suncalc_postgres extension
2. 3D ray computation from bench to sun direction
3. DSM sampling along ray at 10m intervals
4. Obstacle detection using PostGIS raster functions
5. Binary result storage (exposed/not exposed)

### Performance

**Processing time estimates:**
- 200 benches × 52,560 timestamps: ~1-3 days (4 parallel workers)
- 1000 benches × 52,560 timestamps: ~5-7 days (4 parallel workers)

**Pure PostgreSQL advantages:**
- ✅ No data transfer overhead (everything stays in database)
- ✅ Native parallel query execution across CPU cores
- ✅ Efficient memory usage with PostgreSQL buffers
- ✅ Transaction safety and automatic rollback on errors
- ✅ Built-in query optimization and spatial indexing

**Optimization strategies:**
- PostgreSQL parallel query execution
- Spatial indexing for DSM queries
- TimescaleDB compression for storage efficiency
- Skip nighttime hours (sun elevation < 0°)
- Efficient set-based operations (no row-by-row processing)

## Scheduled Updates

For automated updates, use PostgreSQL pg_cron extension or system cron:

```bash
# Using system cron to run SQL scripts
crontab -e

# Run incremental update every 6 months (Jan 1 and Jul 1 at 2 AM)
0 2 1 1,7 * psql -d sonnenbankerl -f 07_maintenance.sql >> /var/log/sonnenbankerl/precompute.log 2>&1
```

**Or using PostgreSQL pg_cron extension:**
```sql
-- Enable pg_cron extension
CREATE EXTENSION pg_cron;

-- Schedule incremental updates every 6 months
SELECT cron.schedule(
    'sun-exposure-update',
    '0 2 1 1,7',
    $$
    -- Incremental update logic from 07_maintenance.sql
    INSERT INTO exposure (ts_id, bench_id, exposed, location)
    SELECT t.id, b.id, is_exposed(b.geom, sp.azimuth_deg, sp.elevation_deg, dsm_raster), b.geom
    FROM benches b
    CROSS JOIN timestamps t
    JOIN sun_positions sp ON sp.ts_id = t.id
    WHERE t.ts > NOW() - INTERVAL '6 months'
      AND sp.elevation_deg > 0
    ON CONFLICT (ts_id, bench_id) DO NOTHING;
    $$
);
```

## Monitoring

```sql
-- Check progress during computation
SELECT 
    COUNT(*) as total_records,
    COUNT(DISTINCT bench_id) as benches_processed,
    MIN(t.ts) as start_time,
    MAX(t.ts) as end_time,
    COUNT(CASE WHEN exposed THEN 1 END) as sunny_records,
    COUNT(CASE WHEN NOT exposed THEN 1 END) as shady_records
FROM exposure e
JOIN timestamps t ON t.id = e.ts_id
WHERE EXTRACT(YEAR FROM t.ts) = 2026;

-- Monitor database growth
SELECT 
    pg_size_pretty(pg_total_relation_size('exposure')) as exposure_table_size,
    pg_size_pretty(pg_total_relation_size('dsm_raster')) as dsm_size,
    pg_size_pretty(pg_sizeof('exposure')::bigint * COUNT(*)::bigint) as estimated_raw_size
FROM exposure;

-- Check computation progress by bench
SELECT 
    COUNT(DISTINCT bench_id) as benches_completed,
    (SELECT COUNT(*) FROM benches) as total_benches,
    ROUND(COUNT(DISTINCT bench_id)::numeric / (SELECT COUNT(*) FROM benches) * 100, 2) as completion_percent
FROM exposure
WHERE ts_id IN (
    SELECT id FROM timestamps 
    WHERE EXTRACT(YEAR FROM ts) = 2026
);

-- Monitor query performance
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements 
WHERE query LIKE '%is_exposed%' OR query LIKE '%exposure%'
ORDER BY total_time DESC
LIMIT 10;
```

## Data Sources

### DSM/DEM Data
- Source: Bundesamt für Eich- und Vermessungswesen (BEV)
- Resolution: 1m (DSM), 10m (DEM)
- Format: GeoTIFF
- Download: https://www.bev.gv.at/

### OpenStreetMap Data
- Source: OpenStreetMap
- Query: Overpass API
- Tags: amenity=bench, tourism=viewpoint
- Export: GeoJSON format

## Troubleshooting

**Out of memory errors:**
```sql
-- Reduce parallel workers temporarily
SET max_parallel_workers_per_gather = 1;
SET work_mem = '64MB';
```

**Slow DSM queries:**
```sql
-- Check if spatial indexes exist on raster tables
SELECT r_table_name, r_raster_column FROM raster_columns WHERE r_table_name IN ('dsm_raster', 'dem_raster');

-- Rebuild indexes if needed
REINDEX INDEX CONCURRENTLY dsm_raster_st_convexhull_idx;
```

**Database connection issues:**
```sql
-- Check available connections
SELECT count(*) FROM pg_stat_activity WHERE state = 'active';

-- Monitor long-running queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
FROM pg_stat_activity 
WHERE state = 'active' AND now() - pg_stat_activity.query_start > interval '5 minutes';
```

**Computation too slow:**
```sql
-- Optimize PostgreSQL configuration
ALTER SYSTEM SET shared_buffers = '2GB';
ALTER SYSTEM SET effective_cache_size = '6GB';
ALTER SYSTEM SET random_page_cost = 1.1;  -- For SSD storage
SELECT pg_reload_conf();
```

**Incomplete results:**
```sql
-- Check for missing data
SELECT 
    (SELECT COUNT(*) FROM benches) as total_benches,
    COUNT(DISTINCT bench_id) as processed_benches,
    (SELECT COUNT(*) FROM timestamps WHERE EXTRACT(YEAR FROM ts) = 2026) as total_timestamps,
    COUNT(DISTINCT ts_id) as processed_timestamps
FROM exposure;
```

## Documentation

For detailed pipeline information, see:
- [Sunshine Calculation Pipeline](../docs/sunshine_calculation_pipeline.md)
- [Backend Architecture](../docs/architecture.md)
