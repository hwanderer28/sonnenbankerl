-- =============================================================================
-- Generate Weekly Timestamps (Rolling 7 Days)
-- =============================================================================
-- This script creates 10-minute interval timestamps for the next 7 days
-- from today's date. Designed for weekly rolling computation.
--
-- - Timestamps stored in local time (Europe/Vienna)
-- - 10-minute intervals (144 per day)
-- - 1008 timestamps maximum (7 days × 144 intervals)
-- - Rolling window: always covers today + next 6 days

-- Create timestamps table (if not exists from schema migration)
CREATE TABLE IF NOT EXISTS timestamps (
    id SERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL UNIQUE
);

-- Add indexes for time-based queries
CREATE INDEX IF NOT EXISTS idx_timestamps_ts ON timestamps (ts);

-- Function to generate timestamps for rolling week (today + 7 days)
-- Uses local time (Europe/Vienna) for user-friendly display
CREATE OR REPLACE FUNCTION generate_weekly_timestamps() RETURNS INTEGER AS $$
DECLARE
    local_today DATE := (timezone('Europe/Vienna', now()))::date;
    start_time TIMESTAMPTZ;
    end_time TIMESTAMPTZ;
    generated_count INTEGER := 0;
    existing_count INTEGER;
BEGIN
    -- Calculate time range: local today 00:00 to +7 days 00:00
    start_time := (local_today::timestamp AT TIME ZONE 'Europe/Vienna');
    end_time := ((local_today + 7)::timestamp AT TIME ZONE 'Europe/Vienna');

    -- Check existing timestamps in this range
    existing_count := COUNT(*) FROM timestamps
    WHERE ts >= start_time AND ts < end_time;

    IF existing_count > 0 THEN
        RAISE NOTICE 'Found % existing timestamps in weekly range (%)', existing_count, CURRENT_DATE;
        RAISE NOTICE 'Clearing old timestamps to regenerate with fresh data...';
        DELETE FROM timestamps WHERE ts >= start_time AND ts < end_time;
    END IF;

    -- Generate 10-minute intervals for 7 days
    INSERT INTO timestamps (ts)
    SELECT generate_series(
        start_time,
        end_time - INTERVAL '10 minutes',  -- Exclude the endpoint
        '10 minutes'::interval
    );

    GET DIAGNOSTICS generated_count = ROW_COUNT;

    RAISE NOTICE 'Generated % timestamps for % to %',
                 generated_count,
                 start_time::date,
                 (end_time - INTERVAL '1 day')::date;

    RETURN generated_count;
END;
$$ LANGUAGE plpgsql;

-- Function to validate timestamp completeness
CREATE OR REPLACE FUNCTION validate_weekly_timestamps() RETURNS BOOLEAN AS $$
DECLARE
    expected_count INTEGER := 7 * 144;  -- 7 days × 144 intervals per day
    actual_count INTEGER;
    start_date DATE;
    end_date DATE;
    local_today DATE;
BEGIN
    -- Count actual timestamps
    local_today := (timezone('Europe/Vienna', now()))::date;

    SELECT COUNT(*) INTO actual_count FROM timestamps
    WHERE ts >= (local_today::timestamp AT TIME ZONE 'Europe/Vienna')
      AND ts < ((local_today + 7)::timestamp AT TIME ZONE 'Europe/Vienna');

    -- Get date range
    SELECT MIN(ts)::DATE, MAX(ts)::DATE INTO start_date, end_date
    FROM timestamps
    WHERE ts >= (local_today::timestamp AT TIME ZONE 'Europe/Vienna')
      AND ts < ((local_today + 7)::timestamp AT TIME ZONE 'Europe/Vienna');

    -- Validate
    IF actual_count != expected_count THEN
        RAISE WARNING 'Timestamp count mismatch: expected %, got %', expected_count, actual_count;
        RETURN FALSE;
    END IF;

    IF end_date - start_date != 6 THEN  -- Should cover 7 days (start to start+6)
        RAISE WARNING 'Date range incomplete: % to %', start_date, end_date;
        RETURN FALSE;
    END IF;

    RAISE NOTICE 'Timestamp validation passed: % timestamps from % to %',
                 actual_count, start_date, end_date;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to get timestamp statistics
CREATE OR REPLACE FUNCTION get_timestamp_stats() RETURNS TABLE(
    metric_name TEXT,
    metric_value TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 'Total Timestamps' as metric_name, COUNT(*)::text FROM timestamps
    UNION ALL
    SELECT 'Date Range', MIN(ts)::date || ' to ' || MAX(ts)::date
    FROM timestamps
    UNION ALL
    SELECT 'Days Covered', (MAX(ts)::date - MIN(ts)::date + 1)::text
    FROM timestamps
    UNION ALL
    SELECT 'Timezone', 'Europe/Vienna (+01:00/+02:00)'
    FROM timestamps
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Generate weekly timestamps
SELECT generate_weekly_timestamps() as timestamps_generated;

-- Validate generated timestamps
SELECT validate_weekly_timestamps() as validation_passed;

-- Show timestamp statistics
SELECT * FROM get_timestamp_stats();

-- Display sample timestamps
SELECT
    ts::date as date,
    COUNT(*) as intervals,
    MIN(ts)::time as first_time,
    MAX(ts)::time as last_time
FROM timestamps
GROUP BY ts::date
ORDER BY ts::date;

DO $$
BEGIN
    RAISE NOTICE '======================================';
    RAISE NOTICE 'Weekly timestamp generation complete!';
    RAISE NOTICE 'Generated for: % to %',
                 (CURRENT_DATE),
                 (CURRENT_DATE + 6);
    RAISE NOTICE 'Total intervals: % (expected: 1008)',
                 (SELECT COUNT(*) FROM timestamps);
    RAISE NOTICE 'Next run will regenerate fresh timestamps';
    RAISE NOTICE '======================================';
END $$;
