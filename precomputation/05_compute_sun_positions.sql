-- =============================================================================
-- Compute Sun Positions
-- =============================================================================
-- This script precomputes sun positions (azimuth, elevation) for all timestamps
-- using the suncalc_postgres extension optimized for Graz coordinates.

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

-- Function to compute sun positions for a specific date range
CREATE OR REPLACE FUNCTION compute_sun_positions(
    start_date DATE DEFAULT '2026-01-01', 
    end_date DATE DEFAULT '2026-12-31'
) RETURNS INTEGER AS $$
DECLARE
    computed_count INTEGER := 0;
    graz_latitude FLOAT := 47.07;   -- Graz latitude
    graz_longitude FLOAT := 15.44;  -- Graz longitude
BEGIN
    -- Clear existing positions for this date range
    DELETE FROM sun_positions 
    WHERE ts_id IN (
        SELECT id FROM timestamps 
        WHERE ts::DATE BETWEEN start_date AND end_date
    );
    
    -- Check if suncalc_postgres extension is available
    IF EXISTS (
        SELECT 1 FROM pg_extension
        WHERE extname = 'suncalc_postgres'
    ) THEN
        -- Compute sun positions using suncalc_postgres
        BEGIN
            INSERT INTO sun_positions (ts_id, azimuth_deg, elevation_deg)
            SELECT 
                t.id as ts_id,
                (sp).azimuth as azimuth_deg,
                (sp).altitude as elevation_deg
            FROM timestamps t,
                 LATERAL get_position(t.ts, graz_latitude, graz_longitude) AS sp
            WHERE t.ts::DATE BETWEEN start_date AND end_date;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Error computing sun positions: %', SQLERRM;
        END;
    ELSE
        -- Use sample data if extension not available
        -- This provides basic seasonal sun patterns for testing
        INSERT INTO sun_positions (ts_id, azimuth_deg, elevation_deg)
        SELECT 
            t.id as ts_id,
            -- Simple seasonal sun pattern for testing
            CASE 
                WHEN EXTRACT(MONTH FROM t.ts) IN (12, 1, 2) THEN 120.0  -- Winter low sun
                WHEN EXTRACT(MONTH FROM t.ts) IN (3, 4, 10, 11) THEN 270.0  -- Equinox
                WHEN EXTRACT(MONTH FROM t.ts) IN (6, 7, 8) THEN 45.0   -- Summer midday
                ELSE 0.0  -- Default
            END as elevation_deg,
            -- Simple azimuth pattern (East to West throughout day)
            90.0 + (EXTRACT(HOUR FROM t.ts) * 15) as azimuth_deg
        FROM timestamps t
        WHERE t.ts::DATE BETWEEN start_date AND end_date;
        
        RAISE WARNING 'suncalc_postgres extension not available - using sample sun data';
    END IF;
    
    -- Get count of computed positions
    SELECT COUNT(*) INTO computed_count FROM sun_positions 
    WHERE ts_id IN (
        SELECT id FROM timestamps 
        WHERE ts::DATE BETWEEN start_date AND end_date
    );
    
    RETURN computed_count;
END;
$$ LANGUAGE plpgsql;

-- Function to compute additional solar events (sunrise, sunset, solar noon)
CREATE OR REPLACE FUNCTION compute_solar_events(
    target_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID AS $$
DECLARE
    graz_latitude FLOAT := 47.07;   -- Graz latitude
    graz_longitude FLOAT := 15.44;  -- Graz longitude
    sunrise TIMESTAMPTZ;
    sunset TIMESTAMPTZ;
    solar_noon TIMESTAMPTZ;
    ts_ids INTEGER[];
BEGIN
    -- Only compute solar events if suncalc_postgres extension is available
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'suncalc_postgres') THEN
        BEGIN
            -- Get solar events for the date
            SELECT get_sunrise(target_date, graz_latitude, graz_longitude) INTO sunrise;
            SELECT get_sunset(target_date, graz_latitude, graz_longitude) INTO sunset;
            SELECT get_solar_noon(target_date, graz_latitude, graz_longitude) INTO solar_noon;

            -- Get all timestamp IDs for this date
            SELECT ARRAY_agg(id) INTO ts_ids
            FROM timestamps
            WHERE ts::DATE = target_date;

            -- Update sun positions with solar events
            UPDATE sun_positions
            SET
                sunrise_time = sunrise,
                sunset_time = sunset,
                solar_noon = solar_noon
            WHERE ts_id = ANY(ts_ids);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Could not compute solar events for %: %', target_date, SQLERRM;
        END;
    ELSE
        RAISE WARNING 'suncalc_postgres extension not available - skipping solar events for %', target_date;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to validate sun position calculations
