# Sonnenbankerl Backend API

FastAPI-based REST API service for the Sonnenbankerl application.

## Project Structure

```
backend/
├── app/
│   ├── main.py                # FastAPI app entry point
│   ├── api/                   # API endpoint routes
│   │   ├── benches.py         # Bench-related endpoints
│   │   └── health.py          # Health check endpoint
│   ├── models/                # Pydantic models
│   │   ├── bench.py           # Bench data models
│   │   └── exposure.py        # Exposure data models
│   ├── db/                    # Database layer
│   │   ├── connection.py      # PostgreSQL connection pool
│   │   └── queries.py         # SQL queries
│   ├── services/              # Business logic
│   │   ├── weather.py         # GeoSphere API integration
│   │   └── exposure.py        # Sun exposure calculations
│   └── config.py              # Configuration management
├── tests/                     # Unit and integration tests
├── requirements.txt           # Python dependencies
└── Dockerfile                # Docker container definition
```

## Setup

### Prerequisites
- Python 3.10+
- PostgreSQL 14+ with PostGIS and TimescaleDB
- Virtual environment (recommended)

### Installation

```bash
# Navigate to backend directory
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set up environment variables
cp ../.env.example .env
# Edit .env with your configuration
```

### Running Locally

```bash
# Start API server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Access API documentation
# http://localhost:8000/docs (Swagger UI)
# http://localhost:8000/redoc (ReDoc)
```

## API Endpoints

### Benches

```
GET  /api/benches
     Query params: lat, lon, radius
     Returns: List of benches with current sun/shade status

GET  /api/benches/{id}
     Returns: Detailed bench information

GET  /api/benches/{id}/exposure
     Query params: from, to (timestamps)
     Returns: Sun exposure timeline
```

### Health

```
GET  /api/health
     Returns: API health status and database connectivity
```

## Database Connection

The API connects to PostgreSQL using the `DATABASE_URL` environment variable:

```
postgresql://user:password@localhost:5432/sonnenbankerl
```

## Weather Integration

The backend integrates with GeoSphere Austria API for real-time weather data. Configure the API key in `.env`:

```
GEOSPHERE_API_KEY=your_key_here
```

## Testing

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=app tests/
```

## Docker

```bash
# Build image
docker build -t sonnenbankerl-api .

# Run container
docker run -p 8000:8000 --env-file .env sonnenbankerl-api
```

## Documentation

For detailed architecture and deployment information, see:
- [Main README](../README.md)
- [Backend Architecture](../docs/architecture.md)
