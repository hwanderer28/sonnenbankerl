-- =============================================================================
-- Maintenance and Ongoing Procedures
-- =============================================================================
-- This script contains procedures for ongoing maintenance, incremental updates,
-- and monitoring of the sun exposure calculation system.

-- Function to perform incremental updates for new benches
CREATE OR REPLACE FUNCTION incremental_update_new_benches() RETURNS INTEGER AS $$
DECLARE
    new_bench_count INTEGER := 0;
    updated_count INTEGER := 0;
    current_year INTEGER := EXTRACT(YEAR FROM CURRENT_DATE);
BEGIN
    -- Count new benches (those without exposure data)
    SELECT COUNT(*) INTO new_bench_count
    FROM benches b
    WHERE NOT EXISTS (
        SELECT 1 FROM exposure e WHERE e.bench_id = b.id
    );
    
    IF new_bench_count = 0 THEN
        RAISE NOTICE 'No new benches found for incremental update';
        RETURN 0;
    END IF;
    
    RAISE NOTICE 'Found % new benches, starting incremental update', new_bench_count;
    
    -- Compute exposure for new benches for current year
    INSERT INTO exposure (ts_id, bench_id, exposed, location)
    SELECT 
        t.id as ts_id,
        b.id as bench_id,
        is_exposed(b.geom, sp.azimuth_deg, sp.elevation_deg) as exposed,
        b.geom as location
    FROM benches b
    CROSS JOIN timestamps t
    JOIN sun_positions sp ON sp.ts_id = t.id
    WHERE NOT EXISTS (SELECT 1 FROM exposure e WHERE e.bench_id = b.id)
      AND EXTRACT(YEAR FROM t.ts) = current_year
      AND sp.elevation_deg > 0  -- Skip nighttime
    ON CONFLICT (ts_id, bench_id) DO NOTHING;
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    
    RAISE NOTICE 'Incremental update completed: % records processed for % new benches', 
                 updated_count, new_bench_count;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- Function to recompute future dates (6 months ahead)
CREATE OR REPLACE FUNCTION update_future_exposure() RETURNS INTEGER AS $$
DECLARE
    future_start DATE := CURRENT_DATE;
    future_end DATE := CURRENT_DATE + INTERVAL '6 months';
    updated_count INTEGER := 0;
    year_to_update INTEGER;
BEGIN
    year_to_update := EXTRACT(YEAR FROM future_start);
    
    RAISE NOTICE 'Updating future exposure from % to %', future_start, future_end;
    
    -- Remove existing future data
    DELETE FROM exposure 
    WHERE ts_id IN (
        SELECT t.id FROM timestamps t 
        WHERE t.ts::DATE BETWEEN future_start AND future_end
    );
    
    -- Re-compute future exposure for all benches
    INSERT INTO exposure (ts_id, bench_id, exposed, location)
    SELECT 
        t.id as ts_id,
        b.id as bench_id,
        is_exposed(b.geom, sp.azimuth_deg, sp.elevation_deg) as exposed,
        b.geom as location
    FROM benches b
    CROSS JOIN timestamps t
    JOIN sun_positions sp ON sp.ts_id = t.id
    WHERE t.ts::DATE BETWEEN future_start AND future_end
      AND sp.elevation_deg > 0  -- Skip nighttime
    ON CONFLICT (ts_id, bench_id) DO NOTHING;
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    
    RAISE NOTICE 'Future update completed: % records processed', updated_count;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

-- Function to clean up old data (older than 1 year)
CREATE OR REPLACE FUNCTION cleanup_old_exposure_data() RETURNS BIGINT AS $$
DECLARE
    deleted_count BIGINT;
