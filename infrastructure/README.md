# Infrastructure & Deployment

Infrastructure-as-code and deployment configurations for the Sonnenbankerl application.

## Structure

```
infrastructure/
├── docker/
│   ├── docker-compose.yml          # Stack with Postgres, API, frontend (Traefik labels)
│   └── Dockerfile.postgres         # Postgres with PostGIS/TimescaleDB
├── systemd/
│   ├── api.service                 # API service unit
│   └── precompute.timer            # Scheduled precomputation
└── scripts/
    ├── backup.sh                   # Database backup script
    ├── healthcheck.sh              # Health monitoring
    └── deploy.sh                   # Deployment automation
```

## Local Development

### Docker Compose Setup

```bash
cd infrastructure/docker

# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

**Services included:**
- PostgreSQL 14 with PostGIS, TimescaleDB, and raster support
- FastAPI backend

**Note:** The PostgreSQL container is built from a custom Dockerfile that extends TimescaleDB with PostGIS support.

### Access Points

- API: http://localhost:8000
- API Docs: http://localhost:8000/docs
- Database: localhost:5432

## Production Deployment

### Prerequisites

**VPS with Traefik already configured:**
- Traefik v2 or v3 running
- Docker network (e.g., `traefik` or `proxy`)
- Entry points configured (typically `web` and `websecure`)
- Certificate resolver set up for Let's Encrypt

**VPS Requirements:**

**Minimum:**
- 4 CPU cores
- 8 GB RAM
- 50 GB SSD
- Ubuntu 22.04 LTS

**Recommended:**
- 6-8 CPU cores
- 16 GB RAM
- 100 GB SSD

### Traefik Integration

The production deployment integrates with your existing Traefik setup using Docker labels.

**Key configuration needed:**
1. **Traefik network name** - The external network Traefik monitors
2. **Domain name** - e.g., `sonnenbankerl-api.ideanexus.cloud`
3. **Certificate resolver** - Your Let's Encrypt resolver name
4. **Entry points** - Typically `websecure` for HTTPS

### Deployment Steps

#### 1. Configure Environment

```bash
# On VPS
cd /opt/sonnenbankerl

# Copy and edit environment file
cp .env.example .env
nano .env
```

**Required environment variables:**
```bash
# Database
DATABASE_URL=postgresql://postgres:STRONG_PASSWORD@postgres:5432/sonnenbankerl
POSTGRES_PASSWORD=STRONG_PASSWORD

# API
API_PORT=8000
ALLOWED_ORIGINS=https://sonnenbankerl.ideanexus.cloud
GEOSPHERE_API_KEY=your_api_key

# Traefik
API_DOMAIN=sonnenbankerl-api.ideanexus.cloud
FRONTEND_DOMAIN=sonnenbankerl.ideanexus.cloud
TRAEFIK_NETWORK=traefik_proxy  # Your Traefik network name
CERT_RESOLVER=letsencrypt  # Your certificate resolver name
```

#### 2. Update docker-compose.yml

Edit `infrastructure/docker/docker-compose.yml` for your Traefik setup:

- Ensure the external network name matches your Traefik network (`traefik_proxy` by default).
- API router host: `sonnenbankerl-api.ideanexus.cloud`, entrypoint `websecure`, resolver `letsencrypt`.
- Frontend router host: `sonnenbankerl.ideanexus.cloud`, entrypoint `websecure`, resolver `letsencrypt`.
- Both API and frontend services should join `traefik_proxy`.

#### 3. Deploy with Docker Compose

```bash
cd infrastructure/docker

docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f api
```

#### 4. Run Database Migrations

```bash
# Access postgres container
docker-compose exec postgres psql -U postgres -d sonnenbankerl

# Or run migrations from host
psql postgresql://postgres:PASSWORD@localhost:5432/sonnenbankerl -f ../../database/migrations/001_initial_schema.sql
```

#### 5. Verify Deployment

```bash
# Check Traefik has picked up the service
# Visit your Traefik dashboard or check logs

# Test API health endpoint
curl https://sonnenbankerl-api.ideanexus.cloud/api/health

