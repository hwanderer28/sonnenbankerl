from fastapi import APIRouter, HTTPException, Query
import logging

from app.models.bench import BenchesResponse, BenchListItem, BenchDetail, Location
from app.db.queries import get_benches_within_radius, get_bench_by_id
from app.services.exposure import get_bench_sun_status

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/benches", response_model=BenchesResponse)
async def get_benches(
    lat: float = Query(..., description="Latitude", ge=-90, le=90),
    lon: float = Query(..., description="Longitude", ge=-180, le=180),
    radius: float = Query(1000, description="Search radius in meters", gt=0, le=10000)
):
    """
    Get benches within radius of a location
    
    Args:
        lat: Latitude (-90 to 90)
        lon: Longitude (-180 to 180)
        radius: Search radius in meters (max 10km)
        
    Returns:
        List of benches with current sun status
    """
    logger.info(f"Fetching benches near ({lat}, {lon}) within {radius}m")
    
    try:
        # Get benches from database
        benches = await get_benches_within_radius(lat, lon, radius)
        
        # Enrich with sun status
        result = []
        for bench in benches:
            status, sun_until, remaining_minutes = await get_bench_sun_status(bench['id'])
            
            result.append(BenchListItem(
                id=bench['id'],
                osm_id=bench.get('osm_id'),
                name=bench.get('name'),
                location=Location(lat=bench['lat'], lon=bench['lon']),
                elevation=bench.get('elevation'),
                distance=bench['distance'],
                current_status=status,
                sun_until=sun_until,
                remaining_minutes=remaining_minutes
            ))
        
        logger.info(f"Found {len(result)} benches")
        return BenchesResponse(benches=result)
        
    except Exception as e:
        logger.error(f"Error fetching benches: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")


@router.get("/benches/{bench_id}", response_model=BenchDetail)
async def get_bench(bench_id: int):
    """
    Get detailed information about a specific bench
    
    Args:
        bench_id: Bench ID
        
    Returns:
        Bench details with current sun status
    """
    logger.info(f"Fetching bench {bench_id}")
    
    try:
        # Get bench from database
        bench = await get_bench_by_id(bench_id)
        
        if not bench:
            raise HTTPException(status_code=404, detail="Bench not found")
        
        # Get sun status
        status, sun_until, remaining_minutes = await get_bench_sun_status(bench_id)
        
        return BenchDetail(
            id=bench['id'],
            osm_id=bench.get('osm_id'),
            name=bench.get('name'),
            location=Location(lat=bench['lat'], lon=bench['lon']),
            elevation=bench.get('elevation'),
            current_status=status,
            sun_until=sun_until,
            remaining_minutes=remaining_minutes,
            created_at=bench.get('created_at')
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching bench {bench_id}: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")
