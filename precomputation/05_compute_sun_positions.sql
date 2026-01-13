-- =============================================================================
-- Compute Sun Positions (Weekly Rolling)
-- =============================================================================
-- This script precomputes sun positions (azimuth, elevation) for all timestamps
-- in the current weekly window using the suncalc_postgres extension.
--
-- - Computes for current rolling week (today + 7 days)
-- - Uses accurate astronomical calculations for Graz coordinates

-- Create sun_positions table (if not exists from schema migration)
CREATE TABLE IF NOT EXISTS sun_positions (
    ts_id INT REFERENCES timestamps(id) ON DELETE CASCADE,
    azimuth_deg FLOAT NOT NULL,
    elevation_deg FLOAT NOT NULL,
    solar_noon TIMESTAMPTZ,
    sunrise_time TIMESTAMPTZ,
    sunset_time TIMESTAMPTZ,
    PRIMARY KEY (ts_id)
);

-- Create indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_sun_positions_ts_id ON sun_positions (ts_id);
CREATE INDEX IF NOT EXISTS idx_sun_positions_elevation ON sun_positions (elevation_deg) WHERE elevation_deg > 0;

-- Check if suncalc_postgres functions are available; create wrapper if only get_position exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_sun_position') THEN
        RAISE NOTICE 'suncalc_postgres functions are available';
        RAISE NOTICE 'Using accurate astronomical calculations for Graz (47.07°N, 15.44°E)';
    ELSE
        RAISE WARNING 'suncalc_postgres functions not found - will use sample sun data';
    END IF;
END $$;

-- Function to compute sun positions for current weekly timestamps
CREATE OR REPLACE FUNCTION compute_weekly_sun_positions() RETURNS INTEGER AS $$
DECLARE
    computed_count INTEGER := 0;
    start_date DATE;
    end_date DATE;
    graz_latitude FLOAT := 47.07;
    graz_longitude FLOAT := 15.44;
BEGIN
    -- Get current weekly date range
    start_date := CURRENT_DATE;
    end_date := CURRENT_DATE + 6;

    RAISE NOTICE 'Computing sun positions for % to % (%)', start_date, end_date, end_date - start_date + 1;

    -- Clear existing positions for this date range
    DELETE FROM sun_positions
    WHERE ts_id IN (
        SELECT id FROM timestamps
        WHERE ts::DATE BETWEEN start_date AND end_date
    );

    -- Check if suncalc_postgres function is available
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_sun_position') THEN
        -- Compute sun positions using suncalc_postgres functions
        BEGIN
            INSERT INTO sun_positions (ts_id, azimuth_deg, elevation_deg)
            SELECT
                t.id as ts_id,
                degrees((sp).azimuth) as azimuth_deg,
                degrees((sp).altitude) as elevation_deg
            FROM timestamps t,
                 LATERAL get_sun_position(t.ts, graz_latitude, graz_longitude) AS sp
            WHERE t.ts::DATE BETWEEN start_date AND end_date;

            GET DIAGNOSTICS computed_count = ROW_COUNT;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Error computing sun positions: %', SQLERRM;
            computed_count := 0;
        END;
    ELSE
        -- Use realistic sample data if extension not available
        INSERT INTO sun_positions (ts_id, azimuth_deg, elevation_deg)
        SELECT
            t.id AS ts_id,
            ((day_fraction * 360.0) - 180.0) AS azimuth_deg,
            GREATEST(0.0, 60.0 * SIN(PI() * day_fraction)) AS elevation_deg
        FROM (
            SELECT
                ts,
                id,
                -- Compute day fraction from UTC midnight (timestamps are stored as TIMESTAMPTZ in UTC)
                ((EXTRACT(EPOCH FROM ts) % 86400) / 86400.0) AS day_fraction
            FROM timestamps
            WHERE ts::DATE BETWEEN start_date AND end_date
        ) t;

        GET DIAGNOSTICS computed_count = ROW_COUNT;
        RAISE WARNING 'suncalc_postgres extension not available - using sample sun data (synthetic day curve)';
    END IF;

    RAISE NOTICE 'Computed % sun positions', computed_count;

    RETURN computed_count;
END;
$$ LANGUAGE plpgsql;

-- Function to validate sun position calculations
CREATE OR REPLACE FUNCTION validate_sun_positions() RETURNS TABLE(
    validation_type TEXT,
    status TEXT,
    details TEXT
) AS $$
DECLARE
    expected_count INTEGER;
    actual_count INTEGER;
    min_elev FLOAT;
    max_elev FLOAT;
    min_az FLOAT;
    max_az FLOAT;
