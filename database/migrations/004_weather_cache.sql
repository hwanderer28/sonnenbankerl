-- =============================================================================
-- Weather Cache Table for Cloud Cover Forecasts
-- =============================================================================
-- Stores forecasted cloud cover data from Open-Meteo API
-- Enables weather-adjusted sun exposure queries with hourly resolution
-- Updated periodically (every 5-10 minutes) by background scheduler

-- ============================================================================
-- Weather Cache Table
-- ============================================================================
-- Stores forecasted cloud cover (%) for geographic regions
-- Resolution: hourly, horizon: 48-168 hours ahead
CREATE TABLE IF NOT EXISTS weather_cache (
    id SERIAL PRIMARY KEY,
    region_id VARCHAR(50) NOT NULL,           -- Region identifier (e.g., "graz", or lat_lon hash)
    latitude DOUBLE PRECISION NOT NULL,        -- Region center latitude
    longitude DOUBLE PRECISION NOT NULL,       -- Region center longitude
    forecast_time TIMESTAMPTZ NOT NULL,       -- Timestamp being forecasted
    cloud_cover_percent INTEGER,              -- Cloud cover percentage (0-100)
    sunshine_duration_seconds INTEGER,        -- Sunshine duration in this hour (seconds)
    is_sunny BOOLEAN GENERATED ALWAYS AS     -- Computed sunny status
        (cloud_cover_percent < 20) STORED,
    fetched_at TIMESTAMPTZ DEFAULT NOW(),     -- When this forecast was fetched
    valid_until TIMESTAMPTZ,                  -- Forecast validity end (if applicable)
    UNIQUE (region_id, forecast_time)
);

COMMENT ON TABLE weather_cache IS 'Cached weather forecasts from Open-Meteo (cloud cover, sunshine duration)';
COMMENT ON COLUMN weather_cache.region_id IS 'Geographic region identifier';
COMMENT ON COLUMN weather_cache.cloud_cover_percent IS 'Total cloud cover percentage (0-100)';
COMMENT ON COLUMN weather_cache.is_sunny IS 'TRUE when cloud_cover_percent < 20% (configurable threshold)';

-- ============================================================================
-- Indexes for Efficient Queries
-- ============================================================================

-- Index for finding weather at a specific time
CREATE INDEX IF NOT EXISTS idx_weather_cache_time
    ON weather_cache (region_id, forecast_time);

-- Index for finding next sunny period
CREATE INDEX IF NOT EXISTS idx_weather_cache_sunny
    ON weather_cache (region_id, forecast_time)
    WHERE is_sunny = TRUE;

-- Index for cache cleanup (old records)
CREATE INDEX IF NOT EXISTS idx_weather_cache_fetched
    ON weather_cache (fetched_at);

-- ============================================================================
-- Weather Cache Cleanup Function
-- ============================================================================
-- Remove forecasts older than specified hours to prevent table bloat
CREATE OR REPLACE FUNCTION cleanup_weather_cache(retention_hours INTEGER DEFAULT 168) RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM weather_cache
    WHERE fetched_at < NOW() - (retention_hours || ' hours')::INTERVAL;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RAISE NOTICE 'Cleaned up % old weather cache entries', deleted_count;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_weather_cache IS 'Delete weather forecasts older than retention_hours (default 7 days)';

-- ============================================================================
-- Get Weather-Adjusted Exposure Status Function
-- ============================================================================
-- Determines if a bench is effectively sunny at a given time
-- Combines precomputed clear-sky exposure with weather forecast
CREATE OR REPLACE FUNCTION get_weather_adjusted_exposure(
    p_bench_id INTEGER,
    p_forecast_time TIMESTAMPTZ
) RETURNS BOOLEAN AS $$
DECLARE
    v_lat DOUBLE PRECISION;
    v_lon DOUBLE PRECISION;
    v_region_id VARCHAR(50);
    v_clear_sky_exposed BOOLEAN;
    v_cloud_cover INTEGER;
    v_result BOOLEAN;
