# City of Weatherford — Fire & EMS Service Coverage Analysis

A network-based drive-time analysis of fire and EMS service coverage for the City of Weatherford, Texas. This project uses road network data from OpenStreetMap and Dijkstra's shortest-path algorithm to compute realistic emergency response zones, providing more accurate coverage estimates than traditional radius-based buffers. The analysis supports NFPA 1710 compliance evaluation and identifies coverage gaps as the city expands.

## Live Map

**[View Interactive Web Map](https://arcg.is/fGea5)**

---

## Project Contents

| File | Description |
|------|-------------|
| `analyze_coverage.py` | Python script for network-based drive-time analysis |
| `weatherford_gis_schema.sql` | Enterprise GIS database schema (SQL Server / ESRI SDE) |
| `weatherford_field_maps_spec.md` | ArcGIS Field Maps data specification |
| `weatherford_memo.pdf` | Analysis findings memo |
| `output_shapefiles/` | Generated shapefiles and GeoJSON files |

---

## Tools & Methods

**Python Libraries**
- OSMnx — Street network acquisition from OpenStreetMap
- NetworkX — Graph-based shortest path analysis
- GeoPandas — Spatial data manipulation
- Shapely — Geometric operations

**GIS Platforms**
- ArcGIS Online (ESRI) — Web map hosting and visualization
- QGIS — Desktop GIS analysis and cartography

**Database**
- SQL Server / ESRI SDE schema design

**Data Sources**
- OpenStreetMap — Road network topology
- US Census — City boundary reference

---

## Key Findings

- **5-minute coverage: 80.27% of city area** — Aligns with NFPA 1710 response time benchmarks for first-due engine arrival. Approximately 20% of the city falls outside this critical threshold.

- **10-minute coverage: 99.95% of city area** — Nearly complete coverage is achieved within 10 minutes, with only minor gaps at the periphery.

- **Primary coverage gap: NW growth corridor and US-180 W** — As residential development expands northwest and along US-180 West, these areas represent the most significant gaps in 5-minute response coverage.

---

## NFPA 1710 Reference

NFPA 1710 establishes a 4-minute travel time benchmark for the arrival of the first-due engine company, which departments are expected to meet 90% of the time for effective fire suppression and emergency medical response.

---

## Author

Henry Zhan

---

*This analysis was conducted independently as a portfolio project demonstrating GIS analysis capabilities for municipal public safety planning.*
