# Backend Architecture

This document outlines the comprehensive backend infrastructure for the Sonnenbankerl application, designed to be hosted on a VPS.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter Mobile App                     │
│                    (iOS/Android Clients)                    │
└──────────────────────┬──────────────────────────────────────┘
                       │ HTTPS/REST API
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                     YOUR VPS SERVER                         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │            API Gateway / Load Balancer                │  │
│  │                    (Traefik)                          │  │
│  │              - SSL/TLS termination                    │  │
│  │              - Rate limiting                          │  │
│  │              - Request routing                        │  │
│  └─────────────┬──────────────────────┬──────────────────┘  │
│                │                      │                     │
│  ┌─────────────▼──────────┐  ┌────────▼──────────────────┐  │
│  │   REST API Service     │  │  Static File Service      │  │
│  │   (Node.js/Python)     │  │  (Optional: API docs)     │  │
│  │                        │  │                           │  │
│  │ - Bench queries        │  └───────────────────────────┘  │
│  │ - Weather integration  │                                 │
│  │ - Exposure calculations│                                 │
│  └─────────────┬──────────┘                                 │
│                │                                            │
│  ┌─────────────▼──────────────────────────────────────────┐ │
│  │         PostgreSQL Database                            │ │
│  │         + PostGIS + TimescaleDB                        │ │
│  │                                                        │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │ │
│  │  │   benches    │  │  timestamps  │  │ sun_positions│  │ │
│  │  │  (PostGIS)   │  └──────────────┘  └──────────────┘  │ │
│  │  └──────────────┘                                      │ │
│  │  ┌──────────────────────────────────────────────────┐  │ │
│  │  │  exposure (TimescaleDB hypertable)               │  │ │
│  │  │  - Precomputed sun/shade data                    │  │ │
│  │  │  - 10-min intervals for 2026                     │  │ │
│  │  └──────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │      Precomputation Service (Python)                  │  │
│  │      - Runs periodically (cron)                       │  │
│  │      - Batch processes sun exposure                   │  │
│  │      - Updates exposure table                         │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │      Monitoring & Logging                             │  │
│  │      - Application logs                               │  │
│  │      - Database performance monitoring                │  │
│  │      - Error tracking                                 │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                       │
                       │ External API calls
                       │
         ┌─────────────▼────────────┐
         │  GeoSphere Austria API   │
         │  (Weather data)          │
         └──────────────────────────┘