# Check SSL certificate
curl -vI https://sonnenbankerl-api.ideanexus.cloud
```

### Alternative: Systemd Services

For non-Docker deployment with systemd service management.

```bash
# Install services
sudo cp systemd/*.service /etc/systemd/system/
sudo cp systemd/*.timer /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable api.service
sudo systemctl start api.service

# Check status
sudo systemctl status api.service
```

**Note:** With systemd deployment, you'll still need Traefik configured to route to your API service (typically running on localhost:8000).

## Traefik Configuration Examples

### Basic Traefik Labels (Docker Compose)

```yaml
services:
  api:
    labels:
      # Enable Traefik for this service
      - "traefik.enable=true"
      
      # HTTP Router
      - "traefik.http.routers.sonnenbankerl-api.rule=Host(`sonnenbankerl-api.ideanexus.cloud`)"
      - "traefik.http.routers.sonnenbankerl-api.entrypoints=websecure"
      - "traefik.http.routers.sonnenbankerl-api.tls.certresolver=letsencrypt"
      
      # Service configuration
      - "traefik.http.services.sonnenbankerl-api.loadbalancer.server.port=8000"
```

### Frontend Labels (Docker Compose)

```yaml
services:
  frontend:
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik_proxy"
      - "traefik.http.routers.sonnenbankerl-frontend.rule=Host(`sonnenbankerl.ideanexus.cloud`)"
      - "traefik.http.routers.sonnenbankerl-frontend.entrypoints=websecure"
      - "traefik.http.routers.sonnenbankerl-frontend.tls.certresolver=letsencrypt"
      - "traefik.http.services.sonnenbankerl-frontend.loadbalancer.server.port=80"
```

### With Rate Limiting

```yaml
labels:
  # ... basic labels above ...
  
  # Rate limiting middleware
  - "traefik.http.middlewares.api-ratelimit.ratelimit.average=100"
  - "traefik.http.middlewares.api-ratelimit.ratelimit.burst=50"
  - "traefik.http.middlewares.api-ratelimit.ratelimit.period=1m"
  
  # Apply middleware
  - "traefik.http.routers.sonnenbankerl-api.middlewares=api-ratelimit"
```

### With CORS Headers

```yaml
labels:
  # ... basic labels above ...
  
  # CORS middleware
  - "traefik.http.middlewares.api-cors.headers.accesscontrolallowmethods=GET,OPTIONS,POST"
  - "traefik.http.middlewares.api-cors.headers.accesscontrolalloworigin=https://sonnenbankerl.ideanexus.cloud"
  - "traefik.http.middlewares.api-cors.headers.accesscontrolallowheaders=Content-Type,Authorization"
  
  # Apply multiple middlewares
  - "traefik.http.routers.sonnenbankerl-api.middlewares=api-cors,api-ratelimit"
```

### With Custom Network

If your Traefik uses a different network name:

```yaml
networks:
  my_proxy_network:
    external: true
    name: proxy  # Your actual network name

services:
  api:
    networks:
      - my_proxy_network
      - internal
```

## Maintenance Scripts

### Database Backup

```bash
# Run manual backup
./scripts/backup.sh

# Schedule daily backups (crontab)
crontab -e
# Add: 0 2 * * * /opt/sonnenbankerl/infrastructure/scripts/backup.sh
```

**Backup retention:** Last 30 days (configurable in script)

### Health Monitoring

```bash
# Check API health
./scripts/healthcheck.sh

# Schedule health checks every 5 minutes
crontab -e
# Add: */5 * * * * /opt/sonnenbankerl/infrastructure/scripts/healthcheck.sh
```

### Deployment Automation

```bash
# Deploy latest changes
./scripts/deploy.sh
```

**This script performs:**
1. Pulls latest code from git
2. Rebuilds Docker containers
3. Runs database migrations
4. Restarts services
5. Verifies health

## Monitoring

### Application Logs

**Docker Compose:**
```bash
# View API logs
docker-compose logs -f api

# View all logs
docker-compose logs -f

# View last 100 lines
docker-compose logs --tail=100 api
```

**Systemd:**
```bash
# Follow API logs
sudo journalctl -u api.service -f

