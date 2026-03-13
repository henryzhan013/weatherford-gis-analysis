/*
Weatherford GIS Database Schema
For SQL Server / ESRI SDE

Tables for fire station locations, response zones, parcels, and incidents.
*/

USE WeatherfordGIS;
GO

-- Fire/EMS station locations
CREATE TABLE fire_stations (
    station_id          INT PRIMARY KEY IDENTITY(1,1),
    name                NVARCHAR(100) NOT NULL,
    address             NVARCHAR(200),
    city                NVARCHAR(50) DEFAULT 'Weatherford',
    state               CHAR(2) DEFAULT 'TX',
    lat                 DECIMAL(10, 7) NOT NULL,
    lon                 DECIMAL(11, 7) NOT NULL,
    station_type        NVARCHAR(50) NOT NULL,
    units               INT DEFAULT 0,
    is_active           BIT DEFAULT 1,
    date_established    DATE
);
GO

-- Drive-time response zones (geometry stored in SDE feature class)
CREATE TABLE fire_response_zones (
    zone_id             INT PRIMARY KEY IDENTITY(1,1),
    station_id          INT NOT NULL REFERENCES fire_stations(station_id),
    zone_type           NVARCHAR(50) NOT NULL,
    drive_time_minutes  INT NOT NULL,
    area_sqkm           DECIMAL(10, 4),
    coverage_pct        DECIMAL(5, 2),
    last_updated        DATETIME DEFAULT GETDATE()
);
GO

-- City parcels (synced from county appraisal district)
CREATE TABLE city_parcels (
    parcel_id           NVARCHAR(30) PRIMARY KEY,
    address             NVARCHAR(200),
    owner_name          NVARCHAR(200),
    land_use_code       NVARCHAR(10),
    zoning              NVARCHAR(20),
    acreage             DECIMAL(12, 4),
    assessed_value      DECIMAL(14, 2),
    centroid_lat        DECIMAL(10, 7),
    centroid_lon        DECIMAL(11, 7),
    last_updated        DATETIME DEFAULT GETDATE()
);
GO

CREATE INDEX IX_parcels_land_use ON city_parcels(land_use_code);
CREATE INDEX IX_parcels_zoning ON city_parcels(zoning);
GO

-- Incident records from CAD system
CREATE TABLE incidents (
    incident_id         NVARCHAR(20) PRIMARY KEY,
    station_id          INT REFERENCES fire_stations(station_id),
    incident_type       NVARCHAR(50) NOT NULL,
    priority            INT DEFAULT 3,
    response_time_sec   INT,
    travel_time_sec     INT,
    address             NVARCHAR(200),
    lat                 DECIMAL(10, 7),
    lon                 DECIMAL(11, 7),
    incident_date       DATETIME NOT NULL,
    resolved            BIT DEFAULT 0
);
GO

CREATE INDEX IX_incidents_date ON incidents(incident_date);
CREATE INDEX IX_incidents_station ON incidents(station_id);
GO


-- Sample data: Weatherford fire stations
INSERT INTO fire_stations (name, address, city, state, lat, lon, station_type, units, is_active, date_established)
VALUES
    ('Station 1 Central', '122 S Alamo St', 'Weatherford', 'TX', 32.7582, -97.8005, 'Fire + EMS', 6, 1, '1985-01-01'),
    ('Station 2 East Side', '150 N Oakridge Dr', 'Hudson Oaks', 'TX', 32.7544, -97.6991, 'Fire + EMS', 4, 1, '1998-06-15'),
    ('Station 3', '122 Atwood Court', 'Weatherford', 'TX', 32.7468, -97.7441, 'Fire + EMS', 2, 1, '2012-03-01'),
    ('Station 4 West Park', '905 West Park Ave', 'Weatherford', 'TX', 32.7590, -97.8150, 'Fire + EMS', 2, 1, '2020-01-01');
GO

-- Sample response zones
INSERT INTO fire_response_zones (station_id, zone_type, drive_time_minutes, area_sqkm, coverage_pct)
VALUES
    (1, '5-min Response', 5, 18.5, 25.66),
    (1, '10-min Response', 10, 42.3, 58.68),
    (1, '15-min Response', 15, 68.2, 94.60),
    (2, '5-min Response', 5, 15.2, 21.08),
    (2, '10-min Response', 10, 38.7, 53.68),
    (2, '15-min Response', 15, 65.4, 90.72),
    (3, '5-min Response', 5, 12.8, 17.75),
    (3, '10-min Response', 10, 35.2, 48.83),
    (3, '15-min Response', 15, 62.1, 86.14),
    (4, '5-min Response', 5, 14.2, 19.70),
    (4, '10-min Response', 10, 36.8, 51.05),
    (4, '15-min Response', 15, 63.5, 88.08);
GO


/* ===== QUERIES ===== */

-- Avg response time by station (last 12 months)
SELECT
    fs.name,
    COUNT(*) as incidents,
    AVG(i.response_time_sec) as avg_response_sec,
    AVG(i.response_time_sec) / 60.0 as avg_response_min
FROM fire_stations fs
LEFT JOIN incidents i ON fs.station_id = i.station_id
    AND i.incident_date >= DATEADD(MONTH, -12, GETDATE())
WHERE fs.is_active = 1
GROUP BY fs.station_id, fs.name;
GO

-- Incidents by type per station
SELECT
    fs.name,
    i.incident_type,
    COUNT(*) as count
FROM fire_stations fs
JOIN incidents i ON fs.station_id = i.station_id
WHERE i.incident_date >= DATEADD(YEAR, -1, GETDATE())
GROUP BY fs.station_id, fs.name, i.incident_type
ORDER BY fs.name, count DESC;
GO

-- Stations below NFPA 4-min travel time benchmark (should be 90%+)
SELECT
    fs.name,
    COUNT(*) as total,
    SUM(CASE WHEN i.travel_time_sec <= 240 THEN 1 ELSE 0 END) as within_4min,
    CAST(SUM(CASE WHEN i.travel_time_sec <= 240 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) as compliance_pct
FROM fire_stations fs
JOIN incidents i ON fs.station_id = i.station_id
WHERE i.travel_time_sec IS NOT NULL
    AND i.incident_date >= DATEADD(MONTH, -12, GETDATE())
GROUP BY fs.station_id, fs.name
HAVING SUM(CASE WHEN i.travel_time_sec <= 240 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) < 90;
GO
