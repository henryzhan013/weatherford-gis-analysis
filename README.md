# Weatherford Fire/EMS Coverage Analysis

Network-based drive-time analysis for the City of Weatherford, TX fire department. Uses actual road network data from OpenStreetMap to calculate realistic emergency response zones (5, 10, 15 minute drive times), rather than simple radius buffers.

**[Live Map](https://arcg.is/Hv00m6)**

## What's here

- `analyze_coverage.py` — main analysis script
- `weatherford_gis_schema.sql` — database schema for SQL Server/SDE
- `weatherford_field_maps_spec.md` — Field Maps data spec
- `output_shapefiles/` — generated shapefiles
- `weatherford_coverage.geojson` — combined output for web mapping

## Tools used

- Python (OSMnx, NetworkX, GeoPandas)
- ArcGIS Online
- QGIS
- OpenStreetMap data

## Results

| Zone | Coverage |
|------|----------|
| 5-min | 95.39% |
| 10-min | 100% |
| 15-min | 100% |

With 4 stations, about 95% of the city is within 5-minute response coverage.

## Running it

```bash
pip install -r requirements.txt
python analyze_coverage.py
```

Takes a couple minutes to download the street network and run the analysis.
