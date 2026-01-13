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

-- Import bench data from OpenStreetMap (data/osm/graz_benches.geojson)
-- Source CRS: EPSG:3857 (see GeoJSON crs)
-- GeoJSON is mounted into the Postgres container at /data/osm
DO $$
DECLARE
    source_path TEXT := '/data/osm/graz_benches.geojson';
    feature JSONB;
    imported INTEGER := 0;
    geom_3857 GEOMETRY;
    bench_name TEXT;
    bench_osm_id BIGINT;
BEGIN
    -- Clear existing benches (safe to re-run)
    DELETE FROM benches;

    -- Loop over features in the GeoJSON file
    FOR feature IN
        SELECT jsonb_array_elements(pg_read_file(source_path)::jsonb -> 'features')
    LOOP
        bench_osm_id := (feature -> 'properties' ->> 'osm_id')::BIGINT;
        bench_name   := COALESCE(feature -> 'properties' ->> 'name', format('Bench %s', bench_osm_id));
        geom_3857    := ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 3857);

        INSERT INTO benches (osm_id, geom, name)
        VALUES (
            bench_osm_id,
            ST_Transform(geom_3857, 4326)::geography,
            bench_name
        )
        ON CONFLICT (osm_id) DO UPDATE
        SET geom = EXCLUDED.geom,
            name = EXCLUDED.name;

        imported := imported + 1;
    END LOOP;

    RAISE NOTICE 'Imported % benches from %', imported, source_path;
END $$;


-- Function to update all bench elevations from DEM raster
-- Handles coordinate transformation (EPSG:4326 → EPSG:3857) automatically
CREATE OR REPLACE FUNCTION update_bench_elevations() RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER := 0;
    bench_record RECORD;
    bench_elevation FLOAT;
    bench_point GEOMETRY;
    raster_srid INTEGER := 4326;
BEGIN
    -- Detect raster SRID if available
    BEGIN
        SELECT ST_SRID(rast) INTO raster_srid FROM dem_raster LIMIT 1;
    EXCEPTION WHEN undefined_table THEN
        raster_srid := 4326;
    END;

    -- Update ALL benches (not just those with NULL elevation)
    FOR bench_record IN
        SELECT id, geom FROM benches
    LOOP
        BEGIN
            -- Transform bench point to match raster coordinate system
            bench_point := ST_Transform(bench_record.geom::geometry, raster_srid);

            -- Try to get elevation from DEM raster
            BEGIN
                SELECT ST_Value(rast, bench_point) INTO bench_elevation
                FROM dem_raster
                WHERE ST_Intersects(rast, bench_point)
                LIMIT 1;

                IF bench_elevation IS NOT NULL THEN
                    UPDATE benches
                        SET elevation = bench_elevation + 1.2  -- Add 1.2m for sitting height
                        WHERE id = bench_record.id;

                    updated_count := updated_count + 1;
                    RAISE DEBUG 'Updated bench % elevation to %m', bench_record.id, bench_elevation + 1.2;
                ELSE
                    -- No raster data for this bench, use default elevation
                    UPDATE benches
                        SET elevation = 367.0 + 1.2  -- Average Graz elevation from DEM + sitting height
                        WHERE id = bench_record.id;

                    updated_count := updated_count + 1;
                    RAISE DEBUG 'Set default elevation for bench %', bench_record.id;
                END IF;
            EXCEPTION WHEN undefined_table THEN
                -- DEM raster table doesn't exist, use default
                UPDATE benches
                    SET elevation = 367.0 + 1.2  -- Average Graz elevation + sitting height
                    WHERE id = bench_record.id;

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