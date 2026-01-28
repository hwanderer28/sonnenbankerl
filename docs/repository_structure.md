# Repository Structure

This document provides an overview of the Sonnenbankerl monorepo structure.

## Directory Layout

```
sonnenbankerl/
├── mobile/                  # Flutter mobile application
├── backend/                 # Python FastAPI REST API
├── database/                # PostgreSQL schema & migrations
├── precomputation/          # Batch processing scripts
├── infrastructure/          # Deployment & DevOps configs
├── data/                    # Data files (git-ignored)
├── docs/                    # Project documentation
├── assets/                  # Shared assets (icons, images)
├── .env.example            # Environment variables template
├── .gitignore              # Git ignore rules
└── README.md               # Main project README
```

## Component Overview

### Mobile App (`mobile/`)

**Purpose:** Flutter-based iOS/Android application

**Current Status:** Core features implemented, in testing phase

**Key directories:**
- `lib/models/` - Data models (Bench, BenchInfo, WeatherStatus)
- `lib/services/` - API clients (ApiService), favorites management
- `lib/screens/` - UI screens (BenchMap, WelcomeScreen, SettingsSheet)
- `lib/theme/` - App theming and styling
- `test/` - Unit and widget tests
- `assets/` - Images and resources (Welcome_Screen.jpg)

**Key Features:**
- Interactive MapLibre GL map with real-time bench markers
- Visual sun/shade indicators (yellow for sunny, blue for shady)
- Bench detail popups with sun exposure predictions
- Favorites management with local persistence
- User handedness support (left/right-handed UI)
- Welcome screen for first-time users
- Settings panel for app customization

**Tech stack:** Flutter, Dart, MapLibre GL, Dio, SharedPreferences

**Documentation:** [mobile/README.md](../mobile/README.md)

---

### Backend API (`backend/`)

**Purpose:** REST API service for mobile app

**Key directories:**
- `app/api/` - API endpoint routes
- `app/models/` - Pydantic data models
- `app/db/` - Database connection & queries
- `app/services/` - Business logic (weather, exposure)
- `tests/` - API tests

**Tech stack:** Python, FastAPI, PostgreSQL

**Documentation:** [backend/README.md](../backend/README.md)

---

### Database (`database/`)

**Purpose:** Database schema, migrations, and seed data

**Key directories:**
- `migrations/` - SQL migration files (versioned)
- `seed/` - Sample data for development

**Tech stack:** PostgreSQL, PostGIS, TimescaleDB

**Documentation:** [database/README.md](../database/README.md)

---

### Precomputation (`precomputation/`)

**Purpose:** Batch processing for sun exposure calculations using a database-first approach (pure SQL)

**Key files:**
- `03_import_benches.sql` - Import benches from OSM GeoJSON, update elevations from DEM
- `04_generate_timestamps.sql` - Generate rolling 7-day timestamps
- `05_compute_sun_positions.sql` - Compute sun azimuth/elevation for each timestamp
- `06_compute_exposure.sql` - Line-of-sight computation with horizon precomputation
- `compute_next_week.sh` - Shell script orchestrating the full pipeline

**Tech stack:** Pure SQL (PL/pgSQL), PostGIS, GDAL

**Documentation:** [precomputation/README.md](../precomputation/README.md)

---

### Infrastructure (`infrastructure/`)

**Purpose:** Deployment configurations and automation

**Key directories:**
- `docker/` - Docker Compose files
- `systemd/` - Systemd service files
- `scripts/` - Backup, deployment, monitoring scripts

**Tech stack:** Docker, Traefik (existing VPS setup), Bash

**Documentation:** [infrastructure/README.md](../infrastructure/README.md)

---

### Data (`data/`)

**Purpose:** Storage for geospatial data files

**Key directories:**
- `raw/` - Original DSM/DEM files (git-ignored)
- `processed/` - Processed data (git-ignored)
- `osm/` - OpenStreetMap exports

**Note:** Large data files are not committed to git

**Documentation:** [data/README.md](../data/README.md)

---

### Documentation (`docs/`)

**Purpose:** Project documentation and specifications

**Key files:**
- `architecture.md` - Backend architecture overview
- `sunshine_calculation_pipeline.md` - Precomputation details
- `resources.md` - External resources and APIs
- `repository_structure.md` - This file
- `project_proposal.pdf` - Original project proposal

---

## Development Workflow

### Initial Setup

1. **Clone repository**
   ```bash
   git clone <repository-url>
   cd sonnenbankerl
   ```

2. **Configure environment**
   ```bash
   cp .env.example .env
   nano .env  # Edit configuration
   ```

3. **Start infrastructure**
   ```bash
   cd infrastructure/docker
   docker-compose up -d
   ```

4. **Run database migrations**
   ```bash
   cd database
   psql -d sonnenbankerl -f migrations/001_initial_schema.sql
   ```

