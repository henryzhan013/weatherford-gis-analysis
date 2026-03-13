# City of Weatherford Fire & EMS — Field Maps Data Specification

| | |
|---|---|
| **Prepared by** | GIS Division, City of Weatherford |
| **Date** | March 2026 |
| **Version** | 1.0 |

---

## Purpose

This document defines the GIS data layers and field schemas deployed to ArcGIS Field Maps for use by Weatherford Fire Department field personnel. It serves as a reference for understanding available map data, field definitions, and data stewardship contacts.

---

## Layer Summary

| Layer Name | Feature Type | Coordinate System | Update Frequency | Description |
|------------|--------------|-------------------|------------------|-------------|
| fire_response_zones | Polygon | WGS 1984 (EPSG:4326) | Quarterly | Drive-time service area polygons representing 5, 10, and 15-minute emergency response coverage zones |
| fire_stations | Point | WGS 1984 (EPSG:4326) | As needed | Locations of active fire/EMS stations with apparatus and contact information |

---

## Field Schema: fire_stations

| Field Name | Data Type | Description | Example Value |
|------------|-----------|-------------|---------------|
| name | Text (100) | Station name and identifier | Station 1 Central |
| address | Text (200) | Street address of the station | 122 S Alamo St |
| station_type | Text (50) | Service type provided | Fire + EMS |
| units | Integer | Number of apparatus assigned | 6 |
| is_active | Boolean | Indicates if station is operational | True |

---

## Field Schema: fire_response_zones

| Field Name | Data Type | Description | Example Value |
|------------|-----------|-------------|---------------|
| zone_type | Text (50) | Response time classification | 5-min Response |
| drive_time_minutes | Integer | Drive time threshold in minutes | 5 |
| coverage_pct | Decimal | Percentage of city area covered | 80.25 |
| last_updated | Date | Date of last zone recalculation | 2026-03-01 |

---

## Usage Notes

- **Identifying your response zone:** Tap any location on the map to see which response zone(s) cover that area. The zone_type field indicates the expected drive time from the nearest station.

- **Coverage questions:** If a resident or business inquires about their coverage status, use the Identify tool to check if their address falls within a 5-minute response zone. For addresses outside coverage, document the location and notify the Battalion Chief.

- **Data issues:** If you encounter incorrect station information, missing zones, or map display problems, contact the GIS Division immediately using the information below. Do not attempt to edit feature data in the field.

---

## Data Contacts

| Role | Name | Email |
|------|------|-------|
| GIS Analyst | Henry Zhan | hzhan@weatherfordtx.gov |
| GIS Coordinator | TBD | gis@weatherfordtx.gov |

---

*This data package is maintained by the City of Weatherford GIS Division and published to ArcGIS Online for Field Maps consumption. For technical issues with the Field Maps application, contact Esri Support or the GIS Coordinator.*