# View recent logs
sudo journalctl -u api.service -n 100
```

### Log Locations

```bash
# Application logs
/var/log/sonnenbankerl/
  ├── api.log           # API access and errors
  ├── precompute.log    # Precomputation job logs
  └── cron.log          # Scheduled task logs

# Traefik logs (your existing setup)
/var/log/traefik/
  └── access.log        # Access logs with rate limiting info

# PostgreSQL logs
/var/log/postgresql/
  └── postgresql-14-main.log
```

### Database Monitoring

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U postgres -d sonnenbankerl

# Check table sizes
SELECT pg_size_pretty(pg_total_relation_size('exposure'));

# Monitor active connections
SELECT count(*) FROM pg_stat_activity;

# Slow query analysis
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### Traefik Dashboard

Check your Traefik dashboard to monitor:
- Service health (green/red status)
- Request rate and response times
- SSL certificate status
- Active routes

## Security

### Firewall Configuration

```bash
# Configure UFW (if not already configured)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp   # Traefik HTTP
sudo ufw allow 443/tcp  # Traefik HTTPS
sudo ufw enable
```

### Database Security

- PostgreSQL listens only on Docker internal network
- No direct external access to port 5432
- Strong passwords in `.env` file
- Regular automated backups

### API Security

**Via Traefik middleware:**
- Rate limiting per IP (100 requests/minute recommended)
- CORS configuration for Flutter app domains
- Automatic HTTPS with Let's Encrypt
- HTTP to HTTPS redirect

### Environment Variables

**Never commit `.env` file to git!**

Required security measures:
- Strong `POSTGRES_PASSWORD` (16+ characters)
- Unique `SECRET_KEY`
- Valid `GEOSPHERE_API_KEY`
- Proper `ALLOWED_ORIGINS` (don't use `*` in production)

## Scaling

### Horizontal Scaling

Scale API instances for increased load:

```bash
# Scale to 3 replicas
docker-compose up -d --scale api=3

# Traefik automatically load-balances across replicas
```

### Database Optimization

```sql
-- Enable connection pooling with pgBouncer
-- Configure TimescaleDB compression
ALTER TABLE exposure SET (timescaledb.compress = true);
SELECT add_compression_policy('exposure', INTERVAL '7 days');

-- Create read replicas for heavy queries (advanced)
```

### Caching Layer

Add Redis for frequently accessed data:

```yaml
services:
  redis:
    image: redis:alpine
    networks:
      - internal
    restart: unless-stopped
```

## Troubleshooting

### API not accessible via domain

```bash
# Check Traefik picked up the service
docker logs traefik | grep sonnenbankerl

# Verify Docker labels
docker inspect sonnenbankerl-api | grep -A 20 Labels

# Check API is running
docker-compose ps

# Test API directly (without Traefik)
curl http://localhost:8000/api/health
```

### SSL Certificate Issues

```bash
# Check Traefik certificate resolver logs
docker logs traefik | grep -i cert

# Verify domain DNS points to VPS
nslookup sonnenbankerl-api.ideanexus.cloud

# Force certificate renewal (Traefik v2)
# Remove certificate and restart Traefik
```

### Database Connection Errors

```bash
# Verify PostgreSQL is running
docker-compose ps postgres

# Check database logs
docker-compose logs postgres

# Test connection
docker-compose exec postgres psql -U postgres -d sonnenbankerl -c "SELECT 1;"
```

### Out of Disk Space

```bash
# Check usage
df -h

# Clean up Docker
docker system prune -a

# Remove old backups
find /backups -name "*.sql.gz" -mtime +30 -delete

# Clean TimescaleDB old chunks
psql -d sonnenbankerl -c "SELECT drop_chunks('exposure', INTERVAL '1 year');"
```

## Traefik Version Compatibility

### Traefik v2

Labels shown in this documentation are for Traefik v2.

### Traefik v3

For Traefik v3, update labels:
- `traefik.http.routers.*.tls.certresolver` stays the same
- Most labels remain compatible
- Check Traefik v3 migration guide for specific changes

## Documentation

For detailed architecture and configuration, see:
- [Backend Architecture](../docs/architecture.md)
- [Database Schema](../database/README.md)
- [API Documentation](../backend/README.md)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
