-- =============================================================================
-- Database Constraints Migration
-- =============================================================================
-- Adds foreign key, NOT NULL, and CHECK constraints for data integrity
-- Run after 001_initial_schema.sql and 002_create_indexes.sql
-- =============================================================================

-- ============================================================================
-- 1. Add Foreign Key Constraint on bench_horizon
-- ============================================================================
-- Prevents orphaned horizon data when a bench is deleted
ALTER TABLE bench_horizon
ADD CONSTRAINT fk_bench_horizon_bench
FOREIGN KEY (bench_id) REFERENCES benches(id) ON DELETE CASCADE;

COMMENT ON CONSTRAINT fk_bench_horizon_bench ON bench_horizon
IS 'Ensures horizon data is deleted when bench is removed';

-- ============================================================================
-- 2. Add NOT NULL Constraints on exposure table
-- ============================================================================
-- These columns must always have values for valid exposure records
ALTER TABLE exposure
ALTER COLUMN ts_id SET NOT NULL,
ALTER COLUMN bench_id SET NOT NULL;

COMMENT ON COLUMN exposure.ts_id IS 'Timestamp of exposure calculation';
COMMENT ON COLUMN exposure.bench_id IS 'Bench being evaluated';

-- ============================================================================
-- 3. Add CHECK Constraints for valid ranges
-- ============================================================================

-- Sun position azimuth must be 0-360 degrees
ALTER TABLE sun_positions
ADD CONSTRAINT chk_azimuth_range
CHECK (azimuth_deg >= 0 AND azimuth_deg < 360);

-- Sun position elevation must be -90 to 90 degrees
ALTER TABLE sun_positions
ADD CONSTRAINT chk_elevation_range
CHECK (elevation_deg >= -90 AND elevation_deg <= 90);

-- Bench elevation must be non-negative (if set)
ALTER TABLE benches
ADD CONSTRAINT chk_elevation_positive
CHECK (elevation IS NULL OR elevation >= 0);

COMMENT ON CONSTRAINT chk_azimuth_range ON sun_positions
IS 'Validates sun azimuth is within 0-360 degree range';
COMMENT ON CONSTRAINT chk_elevation_range ON sun_positions
IS 'Validates sun elevation is within -90 to 90 degree range';
COMMENT ON CONSTRAINT chk_elevation_positive ON benches
IS 'Ensures elevation is non-negative if provided';

-- ============================================================================
-- 4. Add Missing Indexes
-- ============================================================================

-- Index for JOIN performance on exposure(bench_id)
CREATE INDEX IF NOT EXISTS exposure_bench_id_idx ON exposure(bench_id);

COMMENT ON INDEX exposure_bench_id_idx
IS 'Improves JOIN performance for bench-specific queries';

-- ============================================================================
-- Success Message
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '======================================';
    RAISE NOTICE 'Constraints migration completed!';
    RAISE NOTICE '';
    RAISE NOTICE 'Constraints added:';
    RAISE NOTICE '  - FK: bench_horizon -> benches';
    RAISE NOTICE '  - NOT NULL: exposure(ts_id, bench_id)';
    RAISE NOTICE '  - CHECK: sun_positions azimuth/elevation ranges';
    RAISE NOTICE '  - CHECK: benches elevation >= 0';
    RAISE NOTICE '';
    RAISE NOTICE 'Indexes added:';
    RAISE NOTICE '  - exposure_bench_id_idx';
    RAISE NOTICE '======================================';
END $$;
