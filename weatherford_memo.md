# Fire/EMS Coverage Analysis — Weatherford, TX

## Overview

I put together this analysis as part of my application for the GIS Analyst position. It looks at fire and EMS response coverage across the city using network-based drive time calculations.

## Methodology

Used Python (OSMnx, NetworkX, GeoPandas) to compute 5, 10, and 15-minute service areas from each fire station. Unlike simple radius buffers, this uses actual road network data from OpenStreetMap to estimate realistic drive times. Results published to ArcGIS Online.

## Findings

- **5-minute coverage: 80.27%** — Roughly 20% of the city is outside the 5-minute threshold (NFPA 1710 benchmark)
- **10-minute coverage: 99.95%** — Nearly full coverage
- **Coverage gaps at periphery** — The areas outside 5-minute coverage are mostly along the outer edges of the city

## Recommendations

- **Monitor new development** — Keep an eye on subdivisions being built in areas outside current 5-minute coverage
- **Rerun quarterly** — The script is automated and repeatable, easy to re-run as the city grows

## Deliverables

- Web map: https://arcg.is/fGea5
- Database schema: `weatherford_gis_schema.sql`
- Field Maps spec: `weatherford_field_maps_spec.md`
- Analysis script: `analyze_coverage.py`
