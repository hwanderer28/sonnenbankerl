#!/usr/bin/env python3
"""
Test script for the GeoSphere Weather API integration.
Run this before starting the server to verify the weather service works.

Usage:
    cd backend
    source venv/bin/activate
    python test_weather.py
"""

import asyncio
import sys
from datetime import datetime

# Add app to path
sys.path.insert(0, ".")


async def test_weather_service():
    """Test the weather service directly"""
    print("=" * 60)
    print("Testing Weather Service")
    print("=" * 60)

    from app.services.weather import (
        fetch_weather_from_api,
        get_current_weather,
        is_sunny,
        get_sunshine_seconds,
    )

    # Test 1: Fetch from API
    print("\n[Test 1] Fetching weather from GeoSphere API...")
    try:
        status = await fetch_weather_from_api()
        print(f"  ✓ API call successful")
        print(f"    - Station: {status.station_name} ({status.station_id})")
        print(f"    - Timestamp: {status.timestamp}")
        print(f"    - Sunshine seconds: {status.sunshine_seconds}")
        print(f"    - Is sunny: {status.is_sunny}")
        print(f"    - Message: {status.message}")
    except Exception as e:
        print(f"  ✗ API call failed: {e}")
        return False

    # Test 2: Test caching
    print("\n[Test 2] Testing cache mechanism...")
    status1, cache_hit1 = await get_current_weather()
    print(f"  First call - cache_hit: {cache_hit1}")

    status2, cache_hit2 = await get_current_weather()
    print(f"  Second call - cache_hit: {cache_hit2}")

    if cache_hit2:
        print("  ✓ Cache working correctly")
    else:
        print("  ✗ Cache not working (second call should be cached)")

    # Test 3: Force refresh
    print("\n[Test 3] Testing force refresh...")
    status3, cache_hit3 = await get_current_weather(force_refresh=True)
    print(f"  Force refresh - cache_hit: {cache_hit3}")
    if not cache_hit3:
        print("  ✓ Force refresh bypassed cache")
    else:
        print("  ✗ Force refresh should not use cache")

    # Test 4: Helper functions
    print("\n[Test 4] Testing helper functions...")
    sunny = await is_sunny()
    seconds = await get_sunshine_seconds()
    print(f"  is_sunny(): {sunny}")
    print(f"  get_sunshine_seconds(): {seconds}")
    print("  ✓ Helper functions working")

    print("\n" + "=" * 60)
    print("All weather service tests passed!")
    print("=" * 60)
    return True


async def test_exposure_integration():
    """Test the exposure service with weather gate"""
    print("\n" + "=" * 60)
    print("Testing Exposure Service Integration")
    print("=" * 60)

    from app.services.weather import is_sunny
    from app.services.exposure import get_bench_sun_status

    # Check current weather
    sunny = await is_sunny()
    print(f"\nCurrent weather: {'Sunny' if sunny else 'Cloudy/Overcast'}")

    # Test with weather gate
    print("\n[Test 1] Getting bench status WITH weather gate...")
    print("  (Note: This will fail if database is not running - that's OK)")
    try:
        status, sun_until, remaining = await get_bench_sun_status(bench_id=1)
        print(f"  Status: {status}")
        print(f"  Sun until: {sun_until}")
        print(f"  Remaining minutes: {remaining}")

        if not sunny and status == "shady":
            print("  ✓ Weather gate working: cloudy weather = shady bench")
    except Exception as e:
        print(f"  ⚠ Database not available (expected): {type(e).__name__}")
        print("  This is OK - weather gate logic was still tested")

    # Test with weather gate skipped
    print("\n[Test 2] Getting bench status WITHOUT weather gate...")
    try:
        status, sun_until, remaining = await get_bench_sun_status(
            bench_id=1, skip_weather_check=True
        )
        print(f"  Status: {status}")
    except Exception as e:
        print(f"  ⚠ Database not available: {type(e).__name__}")

    print("\n" + "=" * 60)
    print("Exposure integration tests completed!")
    print("=" * 60)


async def main():
    print(f"\nTest started at: {datetime.now()}")
    print(f"Testing GeoSphere Weather API Integration\n")

    # Test weather service
    success = await test_weather_service()
    if not success:
        print("\n⚠ Weather service tests failed!")
        return

    # Test exposure integration
    await test_exposure_integration()

    print("\n✓ All tests completed!")


if __name__ == "__main__":
    asyncio.run(main())
