#!/usr/bin/env python3
"""
Test script for Sonnenbankerl API
"""
import requests
import json

BASE_URL = "https://sonnenbankerl.ideanexus.cloud"

def test_health():
    """Test health endpoint"""
    print("🔍 Testing health endpoint...")
    response = requests.get(f"{BASE_URL}/api/health")
    print(f"Status: {response.status_code}")
    print(json.dumps(response.json(), indent=2))
    print()

def get_benches(lat, lon, radius=1000):
    """Get benches near a location"""
    print(f"🪑 Fetching benches near ({lat}, {lon}) within {radius}m...")
    response = requests.get(
        f"{BASE_URL}/api/benches",
        params={"lat": lat, "lon": lon, "radius": radius}
    )
    print(f"Status: {response.status_code}")
    data = response.json()
    print(f"Found {len(data['benches'])} benches:")
    for bench in data['benches']:
        print(f"  - {bench['name']} ({bench['distance']:.1f}m away)")
        print(f"    Location: {bench['location']['lat']}, {bench['location']['lon']}")
        print(f"    Status: {bench['current_status']}")
    print()
    return data

def get_bench_details(bench_id):
    """Get details for a specific bench"""
    print(f"🔍 Fetching details for bench {bench_id}...")
    response = requests.get(f"{BASE_URL}/api/benches/{bench_id}")
    print(f"Status: {response.status_code}")
    print(json.dumps(response.json(), indent=2))
    print()

if __name__ == "__main__":
    # Test health
    test_health()
    
    # Get benches near Graz center
    benches = get_benches(lat=47.07, lon=15.44, radius=1000)
    
    # Get details for first bench
    if benches['benches']:
        bench_id = benches['benches'][0]['id']
        get_bench_details(bench_id)
    
    # Test with different location (should return empty)
    print("🔍 Testing with Vienna coordinates (should be empty)...")
    benches_vienna = get_benches(lat=48.2082, lon=16.3738, radius=1000)
