-- =============================================================================
-- Generate Timestamps for Computation
-- =============================================================================
-- This script creates the time intervals used for sun exposure calculations.
-- We use 10-minute intervals for a full year of data.

-- Create timestamps table (if not exists from schema migration)
CREATE TABLE IF NOT EXISTS timestamps (
    id SERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL UNIQUE
);

-- Add indexes for time-based queries
CREATE INDEX IF NOT EXISTS idx_timestamps_ts ON timestamps (ts);

-- Function to generate timestamps for a specific year
CREATE OR REPLACE FUNCTION generate_yearly_timestamps(target_year INTEGER DEFAULT 2026) 
RETURNS INTEGER AS $$
DECLARE
    start_time TIMESTAMPTZ;
    end_time TIMESTAMPTZ;
    generated_count INTEGER := 0;
    temp_count INTEGER;
    existing_count INTEGER;
BEGIN
    -- Check if timestamps already exist for this year
    SELECT COUNT(*) INTO existing_count FROM timestamps WHERE EXTRACT(YEAR FROM ts) = target_year;
    
    IF existing_count = 0 THEN
        -- No existing data - create fresh
        -- Set time range for: target year (local timezone: Europe/Vienna for Graz)
        start_time := make_timestamptz(target_year, 1, 1, 0, 0, 'Europe/Vienna');
        end_time := make_timestamptz(target_year, 12, 31, 23, 50, 0, 'Europe/Vienna');
        
        -- Generate 10-minute intervals for: entire year
        INSERT INTO timestamps (ts)
        SELECT generate_series(
            start_time, 
            end_time, 
            '10 minutes'::interval
        );
        
        -- Get count of generated timestamps
        SELECT COUNT(*) INTO generated_count FROM timestamps WHERE EXTRACT(YEAR FROM ts) = target_year;
        
        -- Add generated columns for performance if they don't exist
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'timestamps' AND column_name = 'hour_of_day') THEN
            ALTER TABLE timestamps ADD COLUMN hour_of_day INTEGER GENERATED ALWAYS AS (EXTRACT(HOUR FROM ts)) STORED;
        END IF;
        
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'timestamps' AND column_name = 'day_of_year') THEN
            ALTER TABLE timestamps ADD COLUMN day_of_year INTEGER GENERATED ALWAYS AS (EXTRACT(DOY FROM ts)) STORED;
        END IF;
        
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'timestamps' AND column_name = 'month') THEN
            ALTER TABLE timestamps ADD COLUMN month INTEGER GENERATED ALWAYS AS (EXTRACT(MONTH FROM ts)) STORED;
        END IF;
        
        -- Add additional indexes if they don't exist
        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexrelname = 'idx_timestamps_hour') THEN
            CREATE INDEX idx_timestamps_hour ON timestamps (hour_of_day);
        END IF;
        
        IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexrelname = 'idx_timestamps_month') THEN
            CREATE INDEX idx_timestamps_month ON timestamps (month);
        END IF;
        
        RAISE NOTICE 'Generated % timestamps for %', generated_count, target_year;
    ELSE
        -- Data already exists - report existing count
        SELECT COUNT(*) INTO generated_count FROM timestamps WHERE EXTRACT(YEAR FROM ts) = target_year;
        RAISE NOTICE 'Found % existing timestamps for %', existing_count, target_year;
    END IF;
    
    RETURN generated_count;
END;
$$ LANGUAGE plpgsql;

-- Function to validate timestamp completeness
CREATE OR REPLACE FUNCTION validate_yearly_timestamps(target_year INTEGER DEFAULT 2026) 
RETURNS BOOLEAN AS $$
DECLARE
    expected_count INTEGER := 365 * 144;  -- 144 intervals per day (24 * 6)
    actual_count INTEGER;
    start_date DATE;
    end_date DATE;
    missing_hours TEXT := '';
BEGIN
    -- Count actual timestamps
    SELECT COUNT(*) INTO actual_count FROM timestamps WHERE EXTRACT(YEAR FROM ts) = target_year;
    
    -- Check for gaps in the timeline
    SELECT MIN(ts::DATE), MAX(ts::DATE) INTO start_date, end_date 
    FROM timestamps WHERE EXTRACT(YEAR FROM ts) = target_year;
    
    -- Generate report
    IF actual_count != expected_count THEN
        RAISE WARNING 'Timestamp count mismatch: expected %, got %', expected_count, actual_count;
        RETURN FALSE;
    END IF;
    
    -- Check for gaps (simplified check)
    IF end_date - start_date != 364 THEN  -- Should be full year
        RAISE WARNING 'Date range incomplete: % to %', start_date, end_date;
        RETURN FALSE;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Function to get sun hours statistics
CREATE OR REPLACE FUNCTION get_sun_hour_stats(target_year INTEGER DEFAULT 2026) 
RETURNS TABLE(hour_of_day INTEGER, day_count INTEGER) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        hour_of_day,
        COUNT(DISTINCT ts::DATE) as day_count
    FROM timestamps 
    WHERE EXTRACT(YEAR FROM ts) = target_year
      AND hour_of_day BETWEEN 6 AND 18  -- Typical daylight hours
    GROUP BY hour_of_day
    ORDER BY hour_of_day;
END;
$$ LANGUAGE plpgsql;

-- Generate timestamps for 2026
SELECT generate_yearly_timestamps(2026) as timestamps_generated;

-- Validate generated timestamps
SELECT validate_yearly_timestamps(2026) as validation_passed;

-- Show timestamp statistics
SELECT 
    EXTRACT(YEAR FROM ts) as year,
    COUNT(*) as total_timestamps,
    COUNT(DISTINCT ts::DATE) as days,
    COUNT(DISTINCT hour_of_day) as unique_hours,
    MIN(ts) as first_timestamp,
    MAX(ts) as last_timestamp
FROM timestamps 
WHERE EXTRACT(YEAR FROM ts) = 2026
GROUP BY EXTRACT(YEAR FROM ts);

-- Show sun hours distribution
SELECT * FROM get_sun_hour_stats(2026);

-- Grant permissions to application user
-- Note: Using postgres superuser, no additional grants needed
-- Note: Using postgres superuser, no additional grants needed

DO $$
BEGIN
    RAISE NOTICE 'Timestamp generation completed for 2026';
    RAISE NOTICE 'Total timestamps: % (expected: %)', 
                 (SELECT COUNT(*) FROM timestamps WHERE EXTRACT(YEAR FROM ts) = 2026), 
                 365 * 144;
    RAISE NOTICE 'Timestamp validation: %', (SELECT validate_yearly_timestamps(2026));
END $$;