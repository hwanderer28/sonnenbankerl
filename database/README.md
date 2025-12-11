# Database Schema & Migrations

PostgreSQL database with PostGIS and TimescaleDB extensions for spatial and time-series data.

## Structure

```
database/
├── migrations/               # SQL migration files
│   ├── 001_initial_schema.sql
│   ├── 002_create_indexes.sql
│   └── 003_timescaledb_setup.sql
└── seed/                    # Test/development data
    └── sample_benches.sql
```

## Setup

### Prerequisites
- PostgreSQL 14+
- PostGIS extension
- TimescaleDB extension

### Installation

```bash
# Install PostgreSQL and extensions (Ubuntu/Debian)
sudo apt install postgresql postgresql-contrib postgis timescaledb-postgresql-14

# Create database
sudo -u postgres createdb sonnenbankerl

# Enable extensions
psql -d sonnenbankerl -c "CREATE EXTENSION postgis;"
psql -d sonnenbankerl -c "CREATE EXTENSION timescaledb;"
```

### Run Migrations

```bash
# Run migrations in order
psql -d sonnenbankerl -f migrations/001_initial_schema.sql
psql -d sonnenbankerl -f migrations/002_create_indexes.sql
psql -d sonnenbankerl -f migrations/003_timescaledb_setup.sql
```

### Load Sample Data

```bash
# For development/testing
psql -d sonnenbankerl -f seed/sample_benches.sql
```

## Schema Overview

### Tables

**benches**
- Stores bench locations from OpenStreetMap
- PostGIS GEOGRAPHY type for spatial queries
- Elevation from DEM + 1.2m (sitting height)

**timestamps**
- 10-minute interval timestamps for 2026
- ~52,560 rows per year

**sun_positions**
- Precomputed sun azimuth and elevation
- One row per timestamp

**exposure** (TimescaleDB hypertable)
- Binary sun exposure data (sunny/shady)
- Partitioned by time (monthly chunks)
- Primary data table for API queries

**dsm_raster** / **dem_raster**
- Digital Surface Model and Digital Elevation Model
- PostGIS raster type
- Used for line-of-sight calculations

## Backup & Restore

### Backup

```bash
# Full database backup
pg_dump -U postgres sonnenbankerl | gzip > backup_$(date +%Y%m%d).sql.gz

# Tables only (without rasters)
pg_dump -U postgres -t benches -t timestamps -t sun_positions -t exposure sonnenbankerl | gzip > backup_tables.sql.gz
```

### Restore

```bash
# Restore from backup
gunzip < backup_20251211.sql.gz | psql -U postgres sonnenbankerl
```

## Performance

### Indexes

All critical queries are indexed:
- Spatial index on benches (GIST)
- Time-series index on exposure
- Composite indexes for common queries

### Query Performance

Expected query times:
- Bench lookup by location: < 10ms
- Current exposure status: < 5ms
- 24-hour exposure timeline: < 50ms

### Optimization Tips

```sql
-- Analyze tables after data import
ANALYZE benches;
ANALYZE exposure;

-- Check index usage
SELECT * FROM pg_stat_user_indexes WHERE schemaname = 'public';

-- Monitor slow queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY mean_exec_time DESC;
```

## Documentation

For more information, see:
- [Sunshine Calculation Pipeline](../docs/sunshine_calculation_pipeline.md)
- [Backend Architecture](../docs/architecture.md)
