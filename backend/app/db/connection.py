import asyncpg
import logging
from typing import Optional

from app.config import settings

logger = logging.getLogger(__name__)

# Global connection pool
_pool: Optional[asyncpg.Pool] = None


async def init_db():
    """Initialize database connection pool"""
    global _pool
    try:
        _pool = await asyncpg.create_pool(
            settings.database_url,
            min_size=2,
            max_size=10,
            command_timeout=60
        )
        logger.info("Database pool created successfully")
    except Exception as e:
        logger.error(f"Failed to create database pool: {e}")
        raise


async def close_db():
    """Close database connection pool"""
    global _pool
    if _pool:
        await _pool.close()
        logger.info("Database pool closed")


async def get_pool() -> asyncpg.Pool:
    """Get database connection pool"""
    if _pool is None:
        raise RuntimeError("Database pool not initialized")
    return _pool
