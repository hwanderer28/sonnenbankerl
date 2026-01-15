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
└── migrations/                    # SQL migration files (run automatically at init)
    ├── 001_initial_schema.sql     # Core tables: benches, timestamps, sun_positions, exposure
    ├── 002_create_indexes.sql     # Performance indexes
    ├── 003_add_constraints.sql    # NOT NULL, CHECK constraints (safe for base tables)
    └── 004_add_horizon_constraint.sql  # FK for bench_horizon (run in compute_next_week.sh)
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
- Elevation from DEM + 1.2m (sitting height, added during import)

**timestamps**
- 10-minute interval timestamps for the rolling 7-day window
- ~1,008 rows per week

**sun_positions**
- Precomputed sun azimuth and elevation
- One row per timestamp
- Validated with CHECK constraints (azimuth 0-360°, elevation -90° to 90°)

**exposure** (TimescaleDB hypertable)
- Binary sun exposure data (sunny/shady)
- Partitioned by time (monthly chunks)
- Primary data table for API queries
- Foreign keys ensure data integrity

**bench_horizon**
- Precomputed horizon profiles for efficient LOS checks
- 2° azimuth bins out to 8 km
- FK constraint prevents orphaned horizon data

## Data Integrity Constraints

Constraints are applied in two phases:

### Phase 1: Base Tables (`003_add_constraints.sql`)
Applied automatically when database container initializes.

**NOT NULL Constraints**
- `exposure.ts_id` - Timestamp reference required
- `exposure.bench_id` - Bench reference required

**CHECK Constraints**
- `sun_positions.azimuth_deg` - Must be >= 0 AND < 360
- `sun_positions.elevation_deg` - Must be >= -90 AND <= 90
- `benches.elevation` - Must be >= 0 (if set)

**Additional Indexes**
- `exposure_bench_id_idx` - Improves JOIN performance for bench-specific queries

### Phase 2: Horizon Table (`004_add_horizon_constraint.sql`)
Applied during `compute_next_week.sh` Step 7 (after `06_compute_exposure.sql` creates bench_horizon).

**Foreign Key Constraints**
- `bench_horizon.bench_id` → `benches(id)` ON DELETE CASCADE
- Ensures horizon data is automatically deleted when a bench is removed

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

## Running Migrations

**Phase 1 migrations** (`003_add_constraints.sql` and earlier) run automatically at container init.

**Phase 2 migration** (`004_add_horizon_constraint.sql`) runs during `compute_next_week.sh`:

```bash
# Run manually if needed (after 06_compute_exposure.sql has run)
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /migrations/004_add_horizon_constraint.sql
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
