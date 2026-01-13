# Sonnenbankerl Backend Deployment Guide

Complete step-by-step guide for deploying the Sonnenbankerl API to your VPS.

## ✅ Deployment Status

**DEPLOYED & OPERATIONAL**

- **URL**: https://sonnenbankerl.ideanexus.cloud
- **Status**: Production, fully functional
- **Deployed**: December 30, 2025
- **Health**: https://sonnenbankerl.ideanexus.cloud/api/health
- **Docs**: https://sonnenbankerl.ideanexus.cloud/docs

**For API usage, see [API Integration Guide](API_INTEGRATION.md)**

---

## Prerequisites

- VPS with Traefik already configured
- SSH access to VPS
- Domain name configured (`sonnenbankerl.ideanexus.cloud`)
- Docker and Docker Compose installed on VPS

## VPS Configuration

Your VPS setup:
- **Traefik Network**: `traefik_proxy`
- **Certificate Resolver**: `letsencrypt`
- **Postgres Port**: 5435 (external) → 5432 (internal)

---

## Step 1: DNS Configuration

Configure DNS A record for your domain:

```
Type: A
Name: sonnenbankerl
Domain: ideanexus.cloud
Value: [Your VPS IP Address]
TTL: 3600
```

**Verify DNS propagation:**
```bash
nslookup sonnenbankerl.ideanexus.cloud
dig sonnenbankerl.ideanexus.cloud
```

---

## Step 2: Pull Latest Code on VPS

SSH into your VPS and pull the backend branch:

```bash
# SSH into VPS
ssh your-user@your-vps-ip

# Navigate to project directory
cd /srv/docker/sonnenbankerl

# Fetch latest changes
git fetch origin

# Checkout backend branch
git checkout backend

# Pull latest changes
git pull origin backend
```

---

## Step 3: Configure Environment

Create and configure the `.env` file:

```bash
# Navigate to docker directory
cd infrastructure/docker

# Copy example env file
cp ../../.env.example .env

# Edit environment variables
nano .env
```

**Required configuration:**

```bash
# Set a strong password (generate one with: openssl rand -base64 32)
POSTGRES_PASSWORD=YOUR_SECURE_PASSWORD_HERE

# Verify domain is correct
DOMAIN=sonnenbankerl.ideanexus.cloud

# Other defaults should be fine
POSTGRES_USER=postgres
POSTGRES_DB=sonnenbankerl
ENVIRONMENT=production
ALLOWED_ORIGINS=*
```

**Save and exit** (Ctrl+X, then Y, then Enter)

---

## Step 4: Deploy Services

Build and start the Docker containers:

```bash
# Make sure you're in infrastructure/docker/
cd /srv/docker/sonnenbankerl/infrastructure/docker

# Build and start services
docker-compose up -d --build

# This will:
# 1. Build the FastAPI backend image
# 2. Start PostgreSQL with TimescaleDB
# 3. Run database migrations automatically
# 4. Start the API service
# 5. Register with Traefik for HTTPS access
```

---

## Step 5: Monitor Deployment

Watch the logs to ensure everything starts correctly:

```bash
# Follow all logs
docker-compose logs -f

# Or watch specific services:
docker-compose logs -f api
docker-compose logs -f postgres
```

**Look for:**
- ✅ "Starting Sonnenbankerl API"
- ✅ "Database connection initialized"
- ✅ "Schema initialized successfully"
- ✅ "Sample data inserted successfully"
- ✅ "Application startup complete"

**Press Ctrl+C to exit logs**

---

## Step 6: Verify Deployment

### Check Services are Running

```bash
docker-compose ps
```

Expected output:
```
NAME                    STATUS              PORTS
sonnenbankerl-api       Up (healthy)        
sonnenbankerl-postgres  Up (healthy)        0.0.0.0:5435->5432/tcp
```

### Check Traefik Picked Up the Service

```bash
docker logs traefik | grep sonnenbankerl
```

You should see routing rules registered.

### Test API Health Endpoint

```bash
curl https://sonnenbankerl.ideanexus.cloud/api/health
```

Expected response:
```json
{
  "status": "healthy",
  "database": "connected",
  "timestamp": "2025-12-30T15:30:00.123456"
}
```

### Test Benches Endpoint

```bash
# Test with Graz city center coordinates
curl "https://sonnenbankerl.ideanexus.cloud/api/benches?lat=47.07&lon=15.44&radius=1000"
```

