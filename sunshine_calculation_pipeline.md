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
- **Tools**: PostgreSQL + PostGIS + TimescaleDB + suncalc_postgres extension. Python (psycopg2) for batch processing.
- **Performance Estimate**: Initial compute ~1-7 days on multi-core server; storage ~50-500MB (compressed); queries sub-ms.

## Pipeline Overview
The pipeline is divided into setup, data preparation, precomputation, computation, and maintenance phases. It aims for pure PostGIS where possible, with TimescaleDB for time-series efficiency.

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

### 4. Implement LOS Visibility Function
- Custom PL/pgSQL function for line-of-sight check:
  ```sql
  CREATE OR REPLACE FUNCTION is_exposed(bench_geom GEOGRAPHY, az FLOAT, el FLOAT, dsm RASTER)
  RETURNS BOOLEAN AS $$
  DECLARE
      bench_point GEOMETRY := bench_geom::geometry;
      sun_vector GEOMETRY;  -- Compute 3D vector to sun
      distance FLOAT := 1000;  -- Max ray length (m)
      step_size FLOAT := 10;  -- Sample every 10m
      i INT;
      obs_z FLOAT := ST_Value(dsm, bench_point) + 1.2;  -- Bench height
      max_z FLOAT;
  BEGIN
      -- Simplified: Compute sun direction, sample DSM along ray
      -- (Full implementation: Calculate 3D line, interpolate elevations)
      FOR i IN 0..(distance / step_size)::INT LOOP
          -- Sample DSM at interpolated point
          max_z := GREATEST(max_z, ST_Value(dsm, ST_Translate(bench_point, i * step_size * cos(radians(az)), i * step_size * sin(radians(az)))));
      END LOOP;
      -- Check if direct line is blocked
      RETURN obs_z + tan(radians(el)) * distance > max_z;  -- Approximate
  END;
  $$ LANGUAGE plpgsql;
  ```
  - Optimize: Pre-tile DSM; cache results.

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
- **Batch Computation** (Python Script):
  ```python
  import psycopg2
  from multiprocessing import Pool

  conn = psycopg2.connect("dbname=sonnenbankerl")

  def compute_bench(bench_id):
      cur = conn.cursor()
      cur.execute("SELECT id, geom, elevation FROM benches WHERE id = %s", (bench_id,))
      bench = cur.fetchone()
      cur.execute("SELECT ts_id, azimuth_deg, elevation_deg FROM sun_positions")
      for ts_id, az, el in cur:
          exposed = cur.execute("SELECT is_exposed(%s, %s, %s, 'dsm_raster')", (bench[1], az, el)).fetchone()[0]
          cur.execute("INSERT INTO exposure (ts_id, bench_id, exposed, location) VALUES (%s, %s, %s, %s)",
                      (ts_id, bench_id, exposed, bench[1]))
      conn.commit()

  # Run in parallel
  with Pool(4) as p:
      p.map(compute_bench, range(1, 201))  # For 200 benches
  ```
- Enable compression: `ALTER TABLE exposure SET (timescaledb.compress);`.

### 6. Data Management and Maintenance
- **Partitioning**: Monthly chunks (auto-managed).
- **Retention**: Drop old data: `SELECT add_drop_chunks_policy('exposure', INTERVAL '1 year');`.
- **Updates**: Recalculate every 6 months; insert new benches via batch script.
- **Archiving**: Detach chunks for external storage if needed.

## Validation and Testing
- Spot-check: Compare with known sunny/shady spots (e.g., open park vs. under trees).
- Performance: Query `SELECT exposed FROM exposure WHERE bench_id = 1 AND ts_id = 100;`.
- Scale: Monitor with `pg_stat_user_tables`.

## Tradeoffs and Alternatives
- **Pure DB**: Keeps integration simple but compute-intensive.
- **Alternatives**: Use GRASS for faster LOS (precompute rasters, import to PostGIS).
- **Challenges**: DSM sampling accuracy; optimize ray steps.

This pipeline produces a queryable dataset for the app. For questions, refer to README.md.</content>
<parameter name="filePath">precomputation_pipeline.md