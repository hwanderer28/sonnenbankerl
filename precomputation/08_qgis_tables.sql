-- =============================================================================
-- QGIS Visualization Tables Setup
-- =============================================================================
-- This script creates QGIS-accessible tables with proper SRID registration.
-- Run this AFTER the main precomputation pipeline.
--
-- Creates:
-- - qgis_bench_exposure: All exposure data (18,250 records)
-- - qgis_today_exposure: Today's data only (refreshable)
--
-- Usage:
--   docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/08_qgis_tables.sql

-- Create QGIS-accessible table with proper geometry (SRID 4326)
DROP TABLE IF EXISTS qgis_bench_exposure;

CREATE TABLE qgis_bench_exposure (
    id SERIAL PRIMARY KEY,
    bench_id INTEGER NOT NULL,
    osm_id BIGINT,
    geometry GEOMETRY(POINT, 4326) NOT NULL,
    elevation FLOAT,
    timestamp TIMESTAMPTZ NOT NULL,
    is_sunny BOOLEAN NOT NULL,
    exposure_status TEXT NOT NULL,
    azimuth_deg FLOAT,
    sun_elevation FLOAT,
    UNIQUE(bench_id, timestamp)
);

-- Create indexes for performance
CREATE INDEX idx_qgis_bench_geom ON qgis_bench_exposure USING GIST (geometry);
CREATE INDEX idx_qgis_bench_timestamp ON qgis_bench_exposure (timestamp);
CREATE INDEX idx_qgis_bench_status ON qgis_bench_exposure (exposure_status);

-- Populate from existing data
INSERT INTO qgis_bench_exposure (bench_id, osm_id, geometry, elevation, timestamp, is_sunny, exposure_status, azimuth_deg, sun_elevation)
SELECT 
    b.id,
    b.osm_id,
    ST_SetSRID(ST_MakePoint(ST_X(b.geom::geometry), ST_Y(b.geom::geometry)), 4326),
    b.elevation,
    t.ts,
    e.exposed,
    CASE WHEN e.exposed THEN 'Sunny' ELSE 'Shady' END,
    sp.azimuth_deg,
    sp.elevation_deg
FROM benches b
JOIN exposure e ON b.id = e.bench_id
JOIN timestamps t ON e.ts_id = t.id
JOIN sun_positions sp ON e.ts_id = sp.ts_id
WHERE sp.elevation_deg > 0
ON CONFLICT (bench_id, timestamp) DO NOTHING;

-- Create today's exposure table (refreshable)
DROP TABLE IF EXISTS qgis_today_exposure;

CREATE TABLE qgis_today_exposure AS
SELECT * FROM qgis_bench_exposure
WHERE timestamp::date = CURRENT_DATE;

-- Add indexes
CREATE INDEX idx_qgis_today_geom ON qgis_today_exposure USING GIST (geometry);
CREATE INDEX idx_qgis_today_timestamp ON qgis_today_exposure (timestamp);

-- Function to refresh today's data
CREATE OR REPLACE FUNCTION refresh_qgis_today() RETURNS VOID AS $$
BEGIN
    TRUNCATE qgis_today_exposure;
    INSERT INTO qgis_today_exposure
    SELECT * FROM qgis_bench_exposure
    WHERE timestamp::date = CURRENT_DATE;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT ALL ON qgis_bench_exposure TO PUBLIC;
GRANT ALL ON qgis_today_exposure TO PUBLIC;
GRANT EXECUTE ON FUNCTION refresh_qgis_today TO PUBLIC;

-- Verify
DO $$
DECLARE
    total_records BIGINT;
    today_records BIGINT;
BEGIN
    SELECT COUNT(*) INTO total_records FROM qgis_bench_exposure;
    SELECT COUNT(*) INTO today_records FROM qgis_today_exposure;
    
    RAISE NOTICE '======================================';
    RAISE NOTICE 'QGIS Tables Created Successfully!';
    RAISE NOTICE '';
    RAISE NOTICE 'qgis_bench_exposure: % records', total_records;
    RAISE NOTICE 'qgis_today_exposure: % records', today_records;
    RAISE NOTICE '';
    RAISE NOTICE 'SRID: 4326 (WGS84)';
    RAISE NOTICE 'Geometry: POINT';
    RAISE NOTICE '';
    RAISE NOTICE 'To refresh today''s data:';
    RAISE NOTICE '  SELECT refresh_qgis_today();';
    RAISE NOTICE '';
    RAISE NOTICE 'In QGIS:';
    RAISE NOTICE '  Browser → PostgreSQL → Add qgis_today_exposure';
    RAISE NOTICE '  Style by: exposure_status (Sunny/Shady)';
    RAISE NOTICE '======================================';
END $$;