BEGIN
    -- Delete exposure data older than 1 year
    DELETE FROM exposure 
    WHERE ts_id IN (
        SELECT id FROM timestamps 
        WHERE ts < CURRENT_DATE - INTERVAL '1 year'
    );
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RAISE NOTICE 'Cleaned up % old exposure records (older than 1 year)', deleted_count;
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to validate data integrity
CREATE OR REPLACE FUNCTION validate_exposure_data() RETURNS TABLE(
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
DECLARE
    total_benches INTEGER;
    total_timestamps INTEGER;
    total_exposure_records INTEGER;
    expected_records INTEGER;
    coverage_percent FLOAT;
BEGIN
    -- Get basic counts
    SELECT COUNT(*) INTO total_benches FROM benches;
    SELECT COUNT(*) INTO total_timestamps FROM timestamps WHERE EXTRACT(YEAR FROM ts) = 2026;
    SELECT COUNT(*) INTO total_exposure_records FROM exposure;
    
    expected_records := total_benches * total_timestamps;
    coverage_percent := CASE 
        WHEN expected_records > 0 THEN (total_exposure_records::FLOAT / expected_records) * 100
        ELSE 0
    END;
    
    -- Check bench coverage
    RETURN QUERY
    SELECT 
        'Bench Coverage' as check_name,
        CASE 
            WHEN COUNT(DISTINCT bench_id) = total_benches THEN 'PASS'
            ELSE 'FAIL'
        END as status,
        format('%/% benches have exposure data (%.1f%%)', 
               COUNT(DISTINCT bench_id), total_benches, coverage_percent) as details
    FROM exposure;
    
    -- Check timestamp coverage
    RETURN QUERY
    SELECT 
        'Timestamp Coverage' as check_name,
        CASE 
            WHEN COUNT(DISTINCT ts_id) = total_timestamps THEN 'PASS'
            ELSE 'FAIL'
        END as status,
        format('%/% timestamps have exposure data', 
               COUNT(DISTINCT ts_id), total_timestamps) as details
    FROM exposure;
    
    -- Check data consistency
    RETURN QUERY
    SELECT 
        'Data Consistency' as check_name,
        CASE 
            WHEN COUNT(*) = total_benches THEN 'PASS'
            ELSE 'FAIL'
        END as status,
        format('% benches have complete data', COUNT(*)) as details
    FROM (
        SELECT bench_id 
        FROM exposure 
        WHERE ts_id IN (SELECT id FROM timestamps WHERE EXTRACT(YEAR FROM ts) = 2026)
        GROUP BY bench_id
        HAVING COUNT(*) = total_timestamps
    ) complete_benches;
    
    -- Check for invalid exposure values
    RETURN QUERY
    SELECT 
        'Valid Exposure Values' as check_name,
        CASE 
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL'
        END as status,
        format('% records have NULL exposure values', COUNT(*)) as details
    FROM exposure 
    WHERE exposed IS NULL;
END;
$$ LANGUAGE plpgsql;

-- Function to get system health report
CREATE OR REPLACE FUNCTION get_system_health() RETURNS TABLE(
    metric_name TEXT,
    current_value BIGINT,
    status TEXT,
    recommendation TEXT
) AS $$
BEGIN
    -- Database size
    RETURN QUERY
    SELECT 
        'Database Size (MB)' as metric_name,
        pg_database_size('sonnenbankerl') / 1024 / 1024 as current_value,
        CASE 
            WHEN pg_database_size('sonnenbankerl') < 10 * 1024 * 1024 * 1024 THEN 'OK'  -- Less than 10GB
            ELSE 'WARNING'
        END as status,
        'Consider archiving old data if > 10GB' as recommendation;
    
    -- Exposure table size
    RETURN QUERY
    SELECT 
        'Exposure Table Size (MB)' as metric_name,
        pg_total_relation_size('exposure') / 1024 / 1024 as current_value,
        'OK' as status,
        'Normal size for exposure data' as recommendation;
    
    -- Index health
    RETURN QUERY
    SELECT 
        'Total Indexes' as metric_name,
        COUNT(*) as current_value,
        'OK' as status,
        'Regular index maintenance recommended' as recommendation
    FROM pg_indexes WHERE schemaname = 'public';
    
    -- Recent computation activity
    RETURN QUERY
    SELECT 
        'Records Added Today' as metric_name,
        COUNT(*) as current_value,
        CASE 
            WHEN COUNT(*) > 0 THEN 'ACTIVE'
            ELSE 'IDLE'
        END as status,
        CASE 
            WHEN COUNT(*) = 0 THEN 'Check if scheduled updates are running'
            ELSE 'System is actively computing'
        END as recommendation
    FROM exposure 
    WHERE created_at >= CURRENT_DATE;
END;
$$ LANGUAGE plpgsql;

-- Function to optimize database performance
CREATE OR REPLACE FUNCTION optimize_database_performance() RETURNS VOID AS $$
BEGIN
    -- Update table statistics
    ANALYZE benches;
    ANALYZE timestamps;
    ANALYZE sun_positions;
    ANALYZE exposure;
    
    -- Reindex frequently accessed tables
    REINDEX INDEX CONCURRENTLY idx_benches_geom;
    REINDEX INDEX CONCURRENTLY idx_timestamps_ts;
    REINDEX INDEX CONCURRENTLY idx_sun_positions_ts_id;
    
    -- Enable TimescaleDB compression if not already enabled
    ALTER TABLE exposure SET (timescaledb.compress, timescaledb.compress_segmentby = 'bench_id');
    
    RAISE NOTICE 'Database optimization completed';
    RAISE NOTICE 'Updated statistics, rebuilt indexes, enabled compression';
END;
$$ LANGUAGE plpgsql;

-- Create a scheduled maintenance procedure
CREATE OR REPLACE FUNCTION scheduled_maintenance() RETURNS TABLE(
    task_name TEXT,
    status TEXT,
    records_affected BIGINT
) AS $$
DECLARE
    incremental_result INTEGER;
    future_result INTEGER;
    cleanup_result BIGINT;
BEGIN
    -- Incremental update for new benches
    SELECT incremental_update_new_benches() INTO incremental_result;
    RETURN QUERY
    SELECT 'Incremental Update' as task_name, 
           CASE WHEN incremental_result > 0 THEN 'COMPLETED' ELSE 'NO_NEW_DATA' END as status,
           incremental_result as records_affected;
    
    -- Update future exposure (6 months ahead)
    SELECT update_future_exposure() INTO future_result;
    RETURN QUERY
    SELECT 'Future Update' as task_name, 
           'COMPLETED' as status,
           future_result as records_affected;
    
    -- Clean up old data (run monthly)
    IF EXTRACT(DAY FROM CURRENT_DATE) = 1 THEN
        SELECT cleanup_old_exposure_data() INTO cleanup_result;
        RETURN QUERY
        SELECT 'Cleanup Old Data' as task_name, 
               'COMPLETED' as status,
               cleanup_result as records_affected;
    ELSE
        RETURN QUERY
        SELECT 'Cleanup Old Data' as task_name, 
               'SKIPPED' as status,
               0 as records_affected;
    END IF;
    
    -- Performance optimization (run weekly)
    IF EXTRACT(DOW FROM CURRENT_DATE) = 0 THEN  -- Sunday
        PERFORM optimize_database_performance();
        RETURN QUERY
        SELECT 'Performance Optimization' as task_name, 
               'COMPLETED' as status,
               0 as records_affected;
    ELSE
        RETURN QUERY
        SELECT 'Performance Optimization' as task_name, 
               'SKIPPED' as status,
               0 as records_affected;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions to application user
-- Note: Using postgres superuser, no additional grants needed
-- Note: Using postgres superuser, no additional grants needed
-- Note: Using postgres superuser, no additional grants needed
-- Note: Using postgres superuser, no additional grants needed
-- Note: Using postgres superuser, no additional grants needed
-- Note: Using postgres superuser, no additional grants needed
-- Note: Using postgres superuser, no additional grants needed

-- Display current system status
SELECT 'System Health Report' as report_title;
SELECT * FROM get_system_health();

SELECT 'Data Validation Results' as report_title;
SELECT * FROM validate_exposure_data();

DO $$
BEGIN
    RAISE NOTICE 'Maintenance procedures installed successfully';
    RAISE NOTICE 'Run scheduled_maintenance() for regular updates';
    RAISE NOTICE 'Monitor with get_system_health() and validate_exposure_data()';
END $$;