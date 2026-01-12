from fastapi import APIRouter, HTTPException, Query
import logging

from app.models.bench import BenchesResponse, BenchListItem, BenchDetail, Location
from app.db.queries import get_benches_within_radius, get_bench_by_id, get_data_window
from app.services.exposure import get_bench_sun_status

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get(
    "/benches",
    response_model=BenchesResponse,
    summary="List benches near a location with current sun status",
    response_description="Current status for benches plus data window metadata"
)
async def get_benches(
    lat: float = Query(..., description="Latitude", ge=-90, le=90),
    lon: float = Query(..., description="Longitude", ge=-180, le=180),
    radius: float = Query(1000, description="Search radius in meters", gt=0, le=10000)
):
    """
    Get benches within a radius and return their current sun/shade state.
    
    - Rounds `now` to the nearest 10-minute timestamp.
    - Includes `window_start`/`window_end` describing the precomputed data window.
    """
    logger.info(f"Fetching benches near ({lat}, {lon}) within {radius}m")
    
    try:
        # Get benches from database
        benches = await get_benches_within_radius(lat, lon, radius)
        window_start, window_end = await get_data_window()
        
        # Enrich with sun status
        result = []
        for bench in benches:
            status, sun_until, remaining_minutes = await get_bench_sun_status(bench['id'])
            status_note = None
            
            result.append(BenchListItem(
                id=bench['id'],
                osm_id=bench.get('osm_id'),
                name=bench.get('name'),
                location=Location(lat=bench['lat'], lon=bench['lon']),
                elevation=bench.get('elevation'),
                distance=bench['distance'],
                current_status=status,
                sun_until=sun_until,
                remaining_minutes=remaining_minutes,
                status_note=status_note
            ))
        
        logger.info(f"Found {len(result)} benches")
        return BenchesResponse(benches=result, window_start=window_start, window_end=window_end)
        
    except Exception as e:
        logger.error(f"Error fetching benches: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")


@router.get(
    "/benches/{bench_id}",
    response_model=BenchDetail,
    summary="Get bench details with current sun status",
    response_description="Current status, next change, and note if no change within the week"
)
async def get_bench(bench_id: int):
    """
    Get detailed information about a specific bench.
    
    - Rounds `now` to the nearest 10-minute timestamp.
    - Includes precomputed window metadata.
    """
    logger.info(f"Fetching bench {bench_id}")
    
    try:
        # Get bench from database
        bench = await get_bench_by_id(bench_id)
        
        if not bench:
            raise HTTPException(status_code=404, detail="Bench not found")
        
        # Get sun status
        status, sun_until, remaining_minutes = await get_bench_sun_status(bench_id)
        status_note = None
        
        return BenchDetail(
            id=bench['id'],
            osm_id=bench.get('osm_id'),
            name=bench.get('name'),
            location=Location(lat=bench['lat'], lon=bench['lon']),
            elevation=bench.get('elevation'),
            current_status=status,
            sun_until=sun_until,
            remaining_minutes=remaining_minutes,
            status_note=status_note,
            created_at=bench.get('created_at')
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching bench {bench_id}: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")
