# Precomputation Pipeline for Sun Exposure Dataset

This document outlines the comprehensive pipeline for precomputing binary sun exposure data for park benches in Graz, Austria. The dataset indicates whether each bench is exposed to sunlight (1) or not (0) at 10-minute intervals, based solely on sun position and terrain obstacles (DSM). No weather data is included.

## Assumptions and Scope
- **Benches**: ~200 for initial testing (expandable to ~1000); locations from OSM; elevation = DEM + 1.2m (representing upper body/head height).
- **Time Period**: Full year 2026 (365 days × 144 intervals/day = ~52,560 timestamps).
- **Geographic Area**: Graz, Austria (lat/lon: 47.07°N, 15.44°E).
- **Data Sources**:
  - OSM: Bench locations.
  - BEV DSM: 1m resolution for shadow calculations.
  - BEV DEM: Ground elevations.
- **Tools**: PostgreSQL + PostGIS + TimescaleDB + suncalc_postgres extension. Pure SQL implementation for maximum efficiency.
- **Performance Estimate**: Initial compute ~1-7 days on multi-core server; storage ~50-500MB (compressed); queries sub-ms.

## Pipeline Overview
The pipeline is divided into setup, data preparation, precomputation, computation, and maintenance phases. It uses a pure PostgreSQL approach for maximum performance and simplicity, with TimescaleDB for time-series efficiency.

### 1. Environment Setup
- Install PostgreSQL with extensions:
  ```bash
  # Install PostgreSQL, PostGIS, TimescaleDB
  sudo apt install postgresql postgresql-contrib postgis postgresql-*-postgis-*-scripts timescaledb-*-postgresql-*

  # Enable extensions in database
  psql -d sonnenbankerl -c "CREATE EXTENSION postgis;"
  psql -d sonnenbankerl -c "CREATE EXTENSION timescaledb;"
  psql -d sonnenbankerl -c "CREATE EXTENSION suncalc_postgres;"  # From GitHub repo
  ```
- Create database: `sonnenbankerl`.

### 2. Data Acquisition and Preparation
- **Load Benches**:
  - Query OSM for benches in Graz (e.g., via Overpass API or existing dump).
  - Import as PostGIS table:
    ```sql
    CREATE TABLE benches (
        id SERIAL PRIMARY KEY,
        osm_id BIGINT,
        geom GEOGRAPHY(POINT, 4326),
        elevation FLOAT
    );
    -- Insert data via COPY or INSERT
    ```
- **Load DSM/DEM**:
  - Download BEV DSM (1m) and DEM.
  - Import as rasters:
    ```bash
    raster2pgsql -s 4326 -I -C -M dsm.tif dsm_raster | psql -d sonnenbankerl
    raster2pgsql -s 4326 -I -C -M dem.tif dem_raster | psql -d sonnenbankerl
    ```
- **Drape Benches**:
  - Set elevation to DEM + 1.2m:
    ```sql
    UPDATE benches SET elevation = ST_Value(dem_raster, geom::geometry) + 1.2;
    ```

### 3. Precompute Timestamps and Sun Positions
- **Generate Timestamps**:
  ```sql
  CREATE TABLE timestamps (
      id SERIAL PRIMARY KEY,
      ts TIMESTAMPTZ NOT NULL UNIQUE
  );
  -- Insert 10-min intervals for 2026
  INSERT INTO timestamps (ts)
  SELECT generate_series('2026-01-01 00:00:00+01'::timestamptz, '2026-12-31 23:50:00+01'::timestamptz, '10 minutes'::interval);
  ```
- **Compute Sun Positions**:
  ```sql
  CREATE TABLE sun_positions (
      ts_id INT REFERENCES timestamps(id),
      azimuth_deg FLOAT,
      elevation_deg FLOAT,
      PRIMARY KEY (ts_id)
  );
  INSERT INTO sun_positions (ts_id, azimuth_deg, elevation_deg)
  SELECT t.id, (sp).azimuth, (sp).altitude
  FROM timestamps t,
       LATERAL get_position(t.ts, 47.07, 15.44) AS sp;
  ```

