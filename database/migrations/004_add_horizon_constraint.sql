-- =============================================================================
-- Horizon Table Constraints Migration
-- =============================================================================
-- Adds foreign key constraint on bench_horizon table
-- Run AFTER precomputation/06_compute_exposure.sql (which creates bench_horizon)
-- =============================================================================

-- ============================================================================
-- Add Foreign Key Constraint on bench_horizon
-- ============================================================================
-- Prevents orphaned horizon data when a bench is deleted
ALTER TABLE bench_horizon
ADD CONSTRAINT fk_bench_horizon_bench
FOREIGN KEY (bench_id) REFERENCES benches(id) ON DELETE CASCADE;

COMMENT ON CONSTRAINT fk_bench_horizon_bench ON bench_horizon
IS 'Ensures horizon data is deleted when bench is removed';

-- ============================================================================
-- Success Message
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '======================================';
    RAISE NOTICE 'Horizon constraint migration completed!';
    RAISE NOTICE '';
    RAISE NOTICE 'Constraints added:';
    RAISE NOTICE '  - FK: bench_horizon -> benches (ON DELETE CASCADE)';
    RAISE NOTICE '======================================';
END $$;
