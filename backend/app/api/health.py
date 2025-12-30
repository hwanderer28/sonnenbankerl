from fastapi import APIRouter
from datetime import datetime
import logging

from app.db.queries import check_database_health

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/health")
async def health_check():
    """
    Health check endpoint
    
    Returns API and database status
    """
    db_healthy = await check_database_health()
    
    status = "healthy" if db_healthy else "unhealthy"
    db_status = "connected" if db_healthy else "disconnected"
    
    logger.debug(f"Health check: {status}, Database: {db_status}")
    
    return {
        "status": status,
        "database": db_status,
        "timestamp": datetime.utcnow().isoformat()
    }
