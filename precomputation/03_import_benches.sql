-- =============================================================================
-- OSM Bench Data Import
-- =============================================================================
-- This script handles the import of bench locations from OpenStreetMap
-- and sets up the benches table with proper spatial indexing.

-- Create benches table (if not exists from schema migration)
-- Note: This matches the schema from 001_initial_schema.sql
CREATE TABLE IF NOT EXISTS benches (
    id SERIAL PRIMARY KEY,
    osm_id BIGINT UNIQUE,
    geom GEOGRAPHY(POINT, 4326) NOT NULL,
    elevation FLOAT,
    name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add indexes for optimal performance
CREATE INDEX IF NOT EXISTS idx_benches_geom ON benches USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_benches_osm_id ON benches (osm_id);

-- Import procedure - run this after downloading OSM data
-- -----------------------------------------------------------------------------
-- Overpass API query to get benches in Graz area:
-- [out:json][timeout:25];
-- (
--   area["name"="Graz"]->.searchArea;
--   node["amenity"="bench"](area.searchArea);
--   way["amenity"="bench"](area.searchArea);
-- );
-- out geom;
-- -----------------------------------------------------------------------------

-- Sample data import (for testing) - only if benches don't exist yet
-- Replace this with your actual OSM data import process
INSERT INTO benches (osm_id, geom, name) VALUES 
-- Graz Stadtpark sample benches (for testing)
(123456789, ST_SetSRID(ST_MakePoint(15.4375, 47.0732), 4326), 'Stadtpark Bench 1'),
(123456790, ST_SetSRID(ST_MakePoint(15.4381, 47.0728), 4326), 'Stadtpark Bench 2'),
(123456791, ST_SetSRID(ST_MakePoint(15.4369, 47.0735), 4326), 'Stadtpark Bench 3')
ON CONFLICT (osm_id) DO NOTHING;

-- Function to drape benches on DEM for accurate elevation
CREATE OR REPLACE FUNCTION update_bench_elevations() RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER := 0;
    bench_record RECORD;
    bench_elevation FLOAT;
BEGIN
    -- Update bench elevations using DEM (if DEM raster exists)
    FOR bench_record IN 
        SELECT id, geom FROM benches WHERE elevation IS NULL OR elevation < 0
    LOOP
        BEGIN
            -- Only try DEM update if raster table exists
            BEGIN
                SELECT ST_Value(rast, bench_record.geom::geometry) INTO bench_elevation
                FROM dem_raster 
                WHERE ST_Intersects(rast, bench_record.geom::geometry) 
                LIMIT 1;
                
                IF bench_elevation IS NOT NULL THEN
                    UPDATE benches 
                        SET elevation = bench_elevation + 1.2  -- Add 1.2m for average sitting height
                        WHERE id = bench_record.id;
                    
                    updated_count := updated_count + 1;
                END IF;
            EXCEPTION WHEN undefined_table THEN
                -- DEM raster doesn't exist, set default elevation
                UPDATE benches 
                    SET elevation = 340 + 1.2  -- Average Graz elevation + sitting height
                    WHERE id = bench_record.id AND (elevation IS NULL OR elevation < 0);
                
                updated_count := updated_count + 1;
            END;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Could not update elevation for bench %: %', bench_record.id, SQLERRM;
        END;
    END LOOP;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- Function to import OSM bench data from GeoJSON
CREATE OR REPLACE FUNCTION import_osm_benches(geojson_file TEXT DEFAULT NULL) RETURNS INTEGER AS $$
DECLARE
    import_count INTEGER := 0;
    bbox_bounds GEOGRAPHY;
BEGIN
    -- Define Graz bounding box for validation
    bbox_bounds := ST_SetSRID(ST_MakeEnvelope(15.3, 47.0, 15.5, 47.1, 4326), 4326);
    
    -- If GeoJSON file is provided, import from it
    -- Note: This requires the file to be accessible by PostgreSQL server
    IF geojson_file IS NOT NULL THEN
        -- Import from GeoJSON (implementation depends on your setup)
        NULL;  -- Add your GeoJSON import logic here
    END IF;
    
    -- Clean up data: remove benches outside Graz area
    DELETE FROM benches WHERE NOT ST_Within(geom, bbox_bounds);
    
    -- Get count of imported benches
    SELECT COUNT(*) INTO import_count FROM benches;
    
    -- Update elevations for all benches
    PERFORM update_bench_elevations();
    
    RETURN import_count;
END;
$$ LANGUAGE plpgsql;

-- Create view for bench statistics
CREATE OR REPLACE VIEW v_bench_stats AS
SELECT 
    COUNT(*) as total_benches,
    COUNT(CASE WHEN name IS NOT NULL THEN 1 END) as named_benches,
    COUNT(CASE WHEN elevation IS NOT NULL THEN 1 END) as with_elevation,
    AVG(elevation) as avg_elevation,
    ST_AsText(ST_Centroid(ST_Collect(geom::geometry))) as center_point
FROM benches;

-- Run elevation update for existing benches
SELECT update_bench_elevations() as benches_updated;

-- Display bench statistics
SELECT * FROM v_bench_stats;

DO $$
BEGIN
    RAISE NOTICE 'OSM bench data import setup completed';
    RAISE NOTICE 'Benches with elevation data: %', (SELECT COUNT(*) FROM benches WHERE elevation IS NOT NULL);
    RAISE NOTICE 'Use import_osm_benches() function to import from OSM data';
END $$;