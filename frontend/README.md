# Frontend Test Page

A minimal Leaflet + MapTiler page for testing bench exposure data locally.

## Usage

```bash
cd frontend
python -m http.server 3000
# Open http://localhost:3000 in your browser
```

- Map: MapTiler toner-v2 (API key already in `index.html`).
- API target: `http://localhost:8000` (make sure backend is running and exposure data is computed).
- Markers: yellow = sunny, blue = shady; popups show sun status, `sun_until`, and `remaining_minutes` after clicking.

## Prerequisites
- Backend running on `localhost:8000`.
- Benches imported and exposure pipeline executed (run `compute_next_week.sh`).

## Notes
- If you see CORS issues when opening `index.html` directly, serve via `python -m http.server` as above.
- The map centers on Graz Stadtpark, where the current 21 benches are located.
