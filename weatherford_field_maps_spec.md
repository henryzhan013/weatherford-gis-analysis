# Field Maps Data Spec — Weatherford Fire/EMS

Data layers for ArcGIS Field Maps mobile app.

## Layers

| Layer | Type | Update Frequency |
|-------|------|------------------|
| fire_response_zones | Polygon | Quarterly |
| fire_stations | Point | As needed |

## fire_stations fields

| Field | Type | Example |
|-------|------|---------|
| name | Text | Station 1 Central |
| address | Text | 122 S Alamo St |
| station_type | Text | Fire + EMS |
| units | Integer | 6 |
| is_active | Boolean | True |

## fire_response_zones fields

| Field | Type | Example |
|-------|------|---------|
| zone_type | Text | 5-min Response |
| drive_time_minutes | Integer | 5 |
| coverage_pct | Decimal | 80.25 |
| last_updated | Date | 2026-03-01 |

## Usage notes

- Tap any location to see which response zone covers it
- Use Identify tool to check if an address falls within 5-minute coverage
- Don't edit data in the field — report issues through proper channels
