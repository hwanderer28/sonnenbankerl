-- =============================================================================
-- Compute Sun Exposure Data
-- =============================================================================
-- This script implements the core sun exposure computation using pure PostgreSQL.
-- It combines sun positions, line-of-sight calculations, and DSM data to determine
-- whether each bench is exposed to sunlight at each timestamp.

-- Enable optimal parallel processing settings
SET max_parallel_workers_per_gather = 4;
SET work_mem = '256MB';
SET parallel_setup_cost = 1000;
SET parallel_tuple_cost = 0.1;

-- Create or replace the line-of-sight function
CREATE OR REPLACE FUNCTION is_exposed(
    bench_geom GEOGRAPHY, 
    azimuth FLOAT, 
    elevation FLOAT, 
    dsm RASTER DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    bench_point GEOMETRY := bench_geom::geometry;
    distance FLOAT := 1000;  -- Max ray length (m)
    step_size FLOAT := 10;  -- Sample every 10m
    i INT;
    obs_z FLOAT;
    max_z FLOAT := -9999;  -- Initialize to very low value
    sample_point GEOMETRY;
    sample_x FLOAT;
    sample_y FLOAT;
    dsm_raster_ref RASTER;
BEGIN
    -- Skip nighttime checks (elevation < 0)
    IF elevation <= 0 THEN
        RETURN FALSE;
    END IF;
    
    -- Get DSM raster reference if not provided
    IF dsm IS NULL THEN
        SELECT rast INTO dsm_raster_ref
        FROM dsm_raster 
        WHERE ST_Intersects(rast, bench_point) 
        LIMIT 1;
        
        IF dsm_raster_ref IS NULL THEN
            RAISE WARNING 'No DSM data available for bench at %', ST_AsText(bench_point);
            RETURN FALSE;
        END IF;
    ELSE
        dsm_raster_ref := dsm;
    END IF;
    
    -- Get observer height (ground elevation + 1.2m for sitting height)
    obs_z := COALESCE(
        ST_Value(dsm_raster_ref, bench_point),
        ST_Value((SELECT rast FROM dem_raster WHERE ST_Intersects(rast, bench_point) LIMIT 1), bench_point),
        340  -- Average Graz elevation as fallback
    ) + 1.2;
    
    -- Sample DSM along ray to sun direction
    FOR i IN 0..(distance / step_size)::INT LOOP
        sample_x := ST_X(bench_point) + i * step_size * cos(radians(azimuth));
        sample_y := ST_Y(bench_point) + i * step_size * sin(radians(azimuth));
        sample_point := ST_MakePoint(sample_x, sample_y);
        
        -- Get DSM height at sample point
        max_z := GREATEST(max_z, COALESCE(ST_Value(dsm_raster_ref, sample_point), -9999));
        
        -- Early exit if we already found an obstacle
        IF max_z > (obs_z + tan(radians(elevation)) * i * step_size) THEN
            RETURN FALSE;
        END IF;
    END LOOP;
    
    -- Check if direct line to sun is blocked
    RETURN obs_z + tan(radians(elevation)) * distance > max_z;
END;
$$ LANGUAGE plpgsql PARALLEL SAFE;

-- Create index for DSM raster queries (if not exists)
CREATE INDEX IF NOT EXISTS idx_dsm_raster_st_convexhull ON dsm_raster USING GIST (ST_ConvexHull(rast));

-- Function to compute exposure for a single bench (for debugging)
CREATE OR REPLACE FUNCTION compute_single_bench_exposure(
    bench_id INTEGER,
    target_date DATE DEFAULT '2026-06-21'  -- Summer solstice for testing
) RETURNS INTEGER AS $$
DECLARE
    computed_count INTEGER := 0;
BEGIN
    -- Compute exposure for all timestamps on target date
    INSERT INTO exposure (ts_id, bench_id, exposed, location)
    SELECT 
        t.id as ts_id,
        bench_id,
        is_exposed(b.geom, sp.azimuth_deg, sp.elevation_deg) as exposed,
        b.geom as location
    FROM benches b
    CROSS JOIN timestamps t
    JOIN sun_positions sp ON sp.ts_id = t.id
    WHERE b.id = bench_id
      AND t.ts::DATE = target_date
      AND sp.elevation_deg > 0  -- Skip nighttime
    ON CONFLICT (ts_id, bench_id) DO NOTHING;
    
    GET DIAGNOSTICS computed_count = ROW_COUNT;
    RETURN computed_count;
END;
$$ LANGUAGE plpgsql;

-- Main computation function for all benches and timestamps
CREATE OR REPLACE FUNCTION compute_all_exposure_data(
    start_year INTEGER DEFAULT 2026,
    end_year INTEGER DEFAULT 2026,
    batch_size INTEGER DEFAULT 100
) RETURNS INTEGER AS $$
DECLARE
    total_computed INTEGER := 0;
    batch_count INTEGER := 0;
    min_bench_id INTEGER;
    max_bench_id INTEGER;
    current_min_id INTEGER;
    current_max_id INTEGER;
    start_time TIMESTAMP := clock_timestamp();
BEGIN
    RAISE NOTICE 'Starting exposure computation for years % to %', start_year, end_year;
    
    -- Get bench ID range
    SELECT MIN(id), MAX(id) INTO min_bench_id, max_bench_id FROM benches;
    
    IF min_bench_id IS NULL THEN
        RAISE EXCEPTION 'No benches found in database';
    END IF;
    
    RAISE NOTICE 'Processing % benches (ID range: % to %)', 
                 (SELECT COUNT(*) FROM benches), min_bench_id, max_bench_id;
    
    -- Process benches in batches to manage memory usage
    current_min_id := min_bench_id;
    
    WHILE current_min_id <= max_bench_id LOOP
        current_max_id := current_min_id + batch_size - 1;
        
        -- Compute exposure for this batch
        INSERT INTO exposure (ts_id, bench_id, exposed, location)
        SELECT 
            t.id as ts_id,
            b.id as bench_id,
            is_exposed(b.geom, sp.azimuth_deg, sp.elevation_deg) as exposed,
            b.geom as location
        FROM benches b
        CROSS JOIN timestamps t
        JOIN sun_positions sp ON sp.ts_id = t.id
        WHERE b.id BETWEEN current_min_id AND current_max_id
          AND EXTRACT(YEAR FROM t.ts) BETWEEN start_year AND end_year
          AND sp.elevation_deg > 0  -- Skip nighttime for performance
        ON CONFLICT (ts_id, bench_id) DO NOTHING;
        
        GET DIAGNOSTICS batch_count = ROW_COUNT;
        total_computed := total_computed + batch_count;
        
        -- Report progress
        IF current_max_id % (batch_size * 5) = 0 OR current_max_id >= max_bench_id THEN
            RAISE NOTICE 'Progress: Bench IDs %-%, Records: %, Time: %',
                         current_min_id, LEAST(current_max_id, max_bench_id), 
                         total_computed, clock_timestamp() - start_time;
        END IF;
        
        current_min_id := current_max_id + 1;
        
        -- Give PostgreSQL a moment to breathe
        PERFORM pg_sleep(0.1);
    END LOOP;
    
    RETURN total_computed;
END;
$$ LANGUAGE plpgsql;

-- Function to monitor computation progress
CREATE OR REPLACE FUNCTION get_exposure_computation_stats(target_year INTEGER DEFAULT 2026) 
RETURNS TABLE(
    metric_name TEXT,
    metric_value BIGINT,
    metric_percent FLOAT
) AS $$
DECLARE
    total_possible BIGINT;
    total_computed BIGINT;
BEGIN
    -- Calculate total possible records
    SELECT COUNT(*) * COUNT(DISTINCT t.id) INTO total_possible
    FROM benches
    CROSS JOIN timestamps t
    WHERE EXTRACT(YEAR FROM t.ts) = target_year;
    
    -- Get actual computed records
    SELECT COUNT(*) INTO total_computed
    FROM exposure e
    JOIN timestamps t ON t.id = e.ts_id
    WHERE EXTRACT(YEAR FROM t.ts) = target_year;
    
    -- Return statistics
    RETURN QUERY
    SELECT 'Total Possible Records' as metric_name, total_possible as metric_value, 100.0 as metric_percent
    UNION ALL
    SELECT 'Total Computed Records' as metric_name, total_computed as metric_value, 
           ROUND((total_computed::FLOAT / total_possible) * 100, 2) as metric_percent
    UNION ALL
    SELECT 'Benches Processed' as metric_name, 
           COUNT(DISTINCT e.bench_id) as metric_value,
           ROUND((COUNT(DISTINCT e.bench_id)::FLOAT / (SELECT COUNT(*) FROM benches)) * 100, 2) as metric_percent
    FROM exposure e
    JOIN timestamps t ON t.id = e.ts_id
    WHERE EXTRACT(YEAR FROM t.ts) = target_year;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions to application user
GRANT EXECUTE ON FUNCTION is_exposed TO sonnenbankerl_user;
GRANT EXECUTE ON FUNCTION compute_single_bench_exposure TO sonnenbankerl_user;
GRANT EXECUTE ON FUNCTION compute_all_exposure_data TO sonnenbankerl_user;
GRANT EXECUTE ON FUNCTION get_exposure_computation_stats TO sonnenbankerl_user;
GRANT INSERT ON exposure TO sonnenbankerl_user;

-- Enable TimescaleDB compression for storage efficiency
ALTER TABLE exposure SET (timescaledb.compress, timescaledb.compress_segmentby = 'bench_id');

-- Start the main computation (this will take hours to days)
-- For testing with a single bench first:
-- SELECT compute_single_bench_exposure(1, '2026-06-21');

-- For full computation (uncomment when ready):
-- SELECT compute_all_exposure_data(2026, 2026, 100) as total_records_computed;

DO $$
BEGIN
    RAISE NOTICE 'Exposure computation setup completed';
    RAISE NOTICE 'To start full computation, run: SELECT compute_all_exposure_data(2026, 2026, 100);';
    RAISE NOTICE 'To test single bench, run: SELECT compute_single_bench_exposure(1, ''2026-06-21'');';
    RAISE NOTICE 'Monitor progress with: SELECT * FROM get_exposure_computation_stats(2026);';
END $$;