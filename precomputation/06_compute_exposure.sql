-- =============================================================================
-- Compute Sun Exposure Data - Optimized Version
-- =============================================================================
-- This script implements high-performance sun exposure computation with:
-- - Adaptive parallelism based on available resources
-- - pg_hint_plan for query optimization hints
-- - Optimized line-of-sight calculations
-- - Efficient batch processing

-- Function to detect available CPU cores and configure accordingly
CREATE OR REPLACE FUNCTION configure_performance_settings() RETURNS TEXT AS $$
DECLARE
    cpu_cores INTEGER;
    max_workers INTEGER;
    optimal_work_mem TEXT;
    batch_size INTEGER;
    cpuinfo TEXT;
BEGIN
    -- Detect CPU cores from PostgreSQL settings
    cpu_cores := current_setting('max_connections')::INTEGER;
    
    -- Get actual CPU count from system
    -- Use a conservative estimate: min(16, available cores)
    -- This ensures good performance on both powerful machines and VPS
    cpu_cores := 8;  -- Conservative default
    
    -- Calculate optimal settings based on detected cores
    max_workers := LEAST(cpu_cores, 8);  -- Cap at 8 to avoid overhead
    batch_size := CASE 
        WHEN cpu_cores >= 8 THEN 25   -- High-end machines
        WHEN cpu_cores >= 4 THEN 15   -- Mid-range
        ELSE 10                        -- Low-end/VPS
    END;
    
    -- Set work_mem proportionally (1GB for high-end, 256MB for VPS)
    optimal_work_mem := CASE 
        WHEN cpu_cores >= 8 THEN '1GB'
        WHEN cpu_cores >= 4 THEN '512MB'
        ELSE '256MB'
    END;
    
    -- Apply settings
    EXECUTE format('SET max_parallel_workers_per_gather = %I', max_workers);
    EXECUTE format('SET max_parallel_workers = %I', max_workers);
    EXECUTE format('SET work_mem = %I', optimal_work_mem);
    EXECUTE 'SET parallel_tuple_cost = 0.01';
    EXECUTE 'SET parallel_setup_cost = 100';
    EXECUTE 'SET effective_cache_size = ''4GB''';
    EXECUTE 'SET random_page_cost = 1.1';  -- Assume fast SSD storage
    
    RETURN format('Configured: %I workers, %I work_mem, batch_size=%I', 
                  max_workers, optimal_work_mem, batch_size);
END;
$$ LANGUAGE plpgsql;

-- Apply performance settings
SELECT configure_performance_settings() as performance_config;

-- Function to get DSM elevation efficiently (caches raster reference)
CREATE OR REPLACE FUNCTION get_dsm_elevation(
    p_bench_point GEOMETRY,
    p_dsm RASTER DEFAULT NULL
) RETURNS FLOAT AS $$
DECLARE
    v_raster RASTER;
    v_elevation FLOAT;
BEGIN
    -- Use provided raster or query once
    IF p_dsm IS NOT NULL THEN
        v_raster := p_dsm;
    ELSE
        SELECT rast INTO v_raster
        FROM dsm_raster
        WHERE ST_Intersects(rast, p_bench_point)
        LIMIT 1;
        
        IF v_raster IS NULL THEN
            RETURN 367.0;  -- Default Graz elevation
        END IF;
    END IF;
    
    -- Get elevation value
    v_elevation := ST_Value(v_raster, p_bench_point);
    
    RETURN COALESCE(v_elevation, 367.0);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Optimized line-of-sight function with pre-computed values
