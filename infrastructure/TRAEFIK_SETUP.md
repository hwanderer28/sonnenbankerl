# Traefik Integration Guide

Quick reference for integrating Sonnenbankerl API with your existing Traefik setup.

## Prerequisites

Before deploying, you need:

1. **Traefik running on your VPS**
2. **Docker network** that Traefik monitors (commonly named `traefik` or `proxy`)
3. **Entry points configured** (typically `web` for HTTP and `websecure` for HTTPS)
4. **Certificate resolver** set up for Let's Encrypt (optional but recommended)

## Required Information

To configure the production deployment, you'll need to know:

### 1. Traefik Network Name

```bash
# List Docker networks
docker network ls

# Common names: traefik, proxy, web
```

### 2. Entry Points

Check your Traefik configuration file or command:

```yaml
# Static configuration (traefik.yml)
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
```

Common entry point names:
- `web` - HTTP (port 80)
- `websecure` - HTTPS (port 443)

### 3. Certificate Resolver Name

```yaml
# Static configuration (traefik.yml)
certificatesResolvers:
  letsencrypt:
    acme:
      email: your@email.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
```

Common resolver names: `letsencrypt`, `le`, `default`

### 4. Domain Name

The domain you'll use for the API (e.g., `api.sonnenbankerl.com`)

**Important:** Ensure DNS A record points to your VPS IP before deployment.

## Configuration Steps

### 1. Update .env File

```bash
cd /opt/sonnenbankerl
cp .env.example .env
nano .env
```

**Set these Traefik-specific variables:**

```bash
# Your API domain
DOMAIN=api.sonnenbankerl.com

# Your Traefik network name (check with: docker network ls)
TRAEFIK_NETWORK=traefik

# Your Traefik entry point for HTTPS (usually 'websecure')
TRAEFIK_ENTRYPOINT=websecure

# Your certificate resolver name (check your Traefik config)
CERT_RESOLVER=letsencrypt
```

### 2. Verify Network Exists

```bash
# Check if Traefik network exists
docker network inspect traefik

# If it doesn't exist, check what Traefik uses
docker inspect traefik | grep -A 20 Networks
```

### 3. Deploy

```bash
cd infrastructure/docker
docker-compose -f docker-compose.prod.yml up -d
```

### 4. Verify Traefik Picked Up Service

**Check Traefik logs:**
```bash
docker logs traefik | grep sonnenbankerl
```

**Check Traefik dashboard** (if enabled):
- Visit your Traefik dashboard
- Look for `sonnenbankerl-api` router
- Verify it's in "green" status

**Test the endpoint:**
```bash
curl https://api.sonnenbankerl.com/api/health
```

## Docker Compose Labels Explained

The production compose file includes these Traefik labels:

```yaml
labels:
  # Enable Traefik for this container
  - "traefik.enable=true"
  
  # Specify which Docker network Traefik should use
  - "traefik.docker.network=traefik"
  
  # Routing rule: match requests to api.sonnenbankerl.com
  - "traefik.http.routers.sonnenbankerl-api.rule=Host(`api.sonnenbankerl.com`)"
  
  # Use the 'websecure' entry point (HTTPS)
  - "traefik.http.routers.sonnenbankerl-api.entrypoints=websecure"
  
  # Enable TLS
  - "traefik.http.routers.sonnenbankerl-api.tls=true"
  
  # Use Let's Encrypt certificate resolver
  - "traefik.http.routers.sonnenbankerl-api.tls.certresolver=letsencrypt"
  
  # API service runs on port 8000 inside container
  - "traefik.http.services.sonnenbankerl-api.loadbalancer.server.port=8000"
```

## Optional: Rate Limiting

Uncomment these labels in `docker-compose.prod.yml` to enable rate limiting:

```yaml
labels:
  # ... existing labels ...
  
  # Rate limiting: 100 requests/minute average, 50 burst
  - "traefik.http.middlewares.sonnenbankerl-ratelimit.ratelimit.average=100"
  - "traefik.http.middlewares.sonnenbankerl-ratelimit.ratelimit.burst=50"
  - "traefik.http.middlewares.sonnenbankerl-ratelimit.ratelimit.period=1m"
  
  # Apply middleware to router
  - "traefik.http.routers.sonnenbankerl-api.middlewares=sonnenbankerl-ratelimit"
```

## Optional: CORS Headers

If your Flutter app runs on a different domain, enable CORS:

```yaml
labels:
  # ... existing labels ...
  
  # CORS configuration
  - "traefik.http.middlewares.sonnenbankerl-cors.headers.accesscontrolallowmethods=GET,OPTIONS,POST"
  - "traefik.http.middlewares.sonnenbankerl-cors.headers.accesscontrolalloworigin=*"
  - "traefik.http.middlewares.sonnenbankerl-cors.headers.accesscontrolallowheaders=Content-Type,Authorization"
  
  # Apply both CORS and rate limiting
  - "traefik.http.routers.sonnenbankerl-api.middlewares=sonnenbankerl-cors,sonnenbankerl-ratelimit"
```

## Troubleshooting

### Service Not Accessible

**1. Check container is running:**
```bash
docker-compose -f docker-compose.prod.yml ps
```

**2. Verify container is on Traefik network:**
```bash
docker inspect sonnenbankerl-api | grep -A 10 Networks
```

**3. Check Traefik logs:**
```bash
docker logs traefik --tail 100 | grep sonnenbankerl
```

**4. Test API directly (bypass Traefik):**
```bash
# Find container IP
docker inspect sonnenbankerl-api | grep IPAddress

# Test directly
curl http://CONTAINER_IP:8000/api/health
```

### Certificate Not Generated

**1. Verify DNS points to VPS:**
```bash
nslookup api.sonnenbankerl.com
dig api.sonnenbankerl.com
```

**2. Check Traefik certificate logs:**
```bash
docker logs traefik | grep -i "certificate\|acme\|letsencrypt"
```

**3. Ensure port 80 is accessible** (needed for HTTP challenge):
```bash
sudo ufw status
# Should show 80/tcp ALLOW
```

### Wrong Network Error

If you get "network not found":

```bash
# Check actual network name
docker network ls

# Update .env file
TRAEFIK_NETWORK=actual_network_name

# Recreate containers
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.prod.yml up -d
```

## Example Traefik Configurations

### Traefik v2 Static Config (traefik.yml)

```yaml
api:
  dashboard: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik

certificatesResolvers:
  letsencrypt:
    acme:
      email: your@email.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
```

### Traefik v2 Docker Compose

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./letsencrypt:/letsencrypt
    networks:
      - traefik

networks:
  traefik:
    name: traefik
```

## Next Steps

After successful deployment:

1. **Test all API endpoints**
   ```bash
   curl https://api.sonnenbankerl.com/api/health
   curl https://api.sonnenbankerl.com/api/benches?lat=47.07&lon=15.44&radius=1000
   ```

2. **Monitor logs**
   ```bash
   docker-compose -f docker-compose.prod.yml logs -f api
   ```

3. **Set up monitoring** (see infrastructure/README.md)

4. **Configure backups** (see infrastructure/scripts/backup.sh)

5. **Update Flutter app** to use production API URL

## Support

For Traefik-specific issues, consult:
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Traefik Docker Provider Docs](https://doc.traefik.io/traefik/providers/docker/)
- [Traefik Community Forum](https://community.traefik.io/)

For project-specific issues, see:
- [infrastructure/README.md](README.md)
- [Backend Architecture](../docs/architecture.md)
