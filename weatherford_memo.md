# MEMORANDUM

| | |
|:--|:--|
| **TO:** | GIS Coordinator, City of Weatherford |
| **FROM:** | Henry Zhan |
| **DATE:** | March 13, 2026 |
| **RE:** | Preliminary Fire & EMS Service Coverage Analysis — City of Weatherford |

---

## OVERVIEW

As part of my application for the GIS Analyst position, I conducted an independent analysis of fire and EMS service coverage for the City of Weatherford. This memo summarizes my methodology, key findings, and deliverables to demonstrate my technical capabilities and initiative.

## METHODOLOGY

I performed a network-based drive-time analysis using Python (OSMnx, NetworkX, GeoPandas) to compute 5, 10, and 15-minute service areas from each of the three fire stations. Unlike simple radius buffers, this approach uses actual road network topology and travel times derived from OpenStreetMap data, providing a more accurate representation of emergency response coverage. Results were validated against the city boundary and published to ArcGIS Online for interactive visualization.

## KEY FINDINGS

- **5-minute coverage: 80.27% of city area** — This aligns with NFPA 1710 response time benchmarks for first-due engine arrival. Approximately 20% of the city falls outside this critical threshold.

- **10-minute coverage: 99.95% of city area** — Nearly complete coverage is achieved within 10 minutes, with only minor gaps at the periphery.

- **Primary coverage gap: NW growth corridor and US-180 W** — As residential development expands northwest and along US-180 West, these areas represent the most significant gaps in 5-minute response coverage and warrant monitoring.

## RECOMMENDATIONS

- **Monitor NW growth corridor** — As new residential subdivisions are platted beyond the current 5-minute coverage zone, evaluate the need for station deployment or apparatus repositioning to maintain NFPA compliance.

- **Rerun analysis quarterly** — The Python script is fully automated and repeatable. I recommend re-executing the analysis each quarter as new parcels are added to identify emerging coverage gaps before they become critical.

## DELIVERABLES

- Interactive web map (ArcGIS Online): [https://arcg.is/fGea5](https://arcg.is/fGea5)
- SQL database schema: `weatherford_gis_schema.sql`
- Field Maps data specification: `weatherford_field_maps_spec.md`
- Python analysis script: `analyze_coverage.py` — fully documented and repeatable

## CLOSING

I would welcome the opportunity to walk through my methodology and findings in person at your convenience.

---

*Henry Zhan*
