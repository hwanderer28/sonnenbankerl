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
    current_status: str = Field(..., description="Current sun status: sunny or shady")
    sun_until: Optional[datetime] = Field(None, description="Time until sun changes")
    remaining_minutes: Optional[int] = Field(None, description="Minutes until sun changes")


class BenchDetail(BenchBase):
    """Detailed bench information"""
    current_status: str = Field(..., description="Current sun status: sunny or shady")
    sun_until: Optional[datetime] = Field(None, description="Time until sun changes")
    remaining_minutes: Optional[int] = Field(None, description="Minutes until sun changes")
    created_at: Optional[datetime] = None


class BenchesResponse(BaseModel):
    """Response for benches list endpoint"""
    benches: list[BenchListItem]
