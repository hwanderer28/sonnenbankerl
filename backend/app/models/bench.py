from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class Location(BaseModel):
    """Geographic location"""
    lat: float = Field(..., description="Latitude")
    lon: float = Field(..., description="Longitude")


class BenchBase(BaseModel):
    """Base bench information"""
    id: int
    osm_id: Optional[int] = None
    name: Optional[str] = None
    location: Location
    elevation: Optional[float] = None


class BenchListItem(BenchBase):
    """Bench in list view with current status"""
    distance: float = Field(..., description="Distance from query point in meters")
    current_status: str = Field(..., description="Current sun status: sunny, shady, or unknown")
    sun_until: Optional[datetime] = Field(None, description="Time until sun changes")
    remaining_minutes: Optional[int] = Field(None, description="Minutes until sun changes")
    status_note: Optional[str] = Field(None, description="Additional status note when no change is within window")


class BenchDetail(BenchBase):
    """Detailed bench information"""
    current_status: str = Field(..., description="Current sun status: sunny, shady, or unknown")
    sun_until: Optional[datetime] = Field(None, description="Time until sun changes")
    remaining_minutes: Optional[int] = Field(None, description="Minutes until sun changes")
    status_note: Optional[str] = Field(None, description="Additional status note when no change is within window")
    created_at: Optional[datetime] = None


class BenchesResponse(BaseModel):
    """Response for benches list endpoint"""
    benches: list[BenchListItem]
    window_start: Optional[datetime] = Field(None, description="Start of available precomputed window")
    window_end: Optional[datetime] = Field(None, description="End of available precomputed window")
