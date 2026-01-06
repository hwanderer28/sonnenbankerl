-- =============================================================================
-- PostgreSQL Extensions Setup
-- =============================================================================
-- This script installs and configures all required PostgreSQL extensions
-- for the Sonnenbankerl sun exposure calculation pipeline.

-- Enable core spatial extensions
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_raster;  -- Required for raster2pgsql and raster type
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Enable TimescaleDB for time-series efficiency
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Enable suncalc_postgres for sun position calculations
-- Note: This requires installation from https://github.com/olithissen/suncalc_postgres
CREATE EXTENSION IF NOT EXISTS suncalc_postgres;

-- Optional: Enable pg_stat_statements for monitoring query performance
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Optional: Enable pg_cron for scheduled maintenance (requires PostgreSQL restart)
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Configure database for optimal raster and parallel processing performance
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET work_mem = '256MB';
ALTER SYSTEM SET maintenance_work_mem = '512MB';
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;
ALTER SYSTEM SET max_parallel_workers = 8;
ALTER SYSTEM SET effective_cache_size = '3GB';
ALTER SYSTEM SET random_page_cost = 1.1;  -- Optimized for SSD storage

-- Reload configuration to apply changes
SELECT pg_reload_conf();

-- Note: Using default 'postgres' superuser for simplicity
-- In production, create a dedicated user with appropriate permissions

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'PostgreSQL extensions installed successfully';
    RAISE NOTICE 'Extensions: postgis, postgis_raster, timescaledb, suncalc_postgres, pg_stat_statements';
    RAISE NOTICE 'Configuration optimized for raster processing and parallel queries';
END $$;