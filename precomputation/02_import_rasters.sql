-- =============================================================================
-- DSM/DEM Raster Import
-- =============================================================================
-- This script handles the import of Digital Surface Model (DSM) and Digital Elevation Model (DEM) data
-- using PostGIS raster functionality. These rasters are essential for line-of-sight calculations.

-- Import commands (run from shell):
-- -----------------------------------------------------------------------------
-- raster2pgsql -s 4326 -I -C -M ../data/raw/dsm_graz_1m.tif dsm_raster | psql -d sonnenbankerl
-- raster2pgsql -s 4326 -I -C -M ../data/raw/dem_graz.tif dem_raster | psql -d sonnenbankerl
-- -----------------------------------------------------------------------------

-- After importing rasters, verify their properties
DO $$
DECLARE
    dsm_count integer;
    dem_count integer;
    dsm_extent record;
    dem_extent record;
BEGIN
    -- Check if raster tables exist and have data
    SELECT COUNT(*) INTO dsm_count FROM information_schema.tables WHERE table_name = 'dsm_raster';
    SELECT COUNT(*) INTO dem_count FROM information_schema.tables WHERE table_name = 'dem_raster';
    
    IF dsm_count = 0 THEN
        RAISE NOTICE 'Warning: dsm_raster table not found. Please import DSM data first.';
        RETURN;
    END IF;
    
    IF dem_count = 0 THEN
        RAISE NOTICE 'Warning: dem_raster table not found. Please import DEM data first.';
        RETURN;
    END IF;
    
    -- Get raster extents
    EXECUTE 'SELECT ST_SummaryStatsAgg(ST_Union(rast)) as stats FROM dsm_raster' INTO dsm_extent;
    EXECUTE 'SELECT ST_SummaryStatsAgg(ST_Union(rast)) as stats FROM dem_raster' INTO dem_extent;
    
    RAISE NOTICE 'DSM raster imported successfully: % tiles, %.2f MB', 
                 (SELECT COUNT(*) FROM dsm_raster), 
                 (SELECT pg_size_pretty(pg_total_relation_size('dsm_raster')));
    
    RAISE NOTICE 'DEM raster imported successfully: % tiles, %.2f MB', 
                 (SELECT COUNT(*) FROM dem_raster), 
                 (SELECT pg_size_pretty(pg_total_relation_size('dem_raster')));
END $$;

-- Create optimized indexes for raster queries
CREATE INDEX IF NOT EXISTS idx_dsm_raster_st_convexhull ON dsm_raster USING GIST (ST_ConvexHull(rast));
CREATE INDEX IF NOT EXISTS idx_dem_raster_st_convexhull ON dem_raster USING GIST (ST_ConvexHull(rast));

-- Create spatial constraints to ensure data integrity
ALTER TABLE dsm_raster ADD CONSTRAINT enforce_srid_dsm CHECK (ST_SRID(rast) = 4326);
ALTER TABLE dem_raster ADD CONSTRAINT enforce_srid_dem CHECK (ST_SRID(rast) = 4326);

-- Create view for easy raster access
CREATE OR REPLACE VIEW v_raster_info AS
SELECT 
    'dsm_raster' as table_name,
    COUNT(*) as tile_count,
    pg_size_pretty(pg_total_relation_size('dsm_raster')) as table_size,
    ST_SRID(rast) as srid,
    ST_Width(rast) as pixel_width,
    ST_Height(rast) as pixel_height,
    ST_ScaleX(rast) as pixel_size_x,
    ST_ScaleY(rast) as pixel_size_y
FROM dsm_raster
UNION ALL
SELECT 
    'dem_raster' as table_name,
    COUNT(*) as tile_count,
    pg_size_pretty(pg_total_relation_size('dem_raster')) as table_size,
    ST_SRID(rast) as srid,
    ST_Width(rast) as pixel_width,
    ST_Height(rast) as pixel_height,
    ST_ScaleX(rast) as pixel_size_x,
    ST_ScaleY(rast) as pixel_size_y
FROM dem_raster;

-- Grant permissions to application user
-- Note: Using postgres superuser, no additional grants needed
-- Note: Using postgres superuser, no additional grants needed
-- Note: Using postgres superuser, no additional grants needed

-- Sample query to test raster functionality
CREATE OR REPLACE FUNCTION test_raster_access() RETURNS TEXT AS $$
DECLARE
    sample_dsm_val float;
    sample_dem_val float;
    test_point geography := ST_SetSRID(ST_MakePoint(15.44, 47.07), 4326); -- Graz center
BEGIN
    -- Test DSM access
    SELECT ST_Value(rast, test_point::geometry) INTO sample_dsm_val 
    FROM dsm_raster 
    WHERE ST_Intersects(rast, test_point::geometry) 
    LIMIT 1;
    
    -- Test DEM access
    SELECT ST_Value(rast, test_point::geometry) INTO sample_dem_val 
    FROM dem_raster 
    WHERE ST_Intersects(rast, test_point::geometry) 
    LIMIT 1;
    
    RETURN format('Test successful - DSM: %s m, DEM: %s m', sample_dsm_val, sample_dem_val);
EXCEPTION WHEN OTHERS THEN
    RETURN format('Raster test failed: %s', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- Run the test
SELECT test_raster_access();

DO $$
BEGIN
    RAISE NOTICE 'DSM/DEM raster import configuration completed';
    RAISE NOTICE 'Run the following commands from shell to import actual raster data:';
    RAISE NOTICE '  raster2pgsql -s 4326 -I -C -M ../data/raw/dsm_graz_1m.tif dsm_raster | psql -d sonnenbankerl';
    RAISE NOTICE '  raster2pgsql -s 4326 -I -C -M ../data/raw/dem_graz.tif dem_raster | psql -d sonnenbankerl';
END $$;