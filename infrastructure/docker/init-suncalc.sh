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
    -tAc "SELECT COUNT(*) FROM pg_proc WHERE proname = 'get_sun_position';" || echo "0")

if [ "$FUNCTION_COUNT" -gt "0" ]; then
    echo "✅ SUCCESS: suncalc_postgres functions installed successfully!"
    echo "   Found get_sun_position function"

    # Test the main function with proper record handling
    echo "Testing sun position calculation..."
    TEST_RESULT=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
        -tAc "SELECT degrees((sp).azimuth) as az, degrees((sp).altitude) as alt
              FROM get_sun_position(TIMESTAMP '2026-06-21 12:00:00+00', 47.07, 15.44) AS sp;" 2>&1) || true

    if echo "$TEST_RESULT" | grep -q "^[0-9]"; then
        echo "   Test result: Azimuth=$(echo "$TEST_RESULT" | cut -d'|' -f1)°, Altitude=$(echo "$TEST_RESULT" | cut -d'|' -f2)°"
        echo "   Function working correctly!"
    else
        echo "⚠️  WARNING: Function test returned unexpected result: $TEST_RESULT"
    fi
else
    echo "⚠️  WARNING: suncalc_postgres get_sun_position function not found"
    exit 1
fi

echo "==============================================================================="
echo "suncalc_postgres installation complete!"
echo "==============================================================================="
