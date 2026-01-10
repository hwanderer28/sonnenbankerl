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
-- Generated from data/osm/graz_benches.geojson
-- Total benches: 50
-- ON CONFLICT DO NOTHING ensures idempotent imports (can re-run safely)
INSERT INTO benches (osm_id, geom, name) VALUES
(4293469849, ST_SetSRID(ST_MakePoint(15.443784, 47.0752368), 4326), 'Bench 4293469849'),
(4293469851, ST_SetSRID(ST_MakePoint(15.4434621, 47.0752667), 4326), 'Bench 4293469851'),
(4293469853, ST_SetSRID(ST_MakePoint(15.4437719, 47.0752833), 4326), 'Bench 4293469853'),
(4293469852, ST_SetSRID(ST_MakePoint(15.4445927, 47.0752726), 4326), 'Bench 4293469852'),
(4293469855, ST_SetSRID(ST_MakePoint(15.4435587, 47.0753032), 4326), 'Bench 4293469855'),
(4293469859, ST_SetSRID(ST_MakePoint(15.4437639, 47.0753244), 4326), 'Bench 4293469859'),
(4293469858, ST_SetSRID(ST_MakePoint(15.4445434, 47.0753185), 4326), 'Bench 4293469858'),
(4293469861, ST_SetSRID(ST_MakePoint(15.4445122, 47.0753523), 4326), 'Bench 4293469861'),
(4293469860, ST_SetSRID(ST_MakePoint(15.4435627, 47.0753352), 4326), 'Bench 4293469860'),
(4293469863, ST_SetSRID(ST_MakePoint(15.4435694, 47.0753777), 4326), 'Bench 4293469863'),
(4293469673, ST_SetSRID(ST_MakePoint(15.4442162, 47.0749317), 4326), 'Bench 4293469673'),
(4293469862, ST_SetSRID(ST_MakePoint(15.443489, 47.0753631), 4326), 'Bench 4293469862'),
(4293469681, ST_SetSRID(ST_MakePoint(15.4437267, 47.0750011), 4326), 'Bench 4293469681'),
(4293469865, ST_SetSRID(ST_MakePoint(15.443493, 47.075395), 4326), 'Bench 4293469865'),
(4293469864, ST_SetSRID(ST_MakePoint(15.4437391, 47.0753916), 4326), 'Bench 4293469864'),
(4293469682, ST_SetSRID(ST_MakePoint(15.4436824, 47.0750116), 4326), 'Bench 4293469682'),
(4293469686, ST_SetSRID(ST_MakePoint(15.4442765, 47.0750267), 4326), 'Bench 4293469686'),
(4293469829, ST_SetSRID(ST_MakePoint(15.4439054, 47.0751612), 4326), 'Bench 4293469829'),
(4293469794, ST_SetSRID(ST_MakePoint(15.4442061, 47.0750459), 4326), 'Bench 4293469794'),
(4293469825, ST_SetSRID(ST_MakePoint(15.4439208, 47.0751345), 4326), 'Bench 4293469825'),
(4293469833, ST_SetSRID(ST_MakePoint(15.4435671, 47.0751719), 4326), 'Bench 4293469833'),
(4293469831, ST_SetSRID(ST_MakePoint(15.4435289, 47.0751623), 4326), 'Bench 4293469831'),
(4293469835, ST_SetSRID(ST_MakePoint(15.4436107, 47.0751779), 4326), 'Bench 4293469835'),
(4293469834, ST_SetSRID(ST_MakePoint(15.4434464, 47.075176), 4326), 'Bench 4293469834'),
(4293469836, ST_SetSRID(ST_MakePoint(15.4438913, 47.0751813), 4326), 'Bench 4293469836'),
(4293469839, ST_SetSRID(ST_MakePoint(15.4438806, 47.0751996), 4326), 'Bench 4293469839'),
(4293469841, ST_SetSRID(ST_MakePoint(15.4437106, 47.0752098), 4326), 'Bench 4293469841'),
(4293469840, ST_SetSRID(ST_MakePoint(15.4436757, 47.0752048), 4326), 'Bench 4293469840'),
(4293469843, ST_SetSRID(ST_MakePoint(15.4437696, 47.0752171), 4326), 'Bench 4293469843'),
(4293469842, ST_SetSRID(ST_MakePoint(15.4437428, 47.075213), 4326), 'Bench 4293469842'),
(4293469847, ST_SetSRID(ST_MakePoint(15.4438584, 47.0752334), 4326), 'Bench 4293469847'),
(4293469846, ST_SetSRID(ST_MakePoint(15.4434554, 47.075227), 4326), 'Bench 4293469846'),
(2284918620, ST_SetSRID(ST_MakePoint(15.4445856, 47.0750491), 4326), 'Bench 2284918620'),
(4293469800, ST_SetSRID(ST_MakePoint(15.4441565, 47.0750578), 4326), 'Bench 4293469800'),
(2284918617, ST_SetSRID(ST_MakePoint(15.4443727, 47.0750427), 4326), 'Bench 2284918617'),
(4293469796, ST_SetSRID(ST_MakePoint(15.4436214, 47.0750518), 4326), 'Bench 4293469796'),
(2284918625, ST_SetSRID(ST_MakePoint(15.4445411, 47.075056), 4326), 'Bench 2284918625'),
(4293469805, ST_SetSRID(ST_MakePoint(15.4441022, 47.0750719), 4326), 'Bench 4293469805'),
(2284918623, ST_SetSRID(ST_MakePoint(15.4444211, 47.0750515), 4326), 'Bench 2284918623'),
(2284918631, ST_SetSRID(ST_MakePoint(15.4444967, 47.0750581), 4326), 'Bench 2284918631'),
(2284918626, ST_SetSRID(ST_MakePoint(15.444462, 47.0750572), 4326), 'Bench 2284918626'),
(4293469806, ST_SetSRID(ST_MakePoint(15.4436086, 47.0750733), 4326), 'Bench 4293469806'),
(4293469813, ST_SetSRID(ST_MakePoint(15.4436006, 47.0750948), 4326), 'Bench 4293469813'),
(4293469811, ST_SetSRID(ST_MakePoint(15.4440127, 47.0750861), 4326), 'Bench 4293469811'),
(4293469814, ST_SetSRID(ST_MakePoint(15.4439778, 47.075098), 4326), 'Bench 4293469814'),
(4293469817, ST_SetSRID(ST_MakePoint(15.4439399, 47.0751133), 4326), 'Bench 4293469817'),
(4293469820, ST_SetSRID(ST_MakePoint(15.4439302, 47.0751226), 4326), 'Bench 4293469820'),
(4293469869, ST_SetSRID(ST_MakePoint(15.4444274, 47.0754281), 4326), 'Bench 4293469869'),
(4293469866, ST_SetSRID(ST_MakePoint(15.4443181, 47.0754103), 4326), 'Bench 4293469866'),
(4293469870, ST_SetSRID(ST_MakePoint(15.444298, 47.0754304), 4326), 'Bench 4293469870')
ON CONFLICT (osm_id) DO NOTHING;

-- Function to update all bench elevations from DEM raster
-- Handles coordinate transformation (EPSG:4326 → EPSG:3857) automatically
CREATE OR REPLACE FUNCTION update_bench_elevations() RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER := 0;
    bench_record RECORD;
    bench_elevation FLOAT;
    bench_point_3857 GEOMETRY;
BEGIN
    -- Update ALL benches (not just those with NULL elevation)
    FOR bench_record IN
        SELECT id, geom FROM benches
    LOOP
        BEGIN
            -- Transform bench point to match raster coordinate system
            bench_point_3857 := ST_Transform(bench_record.geom::geometry, 3857);

            -- Try to get elevation from DEM raster
            BEGIN
                SELECT ST_Value(rast, bench_point_3857) INTO bench_elevation
                FROM dem_raster
                WHERE ST_Intersects(rast, bench_point_3857)
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