"""
Unit tests for the weather service with mocked API responses.

Run with:
    cd backend
    source venv/bin/activate
    pytest tests/test_weather_unit.py -v
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from datetime import datetime, timezone, timedelta
from aiohttp import ClientResponseError, ClientTimeout
import asyncio

import sys
sys.path.insert(0, ".")


# Sample API responses for mocking
def create_geosphere_response(sunshine_seconds: int, timestamp: str = "2026-01-12T12:00:00+00:00"):
    """Create a mock GeoSphere API response"""
    return {
        "type": "FeatureCollection",
        "timestamps": [timestamp],
        "features": [{
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [15.448889, 47.077778]
            },
            "properties": {
                "station": "11290",
                "parameters": {
                    "SO": {
                        "name": "Sonnenscheindauer",
                        "unit": "s",
                        "data": [sunshine_seconds]
                    }
                }
            }
        }]
    }


SUNNY_RESPONSE = create_geosphere_response(600)  # 10 minutes of sun (full sun)
CLOUDY_RESPONSE = create_geosphere_response(0)   # No sun
PARTIAL_SUN_RESPONSE = create_geosphere_response(180)  # 3 minutes of sun


def reset_weather_cache():
    """Reset the weather service cache between tests"""
    from app.services import weather
    weather._weather_cache = None
    weather._cache_time = None


@pytest.fixture(autouse=True)
def clear_cache():
    """Clear cache before each test"""
    reset_weather_cache()
    yield
    reset_weather_cache()


class MockResponse:
    """Mock aiohttp response"""
    def __init__(self, json_data, status=200):
        self._json_data = json_data
        self.status = status

    async def json(self):
        return self._json_data

    async def text(self):
        return str(self._json_data)

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass


class MockClientSession:
    """Mock aiohttp ClientSession"""
    def __init__(self, response):
        self._response = response

    def get(self, url, params=None, timeout=None):
        return self._response

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        pass


# =============================================================================
# Test: Sunny Detection (SO > 0)
# =============================================================================

@pytest.mark.asyncio
async def test_sunny_detection_full_sun():
    """Test that SO > 0 is detected as sunny"""
    from app.services.weather import fetch_weather_from_api

    mock_response = MockResponse(SUNNY_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        status = await fetch_weather_from_api()

    assert status.is_sunny is True
    assert status.sunshine_seconds == 600
    assert "Sunny conditions" in status.message


@pytest.mark.asyncio
async def test_sunny_detection_partial_sun():
    """Test that partial sunshine (SO > 0 but < 600) is detected as sunny"""
    from app.services.weather import fetch_weather_from_api

    mock_response = MockResponse(PARTIAL_SUN_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        status = await fetch_weather_from_api()

    assert status.is_sunny is True
    assert status.sunshine_seconds == 180
    assert "Partial sunshine" in status.message


# =============================================================================
# Test: Cloudy Detection (SO = 0)
# =============================================================================

@pytest.mark.asyncio
async def test_cloudy_detection():
    """Test that SO = 0 is detected as cloudy"""
    from app.services.weather import fetch_weather_from_api

    mock_response = MockResponse(CLOUDY_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        status = await fetch_weather_from_api()

    assert status.is_sunny is False
    assert status.sunshine_seconds == 0
    assert "Overcast" in status.message or "cloudy" in status.message


# =============================================================================
# Test: Cache Hit/Miss Behavior
# =============================================================================

@pytest.mark.asyncio
async def test_cache_miss_on_first_call():
    """Test that first call is a cache miss"""
    from app.services.weather import get_current_weather

    mock_response = MockResponse(SUNNY_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        status, cache_hit = await get_current_weather()

    assert cache_hit is False
    assert status.is_sunny is True


@pytest.mark.asyncio
async def test_cache_hit_on_second_call():
    """Test that second call within TTL is a cache hit"""
    from app.services.weather import get_current_weather

    mock_response = MockResponse(SUNNY_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        # First call - should miss cache
        status1, cache_hit1 = await get_current_weather()
        assert cache_hit1 is False

        # Second call - should hit cache
        status2, cache_hit2 = await get_current_weather()
        assert cache_hit2 is True

        # Data should be the same
        assert status1.is_sunny == status2.is_sunny
        assert status1.sunshine_seconds == status2.sunshine_seconds


@pytest.mark.asyncio
async def test_force_refresh_bypasses_cache():
    """Test that force_refresh=True bypasses the cache"""
    from app.services.weather import get_current_weather

    mock_response = MockResponse(SUNNY_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        # First call - populate cache
        await get_current_weather()

        # Force refresh - should bypass cache
        status, cache_hit = await get_current_weather(force_refresh=True)

    assert cache_hit is False


# =============================================================================
# Test: Cache Expiration After TTL
# =============================================================================

@pytest.mark.asyncio
async def test_cache_expires_after_ttl():
    """Test that cache expires after TTL"""
    from app.services import weather
    from app.services.weather import get_current_weather

    mock_response = MockResponse(SUNNY_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        # First call - populate cache
        await get_current_weather()

        # Manually set cache time to be expired (TTL + 1 second ago)
        weather._cache_time = datetime.now(timezone.utc) - timedelta(seconds=601)

        # This call should miss cache due to expiration
        status, cache_hit = await get_current_weather()

    assert cache_hit is False


@pytest.mark.asyncio
async def test_cache_valid_within_ttl():
    """Test that cache is valid within TTL window"""
    from app.services import weather
    from app.services.weather import get_current_weather, _is_cache_valid

    mock_response = MockResponse(SUNNY_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        # Populate cache
        await get_current_weather()

        # Set cache time to 5 minutes ago (within default 10min TTL)
        weather._cache_time = datetime.now(timezone.utc) - timedelta(seconds=300)

        assert _is_cache_valid() is True


# =============================================================================
# Test: API Timeout Handling
# =============================================================================

@pytest.mark.asyncio
async def test_api_timeout_with_stale_cache():
    """Test that API timeout returns stale cache if available"""
    from app.services import weather
    from app.services.weather import get_current_weather, fetch_weather_from_api
    from app.models.weather import WeatherStatus

    # Pre-populate cache with stale data
    stale_status = WeatherStatus(
        is_sunny=True,
        sunshine_seconds=300,
        station_id="11290",
        station_name="Graz Universitaet",
        timestamp=datetime.now(timezone.utc) - timedelta(hours=1),
        cached_at=datetime.now(timezone.utc) - timedelta(hours=1),
        message="Stale data"
    )
    weather._weather_cache = stale_status
    weather._cache_time = datetime.now(timezone.utc) - timedelta(hours=1)  # Expired

    # Mock API to raise timeout
    async def mock_fetch_timeout():
        raise asyncio.TimeoutError("API timeout")

    with patch("app.services.weather.fetch_weather_from_api", side_effect=mock_fetch_timeout):
        status, cache_hit = await get_current_weather()

    # Should return stale cache
    assert cache_hit is True
    assert status.is_sunny is True
    assert status.message == "Stale data"


@pytest.mark.asyncio
async def test_api_timeout_without_cache_raises():
    """Test that API timeout without cache raises exception"""
    from app.services.weather import get_current_weather

    async def mock_fetch_timeout():
        raise asyncio.TimeoutError("API timeout")

    with patch("app.services.weather.fetch_weather_from_api", side_effect=mock_fetch_timeout):
        with pytest.raises(asyncio.TimeoutError):
            await get_current_weather()


# =============================================================================
# Test: API Error Handling
# =============================================================================

@pytest.mark.asyncio
async def test_api_error_4xx():
    """Test handling of 4xx HTTP errors"""
    from app.services.weather import fetch_weather_from_api

    mock_response = MockResponse({"error": "Bad request"}, status=400)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        with pytest.raises(Exception, match="status 400"):
            await fetch_weather_from_api()


@pytest.mark.asyncio
async def test_api_error_5xx():
    """Test handling of 5xx HTTP errors"""
    from app.services.weather import fetch_weather_from_api

    mock_response = MockResponse({"error": "Internal server error"}, status=500)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        with pytest.raises(Exception, match="status 500"):
            await fetch_weather_from_api()


@pytest.mark.asyncio
async def test_api_error_returns_stale_cache():
    """Test that API errors return stale cache if available"""
    from app.services import weather
    from app.services.weather import get_current_weather
    from app.models.weather import WeatherStatus

    # Pre-populate cache
    stale_status = WeatherStatus(
        is_sunny=False,
        sunshine_seconds=0,
        station_id="11290",
        station_name="Graz Universitaet",
        timestamp=datetime.now(timezone.utc) - timedelta(hours=1),
        cached_at=datetime.now(timezone.utc) - timedelta(hours=1),
        message="Stale cloudy data"
    )
    weather._weather_cache = stale_status
    weather._cache_time = datetime.now(timezone.utc) - timedelta(hours=1)  # Expired

    # Mock API error
    async def mock_fetch_error():
        raise Exception("API unavailable")

    with patch("app.services.weather.fetch_weather_from_api", side_effect=mock_fetch_error):
        status, cache_hit = await get_current_weather()

    assert cache_hit is True
    assert status.is_sunny is False


@pytest.mark.asyncio
async def test_invalid_response_format():
    """Test handling of invalid API response format"""
    from app.services.weather import fetch_weather_from_api

    invalid_response = {"unexpected": "format"}
    mock_response = MockResponse(invalid_response)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        with pytest.raises(Exception, match="Failed to parse"):
            await fetch_weather_from_api()


@pytest.mark.asyncio
async def test_missing_sunshine_data():
    """Test handling of response with missing SO data"""
    from app.services.weather import fetch_weather_from_api

    response_no_data = {
        "type": "FeatureCollection",
        "timestamps": ["2026-01-12T12:00:00+00:00"],
        "features": [{
            "type": "Feature",
            "properties": {
                "station": "11290",
                "parameters": {
                    "SO": {
                        "name": "Sonnenscheindauer",
                        "unit": "s",
                        "data": []  # Empty data array
                    }
                }
            }
        }]
    }

    mock_response = MockResponse(response_no_data)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        with pytest.raises(Exception, match="No sunshine data"):
            await fetch_weather_from_api()


# =============================================================================
# Test: Helper Functions
# =============================================================================

@pytest.mark.asyncio
async def test_is_sunny_helper_returns_true():
    """Test is_sunny() helper returns True when sunny"""
    from app.services.weather import is_sunny

    mock_response = MockResponse(SUNNY_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        result = await is_sunny()

    assert result is True


@pytest.mark.asyncio
async def test_is_sunny_helper_returns_false():
    """Test is_sunny() helper returns False when cloudy"""
    from app.services.weather import is_sunny

    mock_response = MockResponse(CLOUDY_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        result = await is_sunny()

    assert result is False


@pytest.mark.asyncio
async def test_is_sunny_helper_returns_false_on_error():
    """Test is_sunny() helper returns False on API error (conservative default)"""
    from app.services.weather import is_sunny

    async def mock_fetch_error():
        raise Exception("API error")

    with patch("app.services.weather.fetch_weather_from_api", side_effect=mock_fetch_error):
        result = await is_sunny()

    assert result is False


@pytest.mark.asyncio
async def test_get_sunshine_seconds_helper():
    """Test get_sunshine_seconds() helper"""
    from app.services.weather import get_sunshine_seconds

    mock_response = MockResponse(SUNNY_RESPONSE)
    mock_session = MockClientSession(mock_response)

    with patch("aiohttp.ClientSession", return_value=mock_session):
        result = await get_sunshine_seconds()

    assert result == 600


@pytest.mark.asyncio
async def test_get_sunshine_seconds_returns_zero_on_error():
    """Test get_sunshine_seconds() returns 0 on error"""
    from app.services.weather import get_sunshine_seconds

    async def mock_fetch_error():
        raise Exception("API error")

    with patch("app.services.weather.fetch_weather_from_api", side_effect=mock_fetch_error):
        result = await get_sunshine_seconds()

    assert result == 0


# =============================================================================
# Test: Exposure Service Integration with Weather Gate
# =============================================================================

@pytest.mark.asyncio
async def test_exposure_returns_shady_when_cloudy():
    """Test that exposure service returns 'shady' when weather is cloudy"""
    from app.services.exposure import get_bench_sun_status
    from app.services import weather

    # Mock weather to return cloudy
    async def mock_is_sunny():
        return False

    with patch("app.services.exposure.check_weather_sunny", side_effect=mock_is_sunny):
        status, sun_until, remaining = await get_bench_sun_status(bench_id=1)

    assert status == "shady"
    assert sun_until is None
    assert remaining is None


@pytest.mark.asyncio
async def test_exposure_skips_weather_check_when_requested():
    """Test that skip_weather_check=True bypasses weather gate"""
    from app.services.exposure import get_bench_sun_status

    # Mock the database query to return exposed=True
    async def mock_get_exposure(bench_id, time):
        return True

    async def mock_get_next_change(bench_id, time, exposed):
        return None

    with patch("app.services.exposure.get_current_exposure", side_effect=mock_get_exposure):
        with patch("app.services.exposure.get_next_sun_change", side_effect=mock_get_next_change):
            status, sun_until, remaining = await get_bench_sun_status(
                bench_id=1, skip_weather_check=True
            )

    # Should return sunny based on DB, not blocked by weather
    assert status == "sunny"


@pytest.mark.asyncio
async def test_exposure_queries_db_when_sunny():
    """Test that exposure service queries DB when weather is sunny"""
    from app.services.exposure import get_bench_sun_status

    # Mock weather to return sunny
    async def mock_is_sunny():
        return True

    # Mock DB to return bench is shaded
    async def mock_get_exposure(bench_id, time):
        return False

    async def mock_get_next_change(bench_id, time, exposed):
        return datetime.utcnow() + timedelta(hours=1)

    with patch("app.services.exposure.check_weather_sunny", side_effect=mock_is_sunny):
        with patch("app.services.exposure.get_current_exposure", side_effect=mock_get_exposure):
            with patch("app.services.exposure.get_next_sun_change", side_effect=mock_get_next_change):
                status, sun_until, remaining = await get_bench_sun_status(bench_id=1)

    # Should return shady based on DB query (bench not exposed despite sunny weather)
    assert status == "shady"
    assert sun_until is not None


# =============================================================================
# Test: Status Message Generation
# =============================================================================

@pytest.mark.asyncio
async def test_status_message_full_sun():
    """Test status message for full sunshine (>= 10 min)"""
    from app.services.weather import _create_status_message

    message = _create_status_message(is_sunny=True, sunshine_seconds=600)
    assert "Sunny conditions" in message


@pytest.mark.asyncio
async def test_status_message_partial_sun():
    """Test status message for partial sunshine (< 10 min)"""
    from app.services.weather import _create_status_message

    message = _create_status_message(is_sunny=True, sunshine_seconds=180)
    assert "Partial sunshine" in message
    assert "3 min" in message


@pytest.mark.asyncio
async def test_status_message_cloudy():
    """Test status message for cloudy conditions"""
    from app.services.weather import _create_status_message

    message = _create_status_message(is_sunny=False, sunshine_seconds=0)
    assert "Overcast" in message or "cloudy" in message


# =============================================================================
# Test: Station Name Mapping
# =============================================================================

@pytest.mark.asyncio
async def test_station_name_mapping():
    """Test that station names are correctly mapped"""
    from app.services.weather import STATION_NAMES

    assert STATION_NAMES["11290"] == "Graz Universitaet"
    assert STATION_NAMES["11240"] == "Graz-Thalerhof-Flughafen"


@pytest.mark.asyncio
async def test_unknown_station_gets_default_name():
    """Test that unknown station ID gets a default name"""
    from app.services.weather import fetch_weather_from_api
    from app.config import settings

    # Create response with unknown station
    response = create_geosphere_response(360)

    mock_response = MockResponse(response)
    mock_session = MockClientSession(mock_response)

    # Temporarily change station ID to unknown
    original_station = settings.geosphere_station_id

    with patch("aiohttp.ClientSession", return_value=mock_session):
        with patch.object(settings, "geosphere_station_id", "99999"):
            status = await fetch_weather_from_api()

    assert "99999" in status.station_name or "Station" in status.station_name
