#!/bin/bash
# Database initialization script - idempotent version
# Only runs migrations if the database is fresh (no benches table)

set -e

MIGRATIONS_DIR="/migrations"

echo "======================================"
echo "Checking database state..."
echo "======================================"

# Check if benches table already exists
EXISTS=$(psql -v ON_ERROR_STOP=0 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'benches');" || echo "f")

if [ "$EXISTS" = "t" ]; then
    echo "Database already initialized (benches table exists)"
    echo "Skipping migrations - data will be preserved"
    echo "======================================"
    exit 0
fi

echo "Fresh database detected - running migrations..."

# Install suncalc first
echo "Installing suncalc_postgres..."
if [ -f "/var/lib/suncalc_postgres/suncalc/suncalc.sql" ]; then
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
        -f /var/lib/suncalc_postgres/suncalc/suncalc.sql
    echo "suncalc_postgres installed"
else
    echo "ERROR: suncalc.sql not found"
    exit 1
fi

# Run all migrations in order (sorted numerically)
for migration in $(ls -1 "$MIGRATIONS_DIR"/*.sql | sort -V); do
    if [ -f "$migration" ]; then
        echo "Running: $migration"
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$migration" || {
            echo "ERROR: Migration $migration failed"
            exit 1
        }
    fi
done

echo "======================================"
echo "Migrations complete!"
echo "======================================"
