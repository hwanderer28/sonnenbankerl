# Database Schema & Migrations

PostgreSQL database with PostGIS and TimescaleDB extensions for spatial and time-series data.

## Status: ✅ Deployed

- **Database**: PostgreSQL 14
- **Extensions**: PostGIS, TimescaleDB
- **Access**: `localhost:5435` from VPS
- **Default Data**: empty; load benches/timestamps/sun via precomputation pipeline

## Structure

```
database/
└── migrations/                    # SQL migration files (run automatically)
    ├── 001_initial_schema.sql     # Core tables and extensions
    ├── 002_create_indexes.sql     # Performance indexes
    └── 003_sample_data.sql        # (deprecated) no-op placeholder; pipelines load data
```

## Automatic Migration

Migrations run automatically when the database container starts for the first time via Docker's `docker-entrypoint-initdb.d` mechanism.

**Manual migration (if needed):**

```bash
# Connect to running container
docker-compose exec postgres psql -U postgres -d sonnenbankerl

# Or run specific migration
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /docker-entrypoint-initdb.d/001_initial_schema.sql
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

## Data Loading

By default the database starts empty. Load benches, timestamps, sun positions, and exposure via the weekly precomputation pipeline (`compute_next_week.sh` or the manual 03–06 SQL steps in `precomputation/README.md`).
## Database Access

**From VPS:**
```bash
# Connect via psql
psql -h localhost -p 5435 -U postgres -d sonnenbankerl

# Example queries
SELECT COUNT(*) FROM benches;
SELECT name, ST_Y(geom::geometry) as lat, ST_X(geom::geometry) as lon FROM benches;
```

**Via Docker:**
```bash
# Connect to running container
docker-compose exec postgres psql -U postgres -d sonnenbankerl
```

## Backup & Restore

**Backup:**
```bash
docker-compose exec postgres pg_dump -U postgres sonnenbankerl | gzip > backup_$(date +%Y%m%d).sql.gz
```

**Restore:**
```bash
gunzip < backup_20251230.sql.gz | docker-compose exec -T postgres psql -U postgres sonnenbankerl
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