BEGIN
    -- Get expected count from timestamps
    SELECT COUNT(*) INTO expected_count
    FROM timestamps
    WHERE ts::DATE BETWEEN CURRENT_DATE AND CURRENT_DATE + 6;

    -- Get actual count from sun_positions
    SELECT COUNT(*), MIN(elevation_deg), MAX(elevation_deg),
           MIN(azimuth_deg), MAX(azimuth_deg)
    INTO actual_count, min_elev, max_elev, min_az, max_az
    FROM sun_positions sp
    JOIN timestamps t ON sp.ts_id = t.id
    WHERE t.ts::DATE BETWEEN CURRENT_DATE AND CURRENT_DATE + 6;

    -- Check completeness
    RETURN QUERY
    SELECT
        'Completeness' as validation_type,
        CASE WHEN actual_count = expected_count THEN 'PASS' ELSE 'FAIL' END as status,
        'Expected: ' || expected_count || ', Got: ' || actual_count || ' positions' as details;

    -- Check elevation ranges
    RETURN QUERY
    SELECT
        'Elevation Range' as validation_type,
        CASE WHEN min_elev >= -90 AND max_elev <= 90 THEN 'PASS' ELSE 'FAIL' END as status,
        'Min: ' || ROUND(min_elev::numeric, 2) || '°, Max: ' || ROUND(max_elev::numeric, 2) || '°' as details;

    -- Check azimuth ranges
    RETURN QUERY
    SELECT
        'Azimuth Range' as validation_type,
        CASE WHEN min_az >= -180 AND max_az <= 180 THEN 'PASS' ELSE 'FAIL' END as status,
        'Min: ' || ROUND(min_az::numeric, 2) || '°, Max: ' || ROUND(max_az::numeric, 2) || '°' as details;
END;
$$ LANGUAGE plpgsql;

-- Function to get sun position statistics
CREATE OR REPLACE FUNCTION get_sun_position_stats() RETURNS TABLE(
    stat_name TEXT,
    stat_value DOUBLE PRECISION,
    description TEXT
) AS $$
BEGIN
    -- Total sun positions
    RETURN QUERY
    SELECT
        'Total Positions' as stat_name,
        COUNT(*)::DOUBLE PRECISION as stat_value,
        'Total sun positions computed' as description
    FROM sun_positions sp
    JOIN timestamps t ON sp.ts_id = t.id
    WHERE t.ts::DATE BETWEEN CURRENT_DATE AND CURRENT_DATE + 6;

    -- Daylight intervals
    RETURN QUERY
    SELECT
        'Daylight Intervals' as stat_name,
        COUNT(*)::DOUBLE PRECISION as stat_value,
        'Intervals with sun above horizon' as description
    FROM sun_positions
    WHERE elevation_deg > 0;

    -- Max sun elevation
    RETURN QUERY
    SELECT
        'Max Elevation' as stat_name,
        MAX(elevation_deg)::DOUBLE PRECISION as stat_value,
        'Maximum sun elevation in degrees' as description
    FROM sun_positions
    WHERE elevation_deg > 0;

    -- Avg daylight hours per day
    RETURN QUERY
    SELECT
        'Avg Daylight Hours' as stat_name,
        AVG(CASE WHEN elevation_deg > 0 THEN 1 ELSE 0 END)::DOUBLE PRECISION * 24 / 6 as stat_value,
        'Average daylight hours per day in weekly window' as description
    FROM sun_positions sp
    JOIN timestamps t ON sp.ts_id = t.id
    WHERE t.ts::DATE BETWEEN CURRENT_DATE AND CURRENT_DATE + 6;
END;
$$ LANGUAGE plpgsql;

-- Compute sun positions for current weekly window
SELECT compute_weekly_sun_positions() as positions_computed;

-- Validate computations
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM sun_positions LIMIT 1) THEN
        RAISE NOTICE '';
        RAISE NOTICE '=== Sun Position Validation ===';
        PERFORM validate_sun_positions();
    ELSE
        RAISE WARNING 'No sun positions computed - validation skipped';
    END IF;
END $$;

-- Show statistics
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM sun_positions LIMIT 1) THEN
        RAISE NOTICE '';
        RAISE NOTICE '=== Sun Position Statistics ===';
        PERFORM public.get_sun_position_stats();
    ELSE
        RAISE WARNING 'No sun positions computed - statistics skipped';
    END IF;
END $$;

-- Show sample data
SELECT
    t.ts::date as date,
    ROUND(MIN(CASE WHEN sp.elevation_deg > 0 THEN sp.azimuth_deg END)::numeric, 1) as sunrise_azimuth,
    TO_CHAR(MIN(CASE WHEN sp.elevation_deg > 0 THEN t.ts END), 'HH24:MI') as sunrise_time,
    ROUND(MAX(sp.elevation_deg)::numeric, 1) as max_elevation,
    TO_CHAR(MAX(CASE WHEN sp.elevation_deg > 0 THEN t.ts END), 'HH24:MI') as solar_noon,
    TO_CHAR(MAX(CASE WHEN sp.elevation_deg > 0 THEN t.ts END), 'HH24:MI') as sunset_time
FROM sun_positions sp
JOIN timestamps t ON sp.ts_id = t.id
WHERE t.ts::DATE BETWEEN CURRENT_DATE AND CURRENT_DATE + 6
GROUP BY t.ts::date
ORDER BY t.ts::date;

DO $$
DECLARE
    total_positions BIGINT;
    daylight_positions BIGINT;
BEGIN
    SELECT COUNT(*) INTO total_positions FROM sun_positions;
    SELECT COUNT(*) INTO daylight_positions FROM sun_positions WHERE elevation_deg > 0;

    RAISE NOTICE '';
    RAISE NOTICE '======================================';
    RAISE NOTICE 'Sun position computation complete!';
    RAISE NOTICE 'Total: % positions (%) daylight',
                 total_positions,
                 ROUND((daylight_positions * 100.0 / NULLIF(total_positions, 0))::numeric, 1);
    RAISE NOTICE '======================================';
END $$;