BEGIN
    -- Get bench location
    SELECT ST_Y(geom::geometry), ST_X(geom::geometry)
    INTO v_lat, v_lon
    FROM benches WHERE id = p_bench_id;

    IF v_lat IS NULL THEN
        RETURN NULL;
    END IF;

    -- Create region identifier (rounded to ~50km grid for cache efficiency)
    v_region_id := 'graz_' || floor(v_lat::numeric * 10)::text || '_' || floor(v_lon::numeric * 10)::text;

    -- Get clear-sky exposure from precomputed data
    SELECT e.exposed INTO v_clear_sky_exposed
    FROM exposure e
    JOIN timestamps t ON t.id = e.ts_id
    WHERE e.bench_id = p_bench_id
      AND t.ts = date_trunc('hour', p_forecast_time)::timestamptz
    LIMIT 1;

    -- If not in daylight, immediately return FALSE
    IF v_clear_sky_exposed = FALSE THEN
        RETURN FALSE;
    END IF;

    -- Get cloud cover for this time
    SELECT cloud_cover_percent INTO v_cloud_cover
    FROM weather_cache
    WHERE region_id = v_region_id
      AND forecast_time = date_trunc('hour', p_forecast_time)::timestamptz
    LIMIT 1;

    -- If no weather data, assume sunny (optimistic default)
    IF v_cloud_cover IS NULL THEN
        RETURN TRUE;
    END IF;

    -- Apply weather threshold (cloud_cover < 20% = sunny)
    v_result := v_cloud_cover < 20;

    RAISE DEBUG 'Weather-adjusted exposure for bench % at %: clear_sky=%, cloud_cover=%%, result=%',
                p_bench_id, p_forecast_time, v_clear_sky_exposed, v_cloud_cover, v_result;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_weather_adjusted_exposure IS
    'Returns TRUE if bench is effectively sunny (clear sky AND cloud cover < 20%%)';

-- ============================================================================
-- Get Next Sunny Period Function
-- ============================================================================
-- Finds the next time when a bench will be sunny (considering weather forecasts)
CREATE OR REPLACE FUNCTION get_next_sunny_period(
    p_bench_id INTEGER,
    p_from_time TIMESTAMPTZ DEFAULT NOW(),
    p_max_hours INTEGER DEFAULT 48
) RETURNS TIMESTAMPTZ AS $$
DECLARE
    v_next_sunny TIMESTAMPTZ;
    v_lat DOUBLE PRECISION;
    v_lon DOUBLE PRECISION;
    v_region_id VARCHAR(50);
BEGIN
    -- Get bench location
    SELECT ST_Y(geom::geometry), ST_X(geom::geometry)
    INTO v_lat, v_lon
    FROM benches WHERE id = p_bench_id;

    IF v_lat IS NULL THEN
        RETURN NULL;
    END IF;

    -- Create region identifier
    v_region_id := 'graz_' || floor(v_lat::numeric * 10)::text || '_' || floor(v_lon::numeric * 10)::text;

    -- Find next sunny hour considering both clear-sky and weather
    SELECT MIN(t.ts) INTO v_next_sunny
    FROM timestamps t
    WHERE t.ts > p_from_time
      AND t.ts < p_from_time + (p_max_hours || ' hours')::INTERVAL
      AND get_weather_adjusted_exposure(p_bench_id, t.ts) = TRUE;

    RETURN v_next_sunny;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_next_sunny_period IS
    'Returns next timestamp when bench will be sunny (considering weather forecasts), NULL if none within max_hours';

-- ============================================================================
-- Success Message
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '======================================';
    RAISE NOTICE 'Weather cache schema initialized!';
    RAISE NOTICE 'Tables: weather_cache';
    RAISE NOTICE 'Functions:';
    RAISE NOTICE '  - cleanup_weather_cache(retention_hours)';
    RAISE NOTICE '  - get_weather_adjusted_exposure(bench_id, time)';
    RAISE NOTICE '  - get_next_sunny_period(bench_id, from_time, max_hours)';
    RAISE NOTICE '======================================';
END $$;
