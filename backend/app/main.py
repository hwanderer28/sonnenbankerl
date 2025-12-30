from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

from app.config import settings
from app.api import health, benches
from app.db.connection import init_db, close_db

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="Sonnenbankerl API",
    description="API for finding sunny benches in Graz",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins.split(",") if settings.allowed_origins != "*" else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Startup event
@app.on_event("startup")
async def startup():
    logger.info("Starting Sonnenbankerl API")
    logger.info(f"Environment: {settings.environment}")
    await init_db()
    logger.info("Database connection initialized")

# Shutdown event
@app.on_event("shutdown")
async def shutdown():
    logger.info("Shutting down Sonnenbankerl API")
    await close_db()
    logger.info("Database connection closed")

# Include routers
app.include_router(health.router, prefix="/api", tags=["health"])
app.include_router(benches.router, prefix="/api", tags=["benches"])

# Root endpoint
@app.get("/")
async def root():
    return {
        "message": "Sonnenbankerl API",
        "version": "0.1.0",
        "docs": "/docs"
    }