```

## Component Breakdown

### 1. Database Layer

**Technology Stack:**
- PostgreSQL 14+
- PostGIS (spatial data extension)
- TimescaleDB (time-series optimization)
- suncalc_postgres (sun position calculations)

**Database Schema:**

```sql
-- Bench locations with spatial data
CREATE TABLE benches (
    id SERIAL PRIMARY KEY,
    osm_id BIGINT UNIQUE,
    geom GEOGRAPHY(POINT, 4326),
    elevation FLOAT,
    name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX benches_geom_idx ON benches USING GIST(geom);

-- Timestamp intervals (10-minute resolution)
CREATE TABLE timestamps (
    id SERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL UNIQUE
);
CREATE INDEX timestamps_ts_idx ON timestamps(ts);

-- Precomputed sun positions for Graz
CREATE TABLE sun_positions (
    ts_id INT NOT NULL REFERENCES timestamps(id) ON DELETE CASCADE,
    azimuth_deg FLOAT NOT NULL CHECK (azimuth_deg >= 0 AND azimuth_deg < 360),
    elevation_deg FLOAT NOT NULL CHECK (elevation_deg >= -90 AND elevation_deg <= 90),
    PRIMARY KEY (ts_id)
);

-- Sun exposure data (TimescaleDB hypertable)
CREATE TABLE exposure (
    ts_id INT NOT NULL REFERENCES timestamps(id) ON DELETE CASCADE,
    bench_id INT NOT NULL REFERENCES benches(id) ON DELETE CASCADE,
    exposed BOOLEAN NOT NULL,
    PRIMARY KEY (ts_id, bench_id)
);
SELECT create_hypertable('exposure', 'ts_id', chunk_time_interval => INTERVAL '1 month');
CREATE INDEX exposure_bench_ts_idx ON exposure (bench_id, ts_id DESC);
CREATE INDEX exposure_bench_id_idx ON exposure (bench_id);

-- Precomputed horizon profiles for efficient LOS checks
CREATE TABLE bench_horizon (
    bench_id INT NOT NULL REFERENCES benches(id) ON DELETE CASCADE,
    azimuth_deg INTEGER NOT NULL,
    max_angle_deg DOUBLE PRECISION NOT NULL,
    PRIMARY KEY (bench_id, azimuth_deg)
);

-- Digital Surface Model and Digital Elevation Model
-- (Loaded via raster2pgsql)
-- dsm_raster: 1m resolution surface model
-- dem_raster: ground elevation model
```

**Storage Estimates:**
- Initial dataset (200 benches, 1 year): 50-500 MB (compressed)
- Full dataset (1000 benches, 1 year): 1-2 GB
- DSM/DEM rasters for Graz: 500 MB - 2 GB

**Performance Optimizations:**
- TimescaleDB compression for exposure table
- Spatial indexes on geography columns
- Partitioning by time (automatic with TimescaleDB)
- Connection pooling (asyncpg with statement caching)
- Batch database queries (eliminates N+1 pattern)
- Adaptive line-of-sight step sizes (~40% faster)

### 2. REST API Service

**Technology Options:**

#### Option A: Python (FastAPI) - Recommended
```python
# Advantages:
# - Excellent PostgreSQL support (psycopg2/asyncpg)
# - Fast async performance
# - Built-in OpenAPI documentation
# - Same language as precomputation scripts
# - Type hints and validation (Pydantic)

from fastapi import FastAPI, Query
from typing import List, Optional
import asyncpg

app = FastAPI()

@app.get("/api/benches")
async def get_benches(
    lat: float,
    lon: float,
    radius: float = Query(1000, description="Radius in meters")
):
    # Returns benches within radius with current sun/shade status
    pass
```

#### Option B: Node.js (Express)
```javascript
// Advantages:
// - Lightweight and fast
// - Large ecosystem
// - Good real-time capabilities (if needed)

const express = require('express');
const { Pool } = require('pg');
const app = express();
```

**API Endpoints:**

```
GET  /api/benches
     Query params:
       - lat: float (required)
       - lon: float (required)
       - radius: float (optional, default: 1000m)
     Returns: List of benches with current sun/shade status
     
     Response example:
     {
       "benches": [
         {
           "id": 1,
           "osm_id": 123456789,
           "location": {"lat": 47.07, "lon": 15.44},
           "distance": 245,
           "current_status": "sunny",
           "sun_until": "2025-12-11T16:53:00Z",
           "remaining_minutes": 194
         }
       ]
     }

GET  /api/benches/{id}
     Returns: Detailed bench information
     
     Response example:
     {
       "id": 1,
       "osm_id": 123456789,
       "location": {"lat": 47.07, "lon": 15.44},
       "elevation": 356.2,
       "current_status": "sunny",
       "sun_until": "2025-12-11T16:53:00Z",
       "remaining_minutes": 194,
       "weather": {
         "cloud_cover": 20,
         "conditions": "partly cloudy"
       }
     }

GET  /api/benches/{id}/exposure
     Query params:
       - from: ISO timestamp (optional, default: now)
       - to: ISO timestamp (optional, default: now + 24h)
     Returns: Sun exposure timeline for visualization
     
     Response example:
     {
       "bench_id": 1,
       "intervals": [
         {"timestamp": "2025-12-11T14:00:00Z", "exposed": true},
         {"timestamp": "2025-12-11T14:10:00Z", "exposed": true},
         {"timestamp": "2025-12-11T14:20:00Z", "exposed": false}
       ]
     }

GET  /api/health
     Returns: API health status
     
     Response example:
     {
       "status": "healthy",
       "database": "connected",
       "timestamp": "2025-12-11T14:30:00Z"
     }
```

**Weather Integration:**

The system integrates with GeoSphere Austria to determine current sunshine conditions. This acts as a "weather gate" - if no sunshine is reported, all benches are marked as shady regardless of geometric exposure.

**Endpoint:** `GET /api/weather/current`

**Response:**
```json
{
  "is_sunny": true,
  "sunshine_seconds": 480,
  "station": "Graz Universitaet",
  "cached": false,
  "timestamp": "2025-12-11T14:30:00Z"
}
```

**Caching Strategy:**
- 10-minute cache TTL to reduce API calls
- Stale cache fallback on API errors (continues serving last known value)
- Can force refresh with `?refresh=true` query parameter

**Station Configuration:**
| Station ID | Name |
|------------|------|
| 11290 | Graz Universitaet (default) |
| 11240 | Graz-Thalerhof-Flughafen |
| 11238 | Graz/Strassgang |
| 11291 | Graz Universitaet/Heinrichstrasse |

**Configuration:**
```python
# From backend/app/config.py
GEOSPHERE_API_URL = "https://dataset.api.hub.geosphere.at"
GEOSPHERE_STATION_ID = "11290"  # Default station
WEATHER_CACHE_TTL = 600  # 10 minutes in seconds
```

**Note:** The weather gate is **skipped by default** (`skip_weather_check=True`) for local development and testing. In production, configure `skip_weather_check=False` to enable the weather-based sunshine gate.

### 3. Reverse Proxy / Load Balancer

**Using Traefik (Existing VPS Setup)**

Traefik provides dynamic routing, automatic HTTPS via Let's Encrypt, and excellent Docker integration.

**Docker Compose Configuration with Traefik Labels:**

```yaml
services:
  api:
    build: ./backend
    networks:
      - traefik  # Your existing Traefik network
      - internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.sonnenbankerl-api.rule=Host(`api.sonnenbankerl.com`)"
      - "traefik.http.routers.sonnenbankerl-api.entrypoints=websecure"
      - "traefik.http.routers.sonnenbankerl-api.tls.certresolver=letsencrypt"
      - "traefik.http.services.sonnenbankerl-api.loadbalancer.server.port=8000"
      
      # Rate limiting middleware
      - "traefik.http.middlewares.api-ratelimit.ratelimit.average=100"
      - "traefik.http.middlewares.api-ratelimit.ratelimit.burst=50"
      - "traefik.http.routers.sonnenbankerl-api.middlewares=api-ratelimit"
      
      # CORS headers
      - "traefik.http.middlewares.api-cors.headers.accesscontrolallowmethods=GET,OPTIONS,POST"
      - "traefik.http.middlewares.api-cors.headers.accesscontrolalloworigin=*"
      - "traefik.http.middlewares.api-cors.headers.accesscontrolallowheaders=Content-Type,Authorization"

networks:
  traefik:
    external: true  # Your existing Traefik network
  internal:
    internal: true
```

**Key Traefik Features:**
- **Dynamic Configuration:** Routes defined via Docker labels
- **Automatic SSL:** Let's Encrypt certificates auto-renewed
- **Rate Limiting:** Built-in middleware for API protection
- **Load Balancing:** Automatic distribution across replicas
- **Health Checks:** Monitors service availability

### 4. Precomputation Service

The system uses a **database-first approach** with pure SQL functions for sun exposure computation. All processing happens inside PostgreSQL using PL/pgSQL functions.

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `generate_weekly_timestamps()` | Creates 7 days of 10-minute intervals (1,008 timestamps) |
| `compute_weekly_sun_positions()` | Calculates sun azimuth/elevation using suncalc_postgres |
| `compute_all_bench_horizons()` | Precomputes horizon profiles (2° bins to 8km) |
| `compute_exposure_next_days_optimized(n)` | Batch computes exposure for N days |

**Running the Pipeline:**

```bash
# Full weekly recomputation (15-30 minutes)
./compute_next_week.sh

# Or manually:
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/03_import_benches.sql
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/04_generate_timestamps.sql
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /precomputation/05_compute_sun_positions.sql
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_all_bench_horizons();"
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "SELECT compute_exposure_next_days_optimized(7);"
```

**Note:** Automated weekly cron job is not yet configured. Run manually as needed.

### 5. Deployment Options

#### Option 1: Docker Compose (Recommended)

**docker-compose.yml:**
```yaml
version: '3.8'

services:
  postgres:
    image: timescale/timescaledb-ha:pg14-latest
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: sonnenbankerl
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "127.0.0.1:5432:5432"
    restart: unless-stopped
    
  api:
    build: ./backend
    depends_on:
      - postgres
    environment:
      DATABASE_URL: postgres://postgres:${DB_PASSWORD}@postgres/sonnenbankerl
      GEOSPHERE_API_KEY: ${GEOSPHERE_API_KEY}
    networks:
      - traefik
      - internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.sonnenbankerl-api.rule=Host(`api.sonnenbankerl.com`)"
      - "traefik.http.routers.sonnenbankerl-api.entrypoints=websecure"
      - "traefik.http.routers.sonnenbankerl-api.tls.certresolver=letsencrypt"
      - "traefik.http.services.sonnenbankerl-api.loadbalancer.server.port=8000"
    restart: unless-stopped

networks:
  traefik:
    external: true  # Use your existing Traefik network
  internal:
    internal: true

volumes:
  pgdata:
```

#### Option 2: Systemd Services

Manual installation with systemd service management.

**api.service:**
```ini
[Unit]
Description=Sonnenbankerl API Service
After=network.target postgresql.service

[Service]
Type=simple
User=sonnenbankerl
WorkingDirectory=/opt/sonnenbankerl/api
Environment="DATABASE_URL=postgres://user:pass@localhost/sonnenbankerl"
ExecStart=/usr/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

## VPS Requirements

### Minimum Specifications
- **CPU**: 4 cores (for parallel precomputation)
- **RAM**: 8 GB (PostgreSQL + PostGIS + API service)
- **Storage**: 50 GB SSD
- **Bandwidth**: 1-2 TB/month

### Recommended Specifications
- **CPU**: 6-8 cores
- **RAM**: 16 GB
- **Storage**: 100 GB SSD
- **Bandwidth**: 2-5 TB/month
- **Operating System**: Ubuntu 22.04 LTS or Debian 12

### Popular VPS Providers
- **Hetzner**: Excellent price/performance ratio in Europe
- **DigitalOcean**: Easy setup, good documentation
- **Linode**: Reliable, good support
- **Vultr**: Competitive pricing

## Security Considerations

### Database Security
- PostgreSQL listens only on localhost (127.0.0.1)
- Strong passwords with environment variables
- Regular automated backups
- Encrypted backups storage

### API Security
- Rate limiting per IP address (100 requests/minute)
- CORS configuration for Flutter app domains
- Input validation and sanitization
- Optional API key authentication
- SQL injection prevention (parameterized queries)

### Server Security
```bash
# Firewall configuration (ufw)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Install fail2ban for SSH protection
sudo apt install fail2ban

# Automatic security updates
sudo apt install unattended-upgrades
```

### SSL/TLS
- Automatic certificate management with Traefik
- Or use Certbot with nginx
- HTTPS only (redirect HTTP to HTTPS)
- HSTS headers enabled

## Monitoring & Maintenance

### Logging Strategy
```bash
# Application logs location
/var/log/sonnenbankerl/
  ├── api.log           # API access and errors
  ├── precompute.log    # Precomputation job logs
  └── cron.log          # Scheduled task logs

# Traefik logs
/var/log/traefik/
  └── access.log        # Access logs with rate limiting info

# PostgreSQL logs
/var/log/postgresql/
  └── postgresql-14-main.log
```

### Database Monitoring
```sql
-- Enable pg_stat_statements for query analysis
CREATE EXTENSION pg_stat_statements;

-- Monitor slow queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
WHERE mean_exec_time > 100  -- queries slower than 100ms
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Check table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### Backup Strategy
```bash
# Daily PostgreSQL backup script
#!/bin/bash
# /opt/sonnenbankerl/backup.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/postgresql"
DB_NAME="sonnenbankerl"

# Create backup
pg_dump -U postgres -d $DB_NAME | gzip > "$BACKUP_DIR/db_$DATE.sql.gz"

# Keep only last 30 days
find $BACKUP_DIR -name "db_*.sql.gz" -mtime +30 -delete

# Upload to remote storage (optional)
# rclone copy "$BACKUP_DIR/db_$DATE.sql.gz" remote:backups/
```

**Crontab entry:**
```bash
# Daily backup at 2 AM
0 2 * * * /opt/sonnenbankerl/backup.sh >> /var/log/sonnenbankerl/backup.log 2>&1
```

### Health Checks
```bash
# Simple uptime monitoring script
#!/bin/bash
# /opt/sonnenbankerl/healthcheck.sh

API_URL="https://api.sonnenbankerl.com/api/health"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" $API_URL)

if [ $RESPONSE -ne 200 ]; then
    echo "API health check failed: HTTP $RESPONSE"
    # Send alert (email, SMS, etc.)
    # systemctl restart api.service
fi
```

**Crontab entry:**
```bash
# Check every 5 minutes
*/5 * * * * /opt/sonnenbankerl/healthcheck.sh
```

### Optional: Prometheus + Grafana
For advanced monitoring and visualization:
- API request rates and latency
- Database connection pool stats
- System resources (CPU, RAM, disk)
- Custom alerts

## Scaling Considerations

### Current Architecture (Single VPS)
Suitable for:
- Up to 10,000 active users
- ~100 requests/second
- Single region (Austria/Central Europe)

### Future Scaling Options

**Horizontal Scaling:**
- Multiple API instances behind load balancer
- Read replicas for PostgreSQL
- Redis cache layer for frequent queries

**Vertical Scaling:**
- Upgrade VPS resources as needed
- TimescaleDB handles large datasets efficiently

**CDN Integration:**
- Cache static bench data at edge locations
- Reduce API server load

**Database Optimization:**
- Materialized views for common queries
- Additional spatial indexes
- Query result caching (Redis)

## Development Workflow

### Local Development Setup
```bash
# Clone repository
git clone <repository-url>
cd sonnenbankerl

# Start services with Docker Compose
docker-compose -f docker-compose.dev.yml up

# Run migrations
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f migrations/001_initial.sql

# Import test data
python scripts/import_test_benches.py
```

### Deployment Process
```bash
# 1. SSH into VPS
ssh user@your-vps-ip

# 2. Pull latest changes
cd /opt/sonnenbankerl
git pull origin main

# 3. Rebuild and restart services
docker-compose build
docker-compose up -d

# 4. Run migrations if needed
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f migrations/002_new_feature.sql

# 5. Check logs
docker-compose logs -f api
```

## Cost Estimation

### Monthly VPS Costs (Hetzner Example)
- **CX31** (4 cores, 8GB RAM, 80GB SSD): ~7 EUR/month
- **CX41** (8 cores, 16GB RAM, 160GB SSD): ~14 EUR/month

### Additional Costs
- Domain name: ~10-15 EUR/year
- GeoSphere API: Free for non-commercial use
- Backup storage (optional): 2-5 EUR/month

**Total estimated monthly cost: 7-20 EUR**

## Next Steps

1. **Choose VPS provider and provision server**
2. **Register domain name** (e.g., api.sonnenbankerl.com)
3. **Set up PostgreSQL with extensions** (PostGIS, TimescaleDB)
4. **Import OSM bench data and DSM/DEM rasters**
5. **Develop REST API service** (FastAPI recommended)
6. **Configure Traefik labels** (for automatic HTTPS routing)
7. **Run initial precomputation** (may take several days)
8. **Set up monitoring and backups**
9. **Deploy and test API**
10. **Integrate with Flutter mobile app**

## References

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [PostGIS Documentation](https://postgis.net/docs/)
- [TimescaleDB Documentation](https://docs.timescale.com/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [GeoSphere Austria API](https://dataset.api.hub.geosphere.at/)