### 4. Implement Pure PostgreSQL LOS Visibility Function
- Optimized PL/pgSQL function for line-of-sight check with parallel processing:
  ```sql
  CREATE OR REPLACE FUNCTION is_exposed(
      bench_geom GEOGRAPHY, 
      azimuth FLOAT, 
      elevation FLOAT, 
      dsm RASTER
  ) RETURNS BOOLEAN AS $$
  DECLARE
      bench_point GEOMETRY := bench_geom::geometry;
      distance FLOAT := 1000;  -- Max ray length (m)
      step_size FLOAT := 10;  -- Sample every 10m
      i INT;
      obs_z FLOAT := ST_Value(dsm, bench_point) + 1.2;  -- Bench height
      max_z FLOAT := -9999;  -- Initialize to very low value
      sample_point GEOMETRY;
      sample_x FLOAT;
      sample_y FLOAT;
  BEGIN
      -- Skip nighttime checks (elevation < 0)
      IF elevation < 0 THEN
          RETURN FALSE;
      END IF;
      
      -- Sample DSM along ray to sun direction
      FOR i IN 0..(distance / step_size)::INT LOOP
          sample_x := ST_X(bench_point) + i * step_size * cos(radians(azimuth));
          sample_y := ST_Y(bench_point) + i * step_size * sin(radians(azimuth));
          sample_point := ST_MakePoint(sample_x, sample_y);
          
          -- Get DSM height at sample point
          max_z := GREATEST(max_z, COALESCE(ST_Value(dsm, sample_point), -9999));
      END LOOP;
      
      -- Check if direct line to sun is blocked
      RETURN obs_z + tan(radians(elevation)) * distance > max_z;
  END;
  $$ LANGUAGE plpgsql PARALLEL SAFE;
  ```
  
- **Performance optimizations**:
  - Mark function as `PARALLEL SAFE` for PostgreSQL parallel query execution
  - Skip nighttime calculations (elevation < 0)
  - Use `COALESCE` to handle NULL DSM values
  - Pre-tile DSM for faster raster access

### 5. Batch Compute Exposure Table
- **Create Hypertable**:
  ```sql
  CREATE TABLE exposure (
      ts_id INT REFERENCES timestamps(id),
      bench_id INT REFERENCES benches(id),
      exposed BOOLEAN NOT NULL,
      location GEOGRAPHY(POINT, 4326),  -- For spatial queries
      PRIMARY KEY (ts_id, bench_id)
  );
  SELECT create_hypertable('exposure', 'ts_id', chunk_time_interval => INTERVAL '1 month');
  CREATE INDEX ON exposure (bench_id, ts_id DESC);
  CREATE INDEX ON exposure USING GIST (location);
  ```
- **Pure PostgreSQL Batch Computation**:
  ```sql
  -- Enable parallel processing for optimal performance
  SET max_parallel_workers_per_gather = 4;
  SET work_mem = '256MB';
  SET shared_buffers = '1GB';
  
  -- Batch compute exposure data for all benches and timestamps
  INSERT INTO exposure (ts_id, bench_id, exposed, location)
  SELECT 
      t.id as ts_id,
      b.id as bench_id,
      is_exposed(b.geom, sp.azimuth_deg, sp.elevation_deg, dsm_raster) as exposed,
      b.geom as location
  FROM benches b
  CROSS JOIN timestamps t
  JOIN sun_positions sp ON sp.ts_id = t.id
  WHERE t.ts BETWEEN '2026-01-01 00:00:00+01'::timestamptz 
                AND '2026-12-31 23:50:00+01'::timestamptz
    -- Skip nighttime hours for performance (sun below horizon)
    AND sp.elevation_deg > 0
  -- PostgreSQL will automatically parallelize this query across available cores
  ON CONFLICT (ts_id, bench_id) DO NOTHING;
  
  -- For incremental updates (new benches only):
  INSERT INTO exposure (ts_id, bench_id, exposed, location)
  SELECT t.id, b.id, is_exposed(b.geom, sp.azimuth_deg, sp.elevation_deg, dsm_raster), b.geom
  FROM benches b
  WHERE b.id > (SELECT COALESCE(MAX(bench_id), 0) FROM exposure)
  CROSS JOIN timestamps t
  JOIN sun_positions sp ON sp.ts_id = t.id
  AND sp.elevation_deg > 0;
  ```