5. **Start backend API**
   ```bash
   cd backend
   python -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   uvicorn app.main:app --reload
   ```

6. **Start mobile app**
   ```bash
   cd mobile
   flutter pub get
   flutter run
   ```

### Development Flow

**Backend development:**
```bash
cd backend
source venv/bin/activate
# Make changes to app/
uvicorn app.main:app --reload  # Auto-reloads on changes
pytest  # Run tests
```

**Mobile development:**
```bash
cd mobile
# Make changes to lib/
flutter run  # Hot reload enabled
flutter test  # Run tests
```

**Database changes:**
```bash
cd database
# Create new migration: migrations/004_new_feature.sql
psql -d sonnenbankerl -f migrations/004_new_feature.sql
```

**Precomputation:**
```bash
cd precomputation
source venv/bin/activate
python compute_exposure.py --year 2026 --parallel 4
```

## Git Workflow

### What's Tracked in Git

✅ Source code (Python, Dart)  
✅ Configuration files (Docker, Traefik labels)  
✅ Documentation (Markdown, LaTeX)  
✅ Database migrations (SQL)  
✅ Scripts (Bash, Python)  
✅ Small assets (icons, logos)

### What's Ignored

❌ Data files (DSM/DEM rasters)  
❌ Environment files (`.env`)  
❌ Build artifacts (`build/`, `dist/`)  
❌ Virtual environments (`venv/`)  
❌ IDE configs (`.vscode/`, `.idea/`)  
❌ Logs (`*.log`)  
❌ Backups (`*.sql.gz`)

### Branching Strategy

```
main                    # Production-ready code
├── develop            # Integration branch
│   ├── feature/map   # Feature branches
│   ├── feature/api
│   └── fix/bugs
```

**Workflow:**
1. Create feature branch from `develop`
2. Make changes and commit
3. Create pull request to `develop`
4. Merge to `main` for releases

## Common Tasks

### Add a New API Endpoint

1. Create route in `backend/app/api/`
2. Add Pydantic model in `backend/app/models/`
3. Implement query in `backend/app/db/queries.py`
4. Add tests in `backend/tests/`
5. Update API documentation

### Add a New Database Table

1. Create migration file in `database/migrations/`
2. Run migration: `psql -d sonnenbankerl -f migrations/XXX.sql`
3. Update models in `backend/app/models/`
4. Add seed data in `database/seed/` (optional)

### Update Bench Data

1. Download latest OSM data
2. Run: `cd precomputation && python import_osm.py`
3. Run precomputation for new benches
4. Verify data in database

### Deploy to Production

1. SSH into VPS
2. Pull latest code: `git pull origin main`
3. Run deployment script: `./infrastructure/scripts/deploy.sh`
4. Verify health: `./infrastructure/scripts/healthcheck.sh`

## File Naming Conventions

### Python
- Modules: `lowercase_with_underscores.py`
- Classes: `CapitalizedWords`
- Functions: `lowercase_with_underscores()`

### Dart/Flutter
- Files: `lowercase_with_underscores.dart`
- Classes: `CapitalizedWords`
- Variables: `camelCase`

### SQL
- Tables: `lowercase_plural` (e.g., `benches`)
- Columns: `lowercase_with_underscores`
- Migrations: `###_descriptive_name.sql` (e.g., `001_initial_schema.sql`)

### Documentation
- Markdown files: `lowercase_with_underscores.md`
- Images: `descriptive_name.png`

## Environment Variables

All services use environment variables from `.env` file:

**Database:**
- `DATABASE_URL` - PostgreSQL connection string
- `POSTGRES_PASSWORD` - Database password

**API:**
- `API_PORT` - API server port (default: 8000)
- `GEOSPHERE_API_KEY` - Weather API key

**Environment:**
- `ENVIRONMENT` - development/staging/production

See `.env.example` for complete list.

## Troubleshooting

### Can't connect to database
```bash
# Check if PostgreSQL is running
docker-compose ps postgres

# Verify connection string
echo $DATABASE_URL

# Test connection
psql $DATABASE_URL -c "SELECT 1;"
```

### API not starting
```bash
# Check for Python errors
cd backend
source venv/bin/activate
python -c "from app.main import app; print('OK')"

# Verify dependencies
pip install -r requirements.txt
```

### Flutter build errors
```bash
# Clean and rebuild
cd mobile
flutter clean
flutter pub get
flutter run
```

## Additional Resources

- [Main README](../README.md) - Project overview
- [Architecture Documentation](architecture.md) - System design
- [Sunshine Calculation Pipeline](sunshine_calculation_pipeline.md) - Algorithm details
- [Resources & APIs](resources.md) - External services

## Contributing

1. Follow the existing code style
2. Write tests for new features
3. Update documentation
4. Keep commits atomic and well-described
5. Use meaningful branch names

## License

TBD (see main [README](../README.md))