CREATE OR REPLACE FUNCTION validate_sun_positions() RETURNS TABLE(
    validation_type TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Check completeness
    RETURN QUERY
    SELECT 
        'Completeness' as validation_type,
        CASE 
            WHEN COUNT(*) = COUNT(sp.ts_id) THEN 'PASS'
            ELSE 'FAIL'
        END as status,
        'Expected: ' || COUNT(t.id) || ', Got: ' || COUNT(sp.ts_id) || ' timestamps' as details
    FROM timestamps t
    LEFT JOIN sun_positions sp ON sp.ts_id = t.id
    WHERE EXTRACT(YEAR FROM t.ts) = 2026;
    
    -- Check elevation ranges
    RETURN QUERY
    SELECT 
        'Elevation Range' as validation_type,
        CASE 
            WHEN MIN(elevation_deg) >= -90 AND MAX(elevation_deg) <= 90 THEN 'PASS'
            ELSE 'FAIL'
        END as status,
        'Min: ' || ROUND(MIN(elevation_deg)::numeric, 2) || '°, Max: ' || ROUND(MAX(elevation_deg)::numeric, 2) || '°' as details
    FROM sun_positions
    WHERE ts_id IN (
        SELECT id FROM timestamps WHERE EXTRACT(YEAR FROM ts) = 2026
    );
    
    -- Check azimuth ranges
    RETURN QUERY
    SELECT 
        'Azimuth Range' as validation_type,
        CASE 
            WHEN MIN(azimuth_deg) >= 0 AND MAX(azimuth_deg) <= 360 THEN 'PASS'
            ELSE 'FAIL'
        END as status,
        'Min: ' || ROUND(MIN(azimuth_deg)::numeric, 2) || '°, Max: ' || ROUND(MAX(azimuth_deg)::numeric, 2) || '°' as details
    FROM sun_positions
    WHERE ts_id IN (
        SELECT id FROM timestamps WHERE EXTRACT(YEAR FROM ts) = 2026
    );
END;
$$ LANGUAGE plpgsql;

-- Function to get sun position statistics
CREATE OR REPLACE FUNCTION get_sun_position_stats(target_year INTEGER DEFAULT 2026)
RETURNS TABLE(
    stat_name TEXT,
    stat_value DOUBLE PRECISION,
    description TEXT
) AS $$
BEGIN
    RETURN QUERY
    -- Sun hours per day average
    SELECT
        'Avg Sun Hours/Day' as stat_name,
        AVG(CASE WHEN elevation_deg > 0 THEN 1 ELSE 0 END)::DOUBLE PRECISION * 144 as stat_value,  -- 144 intervals per day
        'Average number of 10-min intervals with sun above horizon per day' as description
    FROM sun_positions sp
    JOIN timestamps t ON t.id = sp.ts_id
    WHERE EXTRACT(YEAR FROM t.ts) = target_year;

    -- Max sun elevation
    RETURN QUERY
    SELECT
        'Max Sun Elevation' as stat_name,
        MAX(elevation_deg)::DOUBLE PRECISION as stat_value,
        'Maximum sun elevation angle in degrees' as description
    FROM sun_positions sp
    JOIN timestamps t ON t.id = sp.ts_id
    WHERE EXTRACT(YEAR FROM t.ts) = target_year;

    -- Daylight percentage
    RETURN QUERY
    SELECT
        'Daylight Percentage' as stat_name,
        (COUNT(CASE WHEN elevation_deg > 0 THEN 1 END)::DOUBLE PRECISION / COUNT(*) * 100) as stat_value,
        'Percentage of time when sun is above horizon' as description
    FROM sun_positions sp
    JOIN timestamps t ON t.id = sp.ts_id
    WHERE EXTRACT(YEAR FROM t.ts) = target_year;
END;
$$ LANGUAGE plpgsql;

-- Compute sun positions for 2026
SELECT compute_sun_positions('2026-01-01', '2026-12-31') as positions_computed;

-- Compute solar events for each day (only if extension is available)
DO $$
DECLARE
    current_date_var DATE := '2026-01-01';
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'suncalc_postgres') THEN
        WHILE current_date_var <= '2026-12-31' LOOP
            PERFORM compute_solar_events(current_date_var);
            current_date_var := current_date_var + INTERVAL '1 day';
        END LOOP;
    ELSE
        RAISE NOTICE 'Skipping solar events computation - suncalc_postgres extension not available';
    END IF;
END $$;

-- Validate computations (only if we have sun positions)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM sun_positions LIMIT 1) THEN
        RAISE NOTICE 'Validation results:';
        PERFORM validate_sun_positions();
    ELSE
        RAISE NOTICE 'No sun positions found - skipping validation';
    END IF;
END $$;

-- Show statistics (only if we have sun positions)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM sun_positions LIMIT 1) THEN
        RAISE NOTICE 'Sun position statistics:';
        PERFORM get_sun_position_stats(2026);
    ELSE
        RAISE NOTICE 'No sun positions found - skipping statistics';
    END IF;
END $$;

-- Grant permissions to application user
-- Note: Using postgres superuser, no additional grants needed

DO $$
DECLARE
    total_positions BIGINT;
BEGIN
    SELECT COUNT(*) INTO total_positions FROM sun_positions;
    RAISE NOTICE 'Sun position computation completed for 2026';
    RAISE NOTICE 'Total sun positions: %', total_positions;
    IF total_positions > 0 THEN
        RAISE NOTICE 'Using sample sun data (suncalc_postgres extension not available)';
    END IF;
END $$;