- Enable compression: `ALTER TABLE exposure SET (timescaledb.compress);`.

### 6. Pure PostgreSQL Data Management and Maintenance
- **Partitioning**: Monthly chunks (auto-managed by TimescaleDB).
- **Compression**: Enable TimescaleDB compression for storage efficiency:
  ```sql
  ALTER TABLE exposure SET (timescaledb.compress, timescaledb.compress_segmentby = 'bench_id');
  ```
- **Retention**: Drop old data automatically:
  ```sql
  SELECT add_drop_chunks_policy('exposure', INTERVAL '1 year');
  ```
- **Updates**: Recalculate every 6 months using pure SQL:
  ```sql
  -- Recompute exposure for specific date range
  DELETE FROM exposure 
  WHERE ts_id IN (SELECT id FROM timestamps WHERE ts BETWEEN '2026-07-01' AND '2026-12-31');
  
  -- Re-insert updated data
  INSERT INTO exposure (ts_id, bench_id, exposed, location)
  SELECT t.id, b.id, is_exposed(b.geom, sp.azimuth_deg, sp.elevation_deg, dsm_raster), b.geom
  FROM benches b
  CROSS JOIN timestamps t
  JOIN sun_positions sp ON sp.ts_id = t.id
  WHERE t.ts BETWEEN '2026-07-01 00:00:00+01'::timestamptz 
                AND '2026-12-31 23:50:00+01'::timestamptz
    AND sp.elevation_deg > 0;
  ```
- **Monitoring**: Built-in PostgreSQL performance views:
  ```sql
  -- Monitor computation progress
  SELECT COUNT(*) as total_records, 
         COUNT(DISTINCT bench_id) as benches_processed,
         MIN(ts) as start_time,
         MAX(ts) as end_time
  FROM exposure e
  JOIN timestamps t ON t.id = e.ts_id;
  
  -- Check query performance
  SELECT query, calls, total_time, mean_time 
  FROM pg_stat_statements 
  WHERE query LIKE '%is_exposed%' 
  ORDER BY total_time DESC;
  ```

## Validation and Testing
- Spot-check: Compare with known sunny/shady spots (e.g., open park vs. under trees).
- Performance: Query `SELECT exposed FROM exposure WHERE bench_id = 1 AND ts_id = 100;`.
- Scale: Monitor with `pg_stat_user_tables`.

## Performance Advantages of Pure PostgreSQL Approach

### **Benefits vs. Hybrid Python/PostgreSQL:**
- ✅ **No data transfer overhead** - Everything stays in database memory
- ✅ **Better parallelization** - PostgreSQL's native parallel query execution
- ✅ **Simpler deployment** - No external Python scripts or dependencies
- ✅ **Transaction safety** - Built-in ACID compliance and rollback capability
- ✅ **Easier maintenance** - Single system to monitor and update
- ✅ **Better resource utilization** - Direct memory access vs. Python round-trips

### **Performance Optimizations:**
- **Parallel query execution** - Automatic across CPU cores
- **Spatial indexing** - Optimized raster queries with PostGIS
- **TimescaleDB compression** - Reduced I/O and storage
- **Memory management** - PostgreSQL's shared_buffers and work_mem tuning
- **Batch processing** - Efficient set-based operations

### **Configuration Recommendations:**
```sql
-- PostgreSQL configuration for optimal raster performance
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
ALTER SYSTEM SET work_mem = '256MB';
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
SELECT pg_reload_conf();
```

### **Alternatives (if performance is insufficient):**
- **GRASS GIS integration** - Precompute LOS rasters, import results
- **PostgreSQL C extensions** - Custom compiled LOS functions
- **Raster tiling strategies** - Pre-tile DSM for faster access

### **Implementation Challenges:**
- **DSM sampling accuracy** - Balance between step_size and computation time
- **Memory usage** - Large rasters require proper PostgreSQL configuration
- **Computation time** - Still 1-7 days, but with better resource efficiency

This pure PostgreSQL pipeline produces a highly efficient queryable dataset for the app with minimal external dependencies. For questions, refer to README.md.</content>
<parameter name="filePath">precomputation_pipeline.md