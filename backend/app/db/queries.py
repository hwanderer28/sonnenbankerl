import logging
from typing import List, Optional
from datetime import datetime

from app.db.connection import get_pool

logger = logging.getLogger(__name__)


async def get_benches_within_radius(lat: float, lon: float, radius: float) -> List[dict]:
    """
    Get benches within radius of a location
    
    Args:
        lat: Latitude
        lon: Longitude
        radius: Search radius in meters
        
    Returns:
        List of bench dictionaries with distance
    """
    pool = await get_pool()
    
    query = """
        SELECT 
            b.id,
            b.osm_id,
            b.name,
            ST_Y(b.geom::geometry) as lat,
            ST_X(b.geom::geometry) as lon,
            b.elevation,
            ST_Distance(b.geom, ST_SetSRID(ST_MakePoint($2, $1), 4326)) as distance
        FROM benches b
        WHERE ST_DWithin(b.geom, ST_SetSRID(ST_MakePoint($2, $1), 4326), $3)
        ORDER BY distance;
    """
    
    try:
        async with pool.acquire() as conn:
            rows = await conn.fetch(query, lat, lon, radius)
            return [dict(row) for row in rows]
    except Exception as e:
        logger.error(f"Error querying benches: {e}")
        raise


async def get_bench_by_id(bench_id: int) -> Optional[dict]:
    """
    Get bench by ID
    
    Args:
        bench_id: Bench ID
        
    Returns:
        Bench dictionary or None if not found
    """
    pool = await get_pool()
    
    query = """
        SELECT 
            id,
            osm_id,
            name,
            ST_Y(geom::geometry) as lat,
            ST_X(geom::geometry) as lon,
            elevation,
            created_at
        FROM benches
        WHERE id = $1;
    """
    
    try:
        async with pool.acquire() as conn:
            row = await conn.fetchrow(query, bench_id)
            return dict(row) if row else None
    except Exception as e:
        logger.error(f"Error querying bench {bench_id}: {e}")
        raise


async def get_current_exposure(bench_id: int, current_time: datetime) -> Optional[bool]:
    """
    Get current sun exposure status for a bench
    
    Args:
        bench_id: Bench ID
        current_time: Current timestamp (rounded to 10-min interval)
        
    Returns:
        True if exposed to sun, False if shaded, None if no data
    """
    pool = await get_pool()
    
    query = """
        SELECT e.exposed
        FROM exposure e
        JOIN timestamps t ON t.id = e.ts_id
        WHERE e.bench_id = $1
        AND t.ts = $2::timestamptz
        LIMIT 1;
    """
    
    try:
        async with pool.acquire() as conn:
            row = await conn.fetchrow(query, bench_id, current_time)
            return row['exposed'] if row else None
    except Exception as e:
        logger.error(f"Error querying exposure for bench {bench_id}: {e}")
        raise


async def get_next_sun_change(bench_id: int, current_time: datetime, current_status: bool) -> Optional[datetime]:
    """
    Get next time when sun status changes
    
    Args:
        bench_id: Bench ID
        current_time: Current timestamp
        current_status: Current exposure status (True=sunny, False=shady)
        
    Returns:
        Timestamp of next change, or None if no change found
    """
    pool = await get_pool()
    
    # If currently sunny, find next shady time
    # If currently shady, find next sunny time
    target_status = not current_status
    
    query = """
        SELECT t.ts::timestamptz
        FROM exposure e
        JOIN timestamps t ON t.id = e.ts_id
        WHERE e.bench_id = $1
        AND t.ts > $2::timestamptz
        AND e.exposed = $3
        ORDER BY t.ts
        LIMIT 1;
    """
    
    try:
        async with pool.acquire() as conn:
            row = await conn.fetchrow(query, bench_id, current_time, target_status)
            return row['ts'] if row else None
    except Exception as e:
        logger.error(f"Error querying next sun change for bench {bench_id}: {e}")
        raise


async def get_data_window() -> tuple[Optional[datetime], Optional[datetime]]:
    """
    Get min and max timestamps available in precomputed data.

    Returns:
        Tuple of (window_start, window_end) or (None, None) if no timestamps.
    """
    pool = await get_pool()
    query = """
        SELECT MIN(ts) AS start_ts, MAX(ts) AS end_ts FROM timestamps;
    """
    try:
        async with pool.acquire() as conn:
            row = await conn.fetchrow(query)
            if row:
                return row['start_ts'], row['end_ts']
            return None, None
    except Exception as e:
        logger.error(f"Error querying data window: {e}")
        raise


async def check_database_health() -> bool:
    """
    Check if database connection is healthy
    
    Returns:
        True if database is accessible, False otherwise
    """
    try:
        pool = await get_pool()
        async with pool.acquire() as conn:
            result = await conn.fetchval("SELECT 1")
            return result == 1
    except Exception as e:
        logger.error(f"Database health check failed: {e}")
        return False


async def get_bench_status_batch(
    bench_ids: list[int], current_time: datetime
) -> list[dict]:
    """
    Get current exposure and next change for multiple benches in a single query.
    Reduces N+1 query pattern from ~40 queries to 1 for 20 benches.
    
    Args:
        bench_ids: List of bench IDs
        current_time: Current timestamp (rounded to 10-min interval)
        
    Returns:
        List of dicts with bench_id, exposed, and next_change_ts
    """
    if not bench_ids:
        return []
    
    pool = await get_pool()
    
    query = """
        SELECT
            b.id as bench_id,
            e.exposed,
            next_sun.ts as next_change_ts
        FROM unnest($1::int[]) WITH ORDINALITY AS t(bench_id, ord)
        JOIN benches b ON b.id = t.bench_id
        LEFT JOIN exposure e ON e.bench_id = b.id
            AND e.ts_id = (SELECT id FROM timestamps WHERE ts = $2::timestamptz)
        LEFT JOIN LATERAL (
            SELECT t.ts FROM exposure e2
            JOIN timestamps t ON t.id = e2.ts_id
            WHERE e2.bench_id = b.id
              AND t.ts > $2::timestamptz
              AND e2.exposed != COALESCE(e.exposed, FALSE)
            ORDER BY t.ts
            LIMIT 1
        ) next_sun ON true
        ORDER BY t.ord;
    """
    
    try:
        async with pool.acquire() as conn:
            rows = await conn.fetch(query, bench_ids, current_time)
            return [dict(row) for row in rows]
    except Exception as e:
        logger.error(f"Error batch querying bench status: {e}")
        raise