Expected response:
```json
{
  "benches": [
    {
      "id": 1,
      "osm_id": 1001,
      "name": "Stadtpark Bench 1",
      "location": {"lat": 47.0707, "lon": 15.4395},
      "elevation": 353.2,
      "distance": 245.3,
      "current_status": "sunny",
      "sun_until": "2025-12-30T18:00:00",
      "remaining_minutes": 210
    },
    ...
  ]
}
```

### Test API Documentation

Visit in browser:
```
https://sonnenbankerl.ideanexus.cloud/docs
```

You should see the interactive Swagger UI.

---

## Step 7: Database Access (Optional)

If you need to access the database directly:

```bash
# From VPS, connect to postgres
psql -h localhost -p 5435 -U postgres -d sonnenbankerl

# Enter password when prompted
# Then you can run SQL queries:
sonnenbankerl=# SELECT COUNT(*) FROM benches;
 count 
-------
     3
(1 row)

sonnenbankerl=# \q  # Exit
```

---

## Troubleshooting

### Issue: API returns 502 Bad Gateway

**Solution:**
```bash
# Check API logs
docker-compose logs api

# Restart API container
docker-compose restart api
```

### Issue: Database connection failed

**Solution:**
```bash
# Check postgres is running
docker-compose ps postgres

# Check postgres logs
docker-compose logs postgres

# Verify DATABASE_URL in .env matches postgres credentials
```

### Issue: Traefik not routing to API

**Solution:**
```bash
# Verify Traefik can see the container
docker inspect sonnenbankerl-api | grep -A 20 traefik

# Check container is on traefik_proxy network
docker network inspect traefik_proxy

# Restart Traefik if needed
docker restart traefik
```

### Issue: SSL certificate not generated

**Solution:**
```bash
# Check Traefik logs for certificate errors
docker logs traefik | grep -i "certificate\|acme"

# Verify DNS is pointing to your VPS
dig sonnenbankerl.ideanexus.cloud

# Ensure ports 80 and 443 are open
sudo ufw status
```

### Issue: Migrations didn't run

**Solution:**
```bash
# Check if migrations ran
docker-compose logs postgres | grep "Schema initialized"

# If not, run manually:
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /docker-entrypoint-initdb.d/001_initial_schema.sql
docker-compose exec postgres psql -U postgres -d sonnenbankerl -f /docker-entrypoint-initdb.d/002_create_indexes.sql
# 003_sample_data.sql is now a no-op placeholder (kept for ordering only)
```

---

## Updating the Deployment

When you need to deploy updates:

```bash
cd /srv/docker/sonnenbankerl

# Pull latest changes
git pull origin backend

# Navigate to docker directory
cd infrastructure/docker

# Rebuild and restart
docker-compose up -d --build

# Check logs
docker-compose logs -f api
```

---

## Maintenance

### View Logs

```bash
cd /srv/docker/sonnenbankerl/infrastructure/docker

# View recent logs
docker-compose logs --tail 100

# Follow logs in real-time
docker-compose logs -f
```

### Restart Services

```bash
# Restart all services
docker-compose restart

# Restart specific service
docker-compose restart api
docker-compose restart postgres
```

### Stop Services

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (WARNING: deletes database data)
docker-compose down -v
```

### Database Backup

```bash
# Create backup
docker-compose exec postgres pg_dump -U postgres sonnenbankerl | gzip > backup_$(date +%Y%m%d).sql.gz

# Restore from backup
gunzip < backup_20251230.sql.gz | docker-compose exec -T postgres psql -U postgres sonnenbankerl
```

---

## Next Steps

1. ✅ Verify all endpoints work correctly
2. ✅ Test from mobile Flutter app
3. 🔄 Add real OSM bench data (later)
4. 🔄 Implement GeoSphere weather API (when key available)
5. 🔄 Build precomputation pipeline (later)

---

## API Endpoints Reference

### Health Check
```
GET https://sonnenbankerl.ideanexus.cloud/api/health
```

### Get Benches Near Location
```
GET https://sonnenbankerl.ideanexus.cloud/api/benches?lat=47.07&lon=15.44&radius=1000
```

### Get Single Bench Details
```
GET https://sonnenbankerl.ideanexus.cloud/api/benches/{id}
```

### API Documentation
```
GET https://sonnenbankerl.ideanexus.cloud/docs
```

---

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review logs: `docker-compose logs`
3. Check infrastructure/README.md for additional info
4. Verify Traefik configuration in TRAEFIK_SETUP.md
