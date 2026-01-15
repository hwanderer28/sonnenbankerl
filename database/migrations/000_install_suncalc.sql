-- =============================================================================
-- Install suncalc_postgres Extension
-- =============================================================================
-- This script installs the suncalc_postgres functions into the sonnenbankerl database
-- Run automatically at container initialization (after database is created)
-- =============================================================================

-- Install suncalc_postgres functions from the cloned repository
\i /var/lib/suncalc_postgres/suncalc/suncalc.sql

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_sun_position') THEN
        RAISE NOTICE 'suncalc_postgres functions installed successfully!';
    ELSE
        RAISE WARNING 'suncalc_postgres functions may not have installed correctly';
    END IF;
END $$;
