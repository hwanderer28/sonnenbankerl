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

# Check if extension already exists
if psql -U postgres -d sonnenbankerl -c "SELECT 1 FROM pg_extension WHERE extname = 'suncalc_postgres';" | grep -q 1; then
    echo "✅ suncalc_postgres extension is already installed"
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

# Compile and install
echo "🔨 Compiling extension..."
# make clean  # Skip clean if it doesn't exist
make

echo "📋 Installing extension..."
make install

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

# List extension files
echo "📁 Extension files:"
ls -la /usr/share/postgresql/14/extension/ | grep suncalc || echo "No suncalc files found"

# Try to create the extension
echo "🔧 Creating extension in database..."
if psql -U postgres -d sonnenbankerl -c "CREATE EXTENSION IF NOT EXISTS suncalc_postgres;"; then
    echo "✅ Extension created successfully!"
else
    echo "❌ Failed to create extension"
    exit 1
fi

# Test the extension
echo "🧪 Testing extension..."
if psql -U postgres -d sonnenbankerl -c "SELECT get_sunrise('2026-06-21'::date, 47.07, 15.44);" | grep -q "2026"; then
    echo "✅ Extension working correctly!"
    echo "Sunrise calculation test passed"
else
    echo "❌ Extension test failed"
    exit 1
fi

# Cleanup
cd /tmp
rm -rf suncalc_postgres

echo ""
echo "🎉 suncalc_postgres extension installation completed!"
echo "You can now run the sun position computations with accurate astronomical data."