#!/bin/bash
# =============================================================================
# suncalc_postgres Installation Script
# =============================================================================
# This script automatically installs suncalc_postgres SQL functions when the
# PostgreSQL container is first initialized.

set -e

echo "==============================================================================="
echo "Installing suncalc_postgres functions..."
echo "==============================================================================="

# Check if suncalc SQL file exists
if [ ! -f "/tmp/suncalc_postgres/suncalc/suncalc.sql" ]; then
    echo "ERROR: suncalc.sql file not found at /tmp/suncalc_postgres/suncalc/suncalc.sql"
    echo "The suncalc_postgres repository may not have been cloned during build."
    exit 1
fi

# Install suncalc functions into the database
echo "Loading suncalc functions into database: $POSTGRES_DB"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -f /tmp/suncalc_postgres/suncalc/suncalc.sql

# Verify installation by checking for key functions
echo "Verifying installation..."
FUNCTION_COUNT=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -tAc "SELECT COUNT(*) FROM pg_proc WHERE proname LIKE 'get_%position';" || echo "0")

if [ "$FUNCTION_COUNT" -gt "0" ]; then
    echo "✅ SUCCESS: suncalc_postgres functions installed successfully!"
    echo "   Found $FUNCTION_COUNT sun position functions"
    
    # Test the main function
    echo "Testing sun position calculation..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
        -c "SELECT 'Test: ' || 'Azimuth=' || degrees(azimuth)::TEXT || '°, Altitude=' || degrees(altitude)::TEXT || '°' 
            FROM get_position(TIMESTAMP '2026-06-21 12:00:00', 47.07, 15.44);" \
        || echo "Warning: Function test failed"
else
    echo "⚠️  WARNING: suncalc_postgres functions may not have been installed correctly"
    exit 1
fi

echo "==============================================================================="
echo "suncalc_postgres installation complete!"
echo "==============================================================================="