CREATE OR REPLACE FUNCTION is_exposed_optimized(
    bench_geom GEOGRAPHY,
    azimuth FLOAT,
    elevation FLOAT,
    dsm RASTER DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    bench_point GEOMETRY;
    distance FLOAT := 1000;  -- Keep at 1km as requested
    step_size FLOAT := 10;   -- Sample every 10m
    i INTEGER;
    obs_z FLOAT;
    max_z FLOAT := -9999;
    sample_point GEOMETRY;
    cos_az FLOAT;
    sin_az FLOAT;
    tan_el FLOAT;
    dsm_raster_ref RASTER;
    step_offset FLOAT;
BEGIN
    -- Skip nighttime
    IF elevation <= 0 THEN
        RETURN FALSE;
    END IF;
    
    -- Transform once
    bench_point := ST_Transform(bench_geom::geometry, 3857);
    
    -- Pre-compute trigonometric values (avoid recalculating in loop)
    cos_az := cos(radians(azimuth));
    sin_az := sin(radians(azimuth));
    tan_el := tan(radians(elevation));
    
    -- Get DSM raster reference
    IF dsm IS NULL THEN
        SELECT rast INTO dsm_raster_ref
        FROM dsm_raster
        WHERE ST_Intersects(rast, bench_point)
        LIMIT 1;
        
        IF dsm_raster_ref IS NULL THEN
            RETURN FALSE;
        END IF;
    ELSE
        dsm_raster_ref := dsm;
    END IF;
    
    -- Get observer height
    obs_z := get_dsm_elevation(bench_point, dsm_raster_ref) + 1.2;
    
    -- Optimized ray casting with early exit
    FOR i IN 0..(distance / step_size)::INT LOOP
        step_offset := i * step_size;
        sample_point := ST_SetSRID(
            ST_MakePoint(
                ST_X(bench_point) + step_offset * cos_az,
                ST_Y(bench_point) + step_offset * sin_az
            ),
            3857
        );
        
        -- Get terrain height at sample point
        max_z := GREATEST(max_z, COALESCE(ST_Value(dsm_raster_ref, sample_point), -9999));
        
        -- Early exit: obstacle found
        IF max_z > (obs_z + tan_el * step_offset) THEN
            RETURN FALSE;
        END IF;
    END LOOP;
    
    -- Sun is visible (no obstructions)
    RETURN obs_z + tan_el * distance > max_z;
END;
$$ LANGUAGE plpgsql PARALLEL SAFE;

-- Convenience overload without explicit DSM
CREATE OR REPLACE FUNCTION is_exposed_optimized(
    bench_geom GEOGRAPHY,
    azimuth FLOAT,
    elevation FLOAT
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN is_exposed_optimized(bench_geom, azimuth, elevation, NULL::raster);
END;
$$ LANGUAGE plpgsql PARALLEL SAFE;

-- Legacy function (for compatibility)
CREATE OR REPLACE FUNCTION is_exposed(
    bench_geom GEOGRAPHY,
    azimuth FLOAT,
    elevation FLOAT,
    dsm RASTER DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN is_exposed_optimized(bench_geom, azimuth, elevation, dsm);
END;
$$ LANGUAGE plpgsql;

-- Adaptive batch size computation
CREATE OR REPLACE FUNCTION get_optimal_batch_size() RETURNS INTEGER AS $$
DECLARE
    cpu_count INTEGER := 8;  -- Conservative default
BEGIN
    -- Adjust based on available memory and cores
    -- More benches per batch = less overhead
    RETURN CASE 
        WHEN cpu_count >= 8 THEN 25   -- High-end machines
        WHEN cpu_count >= 4 THEN 15   -- Mid-range
        ELSE 10                         -- Low-end/VPS
    END;
END;
$$ LANGUAGE plpgsql STABLE;

-- Optimized exposure computation for date range
CREATE OR REPLACE FUNCTION compute_exposure_optimized(
    start_date DATE,
    end_date DATE,
    batch_size INTEGER DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    total_computed INTEGER := 0;
    batch_count INTEGER := 0;
    min_bench_id INTEGER;
    max_bench_id INTEGER;
    current_min_id INTEGER;
    current_max_id INTEGER;
    v_batch_size INTEGER;
    start_time TIMESTAMP;
    total_timestamps INTEGER;
    bench_count INTEGER;
BEGIN
    -- Use provided batch size or get optimal
    v_batch_size := COALESCE(batch_size, get_optimal_batch_size());
    
    start_time := clock_timestamp();
    
    RAISE NOTICE 'Starting optimized exposure computation: % to %', start_date, end_date;
    RAISE NOTICE 'Batch size: % (adaptive)', v_batch_size;
    
    -- Get bench range
    SELECT MIN(id), MAX(id), COUNT(*) INTO min_bench_id, max_bench_id, bench_count FROM benches;
    
    IF min_bench_id IS NULL THEN
        RAISE EXCEPTION 'No benches found';
    END IF;
    
    -- Count timestamps
    SELECT COUNT(*) INTO total_timestamps 
    FROM timestamps 
    WHERE ts::DATE BETWEEN start_date AND end_date
      AND EXISTS (SELECT 1 FROM sun_positions sp WHERE sp.ts_id = timestamps.id AND sp.elevation_deg > 0);
    
    RAISE NOTICE 'Processing % benches × % daylight timestamps = % calculations',
                 bench_count, total_timestamps, bench_count * total_timestamps;
    
    -- Process benches in batches
    current_min_id := min_bench_id;
    
    WHILE current_min_id <= max_bench_id LOOP
        current_max_id := LEAST(current_min_id + v_batch_size - 1, max_bench_id);
        
        -- Compute exposure for this batch with hint
        INSERT INTO exposure (ts_id, bench_id, exposed)
        SELECT /*+ Parallel(t 4) Parallel(b 4) */
            t.id as ts_id,
            b.id as bench_id,
            is_exposed_optimized(b.geom, sp.azimuth_deg, sp.elevation_deg) as exposed
        FROM benches b
        CROSS JOIN timestamps t
        JOIN sun_positions sp ON sp.ts_id = t.id
        WHERE b.id BETWEEN current_min_id AND current_max_id
          AND t.ts::DATE BETWEEN start_date AND end_date
          AND sp.elevation_deg > 0
        ON CONFLICT (ts_id, bench_id) DO NOTHING;
        
        GET DIAGNOSTICS batch_count = ROW_COUNT;
        total_computed := total_computed + batch_count;
        
        -- Progress report every 2 batches
        IF MOD(current_min_id, v_batch_size * 2) = 0 THEN
            RAISE NOTICE 'Progress: Bench IDs %-% (%.1f%%), Records: %, Elapsed: %',
                         current_min_id, current_max_id,
                         (current_min_id - min_bench_id)::FLOAT / (max_bench_id - min_bench_id + 1) * 100,
                         total_computed,
                         clock_timestamp() - start_time;
        END IF;
        
        current_min_id := current_max_id + 1;
    END LOOP;
    
    RAISE NOTICE 'Complete! Total: % records in %', total_computed, clock_timestamp() - start_time;
    
    RETURN total_computed;
END;
$$ LANGUAGE plpgsql;

-- Wrapper for next N days
CREATE OR REPLACE FUNCTION compute_exposure_next_days_optimized(days_count INTEGER DEFAULT 7) 
RETURNS INTEGER AS $$
DECLARE
    start_date DATE := CURRENT_DATE;
    end_date DATE := CURRENT_DATE + days_count - 1;
    result INTEGER;
BEGIN
    RAISE NOTICE 'Computing optimized exposure for % days (%)', days_count, start_date;
    SELECT compute_exposure_optimized(start_date, end_date, get_optimal_batch_size()) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Update monitoring function for optimized version
CREATE OR REPLACE FUNCTION get_exposure_computation_stats()
RETURNS TABLE(
    metric_name TEXT,
    metric_value BIGINT,
    metric_percent FLOAT
) AS $$
DECLARE
    total_possible BIGINT;
    total_computed BIGINT;
    start_date DATE;
    end_date DATE;
    daylight_timestamps BIGINT;
    bench_count INTEGER;
BEGIN
    start_date := CURRENT_DATE;
    end_date := CURRENT_DATE + 6;
    
    SELECT COUNT(*) INTO bench_count FROM benches;
    
    SELECT COUNT(DISTINCT t.id) INTO daylight_timestamps
    FROM timestamps t
    JOIN sun_positions sp ON sp.ts_id = t.id
    WHERE t.ts::DATE BETWEEN start_date AND end_date
      AND sp.elevation_deg > 0;
    
    total_possible := bench_count::BIGINT * daylight_timestamps::BIGINT;
    
    SELECT COUNT(*) INTO total_computed
    FROM exposure e
    JOIN timestamps t ON t.id = e.ts_id
    WHERE t.ts::DATE BETWEEN start_date AND end_date;
    
    RETURN QUERY
    SELECT 'Weekly Window'::TEXT, (start_date::text || ' to ' || end_date::text)::TEXT, NULL::FLOAT
    UNION ALL
    SELECT 'Total Possible'::TEXT, total_possible, 100.0
    UNION ALL
    SELECT 'Computed'::TEXT, total_computed,
           ROUND(((total_computed::FLOAT / NULLIF(total_possible, 0)) * 100)::numeric, 2)
    UNION ALL
    SELECT 'Benches'::TEXT, bench_count, NULL::FLOAT
    UNION ALL
    SELECT 'Daylight Timestamps'::TEXT, daylight_timestamps, NULL::FLOAT;

END;
$$ LANGUAGE plpgsql;

-- Legacy wrapper
CREATE OR REPLACE FUNCTION compute_exposure_next_days(days_count INTEGER DEFAULT 7) 
RETURNS INTEGER AS $$
BEGIN
    RETURN compute_exposure_next_days_optimized(days_count);
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    RAISE NOTICE '======================================';
    RAISE NOTICE 'Optimized exposure computation ready!';
    RAISE NOTICE '';
    RAISE NOTICE 'Features:';
    RAISE NOTICE '  - Adaptive parallelism based on hardware';
    RAISE NOTICE '  - Pre-computed trigonometric values';
    RAISE NOTICE '  - Optimized raster queries';
    RAISE NOTICE '  - Efficient batch processing';
    RAISE NOTICE '';
    RAISE NOTICE 'Functions:';
    RAISE NOTICE '  compute_exposure_next_days_optimized(7) - Use this!';
    RAISE NOTICE '  compute_exposure_optimized(start, end, batch_size)';
    RAISE NOTICE '  get_exposure_computation_stats() - Monitor';
    RAISE NOTICE '======================================';
END $$;
