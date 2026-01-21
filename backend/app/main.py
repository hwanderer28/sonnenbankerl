from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

from app.config import settings
from app.api import health, benches, weather
from app.db.connection import init_db, close_db
from app.services.scheduler import start_scheduler, stop_scheduler

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Sonnenbankerl API",
    description="API for finding sunny benches in Graz",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins.split(",") if settings.allowed_origins != "*" else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    logger.info("Starting Sonnenbankerl API")
    logger.info(f"Environment: {settings.environment}")
    await init_db()
    logger.info("Database connection initialized")
    start_scheduler()
    logger.info("Weather scheduler started")

@app.on_event("shutdown")
async def shutdown():
    logger.info("Shutting down Sonnenbankerl API")
    stop_scheduler()
    await close_db()
    logger.info("Database connection closed")

app.include_router(health.router, prefix="/api", tags=["health"])
app.include_router(benches.router, prefix="/api", tags=["benches"])
app.include_router(weather.router, prefix="/api", tags=["weather"])

@app.get("/")
async def root():
    return {
        "message": "Sonnenbankerl API",
        "version": "0.1.0",
        "docs": "/docs"
    }
