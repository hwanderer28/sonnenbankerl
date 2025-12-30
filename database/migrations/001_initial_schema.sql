-- Initial database schema for Sonnenbankerl
-- Creates core tables for benches, timestamps, sun positions, and exposure data

-- Enable required PostgreSQL extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ============================================================================
-- Benches Table
-- ============================================================================
-- Stores bench locations from OpenStreetMap with spatial data
CREATE TABLE IF NOT EXISTS benches (
    id SERIAL PRIMARY KEY,
    osm_id BIGINT UNIQUE,
    geom GEOGRAPHY(POINT, 4326) NOT NULL,  -- PostGIS geography type (lat/lon)
    elevation FLOAT,                        -- Elevation in meters
    name TEXT,                              -- Optional bench name/description
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE benches IS 'Park bench locations in Graz';
COMMENT ON COLUMN benches.geom IS 'Geographic location (latitude/longitude)';
COMMENT ON COLUMN benches.elevation IS 'Elevation in meters above sea level';

-- ============================================================================
-- Timestamps Table
-- ============================================================================
-- Stores 10-minute interval timestamps for precomputed data
CREATE TABLE IF NOT EXISTS timestamps (
    id SERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL UNIQUE
);

COMMENT ON TABLE timestamps IS 'Time intervals (10-minute resolution) for sun exposure calculations';

-- ============================================================================
-- Sun Positions Table
-- ============================================================================
-- Precomputed sun positions for Graz at each timestamp
CREATE TABLE IF NOT EXISTS sun_positions (
    ts_id INT REFERENCES timestamps(id) ON DELETE CASCADE,
    azimuth_deg FLOAT NOT NULL,      -- Sun azimuth in degrees
    elevation_deg FLOAT NOT NULL,    -- Sun elevation in degrees
    PRIMARY KEY (ts_id)
);

COMMENT ON TABLE sun_positions IS 'Precomputed sun positions (azimuth/elevation) for each timestamp';

-- ============================================================================
-- Exposure Table (TimescaleDB Hypertable)
-- ============================================================================
-- Stores precomputed sun exposure data for each bench at each timestamp
CREATE TABLE IF NOT EXISTS exposure (
    ts_id INT REFERENCES timestamps(id) ON DELETE CASCADE,
    bench_id INT REFERENCES benches(id) ON DELETE CASCADE,
    exposed BOOLEAN NOT NULL,  -- TRUE = sunny, FALSE = shady
    PRIMARY KEY (ts_id, bench_id)
);

COMMENT ON TABLE exposure IS 'Precomputed sun exposure status for each bench at each timestamp';
COMMENT ON COLUMN exposure.exposed IS 'TRUE if bench is exposed to direct sunlight, FALSE if shaded';

-- Convert exposure table to TimescaleDB hypertable
-- Chunk interval: 8640 timestamp IDs ≈ 60 days (at 10-min intervals)
SELECT create_hypertable('exposure', 'ts_id', chunk_time_interval => 8640, if_not_exists => TRUE);

-- ============================================================================
-- Success Message
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'Schema initialized successfully';
    RAISE NOTICE 'PostGIS and TimescaleDB extensions enabled';
    RAISE NOTICE 'Tables created: benches, timestamps, sun_positions, exposure';
END $$;
