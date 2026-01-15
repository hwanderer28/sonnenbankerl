# Precomputation Pipeline

SQL scripts for weekly sun exposure computation using pure PostgreSQL. No external Python required.

## Quick Start

```bash
# Run the complete weekly pipeline
./compute_next_week.sh
```

## Structure

```
precomputation/
├── 01_setup_extensions.sql          # Install PostGIS, TimescaleDB, suncalc_postgres
├── 02_import_rasters.sql            # DSM/DEM raster import verification
├── 03_import_benches.sql            # Import benches from OSM, update elevations
├── 04_generate_timestamps.sql       # Generate rolling 7-day timestamps
├── 05_compute_sun_positions.sql     # Compute sun positions for the week
├── 06_compute_exposure.sql          # Line-of-sight computation (optimized)
├── 07_compute_next_week.sql         # Results and statistics display
└── compute_next_week.sh             # Full pipeline automation
```

## Prerequisites

- PostgreSQL 14+ with PostGIS, TimescaleDB
- suncalc_postgres extension (installed automatically if missing)
- DSM/DEM raster files in `data/raw/`
- Bench GeoJSON in `data/osm/`

## Installation (Docker)

```bash
cd infrastructure/docker

# Rebuild PostgreSQL container with extensions
docker-compose build postgres
docker-compose up -d postgres

# Import data
../import_data.sh  # Select option 3 (Both rasters and benches)
```

## Usage

### Automated Pipeline

```bash
./compute_next_week.sh
```

### Manual Steps

```bash
cd infrastructure/docker

# Clear old data
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "TRUNCATE exposure; TRUNCATE sun_positions; DELETE FROM timestamps WHERE ts >= CURRENT_DATE; TRUNCATE bench_horizon;"

# Run computation
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/04_generate_timestamps.sql
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/05_compute_sun_positions.sql
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/06_compute_exposure.sql
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_all_bench_horizons();"
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_exposure_next_days_optimized(7);"
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/07_compute_next_week.sql
```

## Available Functions

```sql
-- Generate fresh timestamps
SELECT generate_weekly_timestamps();

-- Compute sun positions
SELECT compute_weekly_sun_positions();

-- Precompute horizons (2° bins to 8 km)
SELECT compute_all_bench_horizons();

-- Compute exposure for next 7 days
SELECT compute_exposure_next_days_optimized(7);

-- Compute exposure for specific date range
SELECT compute_exposure_optimized('2026-01-10', '2026-01-16', 25);

-- Monitor progress
SELECT * FROM get_exposure_computation_stats();
```

## Algorithm

### Horizon + LOS Approach

1. **Horizon Gate**: Precomputed DEM-based horizon profiles (2° bins with interpolation out to 8 km)
2. **Near-Field LOS** (≤500 m): Adaptive step check on DSM

### Adaptive Step Sizes

| Range | Step | Samples |
|-------|------|---------|
| 0-100m | 2m | 50 |
| 100-200m | 5m | 20 |
| 200-500m | 10m | 30 |

~40% faster than fixed 5m steps.

### Horizon Interpolation

Linear interpolation between 2° bins eliminates ~2° blind spots.

## Expected Runtime

| Step | Time | Records |
|------|------|---------|
| Timestamps | < 1s | 1,008 |
| Sun Positions | < 1s | 1,008 |
| Horizon Precomputation | 2-5 min | 180 bins × benches |
| Exposure | 10-20 min | ~18,250 |

## View Results

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

## Data Sources

- **DSM/DEM**: Bundesamt für Eich- und Vermessungswesen (BEV), 1m/10m resolution
- **Benches**: OpenStreetMap, amenity=bench in Graz

## Monitoring

```sql
-- Check progress during computation
SELECT COUNT(*) as records, COUNT(DISTINCT bench_id) as benches FROM exposure;

-- Database size
SELECT
    pg_size_pretty(pg_total_relation_size('exposure')) as exposure_size,
    pg_size_pretty(pg_total_relation_size('dsm_raster')) as dsm_size;
```

## Troubleshooting

### Out of memory
```sql
SET max_parallel_workers_per_gather = 2;
SET work_mem = '256MB';
```

### No benches found
```sql
SELECT COUNT(*) FROM benches;
-- If 0, re-run: ../import_data.sh (option 2)
```

### Wrong elevations
```sql
SELECT update_bench_elevations();
SELECT MIN(elevation), MAX(elevation) FROM benches;
```

## Documentation

- [Sunshine Calculation Pipeline](../docs/sunshine_calculation_pipeline.md)
- [Database Schema](../database/README.md)
- [Backend Architecture](../docs/architecture.md)
