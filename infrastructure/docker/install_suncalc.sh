#!/bin/bash

# Script to manually install suncalc_postgres extension
# Run this inside the PostgreSQL container if the Docker build didn't work

set -e

echo "=== Manual suncalc_postgres Extension Installation ==="

# Check if we're running as postgres user
if [ "$(whoami)" != "postgres" ]; then
    echo "ERROR: This script must be run as the postgres user"
    echo "Run: docker-compose exec postgres bash"
    echo "Then inside container: ./install_suncalc.sh"
    exit 1
fi

# Check if functions already exist
if psql -U postgres -d sonnenbankerl -c "SELECT 1 FROM pg_proc WHERE proname = 'get_sun_position';" | grep -q 1; then
    echo "✅ suncalc_postgres functions are already installed"
    exit 0
fi

echo "📦 Installing suncalc_postgres extension..."

# Create temporary directory
cd /tmp
if [ -d "suncalc_postgres" ]; then
    rm -rf suncalc_postgres
fi

# Clone the repository
echo "📥 Cloning suncalc_postgres repository..."
git clone https://github.com/olithissen/suncalc_postgres.git
cd suncalc_postgres

# Load the SQL functions directly (no compilation needed)
echo "📋 Loading SQL functions into PostgreSQL..."
psql -U postgres -d sonnenbankerl -f suncalc/suncalc.sql

# Check if files were installed
echo "🔍 Checking installation..."
if [ -f "/usr/share/postgresql/14/extension/suncalc.control" ]; then
    echo "✅ Extension control file found"
else
    echo "⚠️  Control file not found in standard location, trying alternative..."
    # Try to copy manually
    cp -f suncalc.control /usr/share/postgresql/14/extension/ 2>/dev/null || true
    cp -f suncalc--*.sql /usr/share/postgresql/14/extension/ 2>/dev/null || true
fi

# Check if functions were loaded
echo "🔍 Checking if functions were loaded..."
if psql -U postgres -d sonnenbankerl -c "SELECT proname FROM pg_proc WHERE proname LIKE 'get_sun%';" | grep -q get_sun; then
    echo "✅ Functions loaded successfully!"
else
    echo "❌ Functions failed to load"
    exit 1
fi

# Test the functions
echo "🧪 Testing functions..."
if psql -U postgres -d sonnenbankerl -c "SELECT degrees(azimuth), degrees(altitude) FROM get_sun_position(TIMESTAMP '2026-06-21 12:00:00', 47.07, 15.44);" | grep -q "[0-9]"; then
    echo "✅ Functions working correctly!"
    echo "Sun position calculation test passed"
else
    echo "❌ Function test failed"
    exit 1
fi

# Cleanup
cd /tmp
rm -rf suncalc_postgres

echo ""
echo "🎉 suncalc_postgres functions installation completed!"
echo "You can now run the sun position computations with accurate astronomical data."