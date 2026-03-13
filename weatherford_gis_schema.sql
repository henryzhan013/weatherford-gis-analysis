/*
================================================================================
CITY OF WEATHERFORD, TEXAS - ENTERPRISE GIS DATABASE SCHEMA
================================================================================

Database:       SQL Server 2019+ with ESRI ArcSDE Geodatabase
Purpose:        Municipal GIS data management for Public Safety, Planning,
                and Emergency Response analysis
Author:         GIS Division - City of Weatherford
Created:        2024
Last Modified:  2024

NOTES:
- This schema integrates with ESRI's ArcGIS Enterprise geodatabase
- Geometry columns use SQL Server's native GEOMETRY type for SDE compatibility
- All spatial data uses EPSG:4326 (WGS 84) for web map interoperability
- Tables are designed for use with ArcGIS Pro, ArcGIS Online, and Experience Builder

================================================================================
*/

USE WeatherfordGIS;
GO

-- ============================================================================
-- SECTION 1: CORE INFRASTRUCTURE TABLES
-- ============================================================================
-- These tables form the backbone of the Public Safety GIS system.
-- Fire station locations and response zones are critical for:
--   - Emergency dispatch routing
--   - ISO fire rating calculations
--   - NFPA 1710 compliance reporting
--   - Capital improvement planning
-- ============================================================================

/*
------------------------------------------------------------------------------
TABLE: fire_stations
------------------------------------------------------------------------------
Purpose: Master table of all fire/EMS station locations in the city.
         Serves as the authoritative source for station attributes and
         is linked to response zones, incidents, and personnel tables.

Business Rules:
- Each station has a unique station_id (primary key)
- station_type indicates service capabilities (Fire, EMS, or Fire + EMS)
- is_active flag allows for tracking of planned/decommissioned stations
- Coordinates are stored for geocoding and spatial joins
------------------------------------------------------------------------------
*/
CREATE TABLE fire_stations (
    station_id          INT PRIMARY KEY IDENTITY(1,1),
    name                NVARCHAR(100) NOT NULL,
    address             NVARCHAR(200) NULL,
    city                NVARCHAR(50) DEFAULT 'Weatherford',
    state               CHAR(2) DEFAULT 'TX',
    lat                 DECIMAL(10, 7) NOT NULL,
    lon                 DECIMAL(11, 7) NOT NULL,
    station_type        NVARCHAR(50) NOT NULL
                        CHECK (station_type IN ('Fire', 'EMS', 'Fire + EMS')),
    units               INT DEFAULT 0,
    is_active           BIT DEFAULT 1,
    date_established    DATE NULL,

    -- Metadata for data governance
    created_date        DATETIME DEFAULT GETDATE(),
    created_by          NVARCHAR(50) DEFAULT SYSTEM_USER,
    modified_date       DATETIME NULL,
    modified_by         NVARCHAR(50) NULL
);
GO

-- Add spatial index hint for ArcSDE registration
EXEC sp_addextendedproperty
    @name = N'SDE_SPATIAL_INDEX',
    @value = N'ENABLED',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE', @level1name = N'fire_stations';
GO


/*
------------------------------------------------------------------------------
TABLE: fire_response_zones
------------------------------------------------------------------------------
Purpose: Stores drive-time service area polygons for each fire station.
         These zones are generated from network analysis using OSM road data
         and represent estimated emergency response coverage areas.

Business Rules:
- zone_type corresponds to NFPA 1710 response time standards:
    - 4-minute: NFPA 1710 benchmark for first engine arrival
    - 5-minute: Common municipal planning standard
    - 10-minute: Extended coverage analysis
    - 15-minute: Maximum acceptable response for ISO ratings
- coverage_pct indicates what percentage of city area this zone covers
- Zones are regenerated quarterly or when road network changes significantly
------------------------------------------------------------------------------
*/
CREATE TABLE fire_response_zones (
    zone_id             INT PRIMARY KEY IDENTITY(1,1),
    station_id          INT NOT NULL,
    zone_type           NVARCHAR(50) NOT NULL,
    drive_time_minutes  INT NOT NULL,
    area_sqkm           DECIMAL(10, 4) NULL,
    coverage_pct        DECIMAL(5, 2) NULL,
    last_updated        DATETIME DEFAULT GETDATE(),

    -- Geometry column for ArcSDE feature class
    -- Stored as WKT or managed by SDE; actual geometry in SDE feature class
    shape_area          DECIMAL(18, 6) NULL,
    shape_length        DECIMAL(18, 6) NULL,

    CONSTRAINT FK_response_zones_station
        FOREIGN KEY (station_id) REFERENCES fire_stations(station_id),

    CONSTRAINT CHK_drive_time
        CHECK (drive_time_minutes IN (4, 5, 10, 15))
);
GO


/*
------------------------------------------------------------------------------
TABLE: city_parcels
------------------------------------------------------------------------------
Purpose: Parcel fabric representing all land parcels within city limits.
         This table is synchronized nightly with Parker County Appraisal
         District (PCAD) data and serves as the foundation for:
         - Land use planning and zoning analysis
         - Emergency response coverage gap analysis
         - Growth impact studies
         - Property notification for public hearings

Business Rules:
- parcel_id matches PCAD's unique parcel identifier
- land_use_code follows Texas Comptroller's property classification
- zoning reflects current City of Weatherford zoning ordinance codes
------------------------------------------------------------------------------
*/
CREATE TABLE city_parcels (
    parcel_id           NVARCHAR(30) PRIMARY KEY,
    address             NVARCHAR(200) NULL,
    owner_name          NVARCHAR(200) NULL,
    land_use_code       NVARCHAR(10) NULL,
    land_use_desc       NVARCHAR(100) NULL,
    zoning              NVARCHAR(20) NULL,
    acreage             DECIMAL(12, 4) NULL,
    assessed_value      DECIMAL(14, 2) NULL,
    year_built          INT NULL,

    -- Spatial reference fields
    centroid_lat        DECIMAL(10, 7) NULL,
    centroid_lon        DECIMAL(11, 7) NULL,

    -- Data lineage
    last_updated        DATETIME DEFAULT GETDATE(),
    pcad_sync_date      DATETIME NULL,

    -- Flags for planning analysis
    is_residential      AS CASE
                            WHEN land_use_code LIKE 'A%'
                              OR land_use_code LIKE 'B%'
                            THEN 1 ELSE 0
                         END PERSISTED,
    is_commercial       AS CASE
                            WHEN land_use_code LIKE 'F%'
                              OR land_use_code LIKE 'L%'
                            THEN 1 ELSE 0
                         END PERSISTED
);
GO

-- Index for common query patterns
CREATE INDEX IX_parcels_land_use ON city_parcels(land_use_code);
CREATE INDEX IX_parcels_zoning ON city_parcels(zoning);
CREATE INDEX IX_parcels_updated ON city_parcels(last_updated);
GO


/*
------------------------------------------------------------------------------
TABLE: incidents
------------------------------------------------------------------------------
Purpose: Fire and EMS incident response records for performance analysis.
         Data is imported from the CAD (Computer-Aided Dispatch) system
         and geocoded for spatial analysis.

Business Rules:
- incident_id matches CAD system's unique identifier
- response_time_sec is measured from dispatch to on-scene arrival
- Coordinates are geocoded from incident address
- Used for NFPA 1710 compliance reporting and station deployment analysis

NFPA 1710 Standards Reference:
- Turnout time: 60-80 seconds
- Travel time (first engine): 240 seconds (4 minutes)
- Total response time target: 320 seconds (5:20)
------------------------------------------------------------------------------
*/
CREATE TABLE incidents (
    incident_id         NVARCHAR(20) PRIMARY KEY,
    station_id          INT NULL,
    incident_type       NVARCHAR(50) NOT NULL,
    incident_subtype    NVARCHAR(100) NULL,
    priority            INT DEFAULT 3 CHECK (priority BETWEEN 1 AND 5),

    -- Response metrics (in seconds for precision)
    dispatch_time_sec   INT NULL,
    turnout_time_sec    INT NULL,
    travel_time_sec     INT NULL,
    response_time_sec   INT NULL,  -- Total: dispatch + turnout + travel

    -- Location
    address             NVARCHAR(200) NULL,
    lat                 DECIMAL(10, 7) NULL,
    lon                 DECIMAL(11, 7) NULL,

    -- Timestamps
    incident_date       DATETIME NOT NULL,
    dispatched_at       DATETIME NULL,
    arrived_at          DATETIME NULL,
    cleared_at          DATETIME NULL,

    -- Status
    resolved            BIT DEFAULT 0,

    CONSTRAINT FK_incidents_station
        FOREIGN KEY (station_id) REFERENCES fire_stations(station_id)
);
GO

-- Indexes for temporal and spatial queries
CREATE INDEX IX_incidents_date ON incidents(incident_date);
CREATE INDEX IX_incidents_station ON incidents(station_id);
CREATE INDEX IX_incidents_type ON incidents(incident_type);
GO


-- ============================================================================
-- SECTION 2: SAMPLE DATA - WEATHERFORD FIRE STATIONS
-- ============================================================================
-- Insert the three primary fire stations serving Weatherford, TX.
-- These locations are used for response zone analysis and coverage mapping.
--
-- Apparatus Inventory:
--   Station 1: Engine 1, Truck 1, Squad 1, Brush 1, Tanker 1, Battalion Chief
--   Station 2: Engine 2, Brush 2, Boat 1, ATV
--   Station 3: Engine 3, Brush 3
-- ============================================================================

INSERT INTO fire_stations
    (name, address, city, state, lat, lon, station_type, units, is_active, date_established)
VALUES
    ('Station 1 Central',
     '122 S Alamo St',
     'Weatherford', 'TX',
     32.7577280, -97.8006822,
     'Fire + EMS',
     6,      -- Engine 1, Truck 1, Squad 1, Brush 1, Tanker 1, Battalion Chief
     1,      -- Active
     '1985-01-01'),

    ('Station 2 East Side',
     '150 N Oakridge Dr',
     'Hudson Oaks', 'TX',
     32.7545750, -97.7122169,
     'Fire + EMS',
     4,      -- Engine 2, Brush 2, Boat 1, ATV
     1,      -- Active
     '1998-06-15'),

    ('Station 3 West',
     '122 Atwood Court',
     'Weatherford', 'TX',
     32.7452730, -97.7428256,
     'Fire + EMS',
     2,      -- Engine 3, Brush 3
     1,      -- Active
     '2012-03-01');
GO

-- Insert response zone records (geometry managed separately in SDE)
INSERT INTO fire_response_zones
    (station_id, zone_type, drive_time_minutes, area_sqkm, coverage_pct, last_updated)
VALUES
    -- Station 1 Central zones
    (1, '5-min Response', 5, 18.5, 25.66, GETDATE()),
    (1, '10-min Response', 10, 42.3, 58.68, GETDATE()),
    (1, '15-min Response', 15, 68.2, 94.60, GETDATE()),

    -- Station 2 East Side zones
    (2, '5-min Response', 5, 15.2, 21.08, GETDATE()),
    (2, '10-min Response', 10, 38.7, 53.68, GETDATE()),
    (2, '15-min Response', 15, 65.4, 90.72, GETDATE()),

    -- Station 3 West zones
    (3, '5-min Response', 5, 12.8, 17.75, GETDATE()),
    (3, '10-min Response', 10, 35.2, 48.83, GETDATE()),
    (3, '15-min Response', 15, 62.1, 86.14, GETDATE());
GO

-- Insert sample incident data for query demonstrations
INSERT INTO incidents
    (incident_id, station_id, incident_type, priority, response_time_sec,
     lat, lon, incident_date, resolved)
VALUES
    ('INC-2024-00142', 1, 'Structure Fire', 1, 285, 32.7612, -97.7989, '2024-01-15 14:23:00', 1),
    ('INC-2024-00156', 1, 'Medical Emergency', 2, 312, 32.7598, -97.7945, '2024-01-18 09:45:00', 1),
    ('INC-2024-00201', 2, 'Vehicle Accident', 2, 198, 32.7445, -97.7612, '2024-02-03 16:30:00', 1),
    ('INC-2024-00215', 2, 'Medical Emergency', 2, 267, 32.7501, -97.7678, '2024-02-10 11:15:00', 1),
    ('INC-2024-00289', 3, 'Grass Fire', 2, 342, 32.7756, -97.8312, '2024-03-05 13:20:00', 1),
    ('INC-2024-00301', 1, 'Medical Emergency', 2, 295, 32.7589, -97.7901, '2024-03-12 08:55:00', 1),
    ('INC-2024-00345', 3, 'Structure Fire', 1, 378, 32.7698, -97.8289, '2024-04-02 22:10:00', 1),
    ('INC-2024-00412', 2, 'Medical Emergency', 2, 245, 32.7512, -97.7634, '2024-04-18 15:40:00', 1),
    ('INC-2024-00467', 1, 'Hazmat', 1, 410, 32.7634, -97.8012, '2024-05-06 10:30:00', 1),
    ('INC-2024-00523', 3, 'Medical Emergency', 2, 356, 32.7723, -97.8267, '2024-05-22 19:25:00', 1);
GO

PRINT 'Sample data inserted successfully.';
GO


-- ============================================================================
-- SECTION 3: ANALYTICAL QUERIES FOR MUNICIPAL GIS OPERATIONS
-- ============================================================================
-- These queries support common GIS analysis tasks for fire department
-- planning, ISO rating evaluations, and city council reporting.
-- ============================================================================


/*
------------------------------------------------------------------------------
QUERY 1: Parcels Outside 5-Minute Response Zone
------------------------------------------------------------------------------
Purpose: Identifies residential and commercial parcels that fall outside
         the 5-minute emergency response coverage area.

Business Use:
- Supports ISO fire rating analysis (affects insurance premiums)
- Identifies candidates for new station site selection
- Required for comprehensive plan updates
- Used in capital improvement planning justification

Note: In production, this would use ST_Contains or ST_Intersects with
      actual geometry. This version uses a simplified distance calculation.
------------------------------------------------------------------------------
*/
SELECT
    p.parcel_id,
    p.address,
    p.owner_name,
    p.land_use_desc,
    p.zoning,
    p.acreage,
    p.assessed_value,
    -- Calculate distance to nearest station (simplified; use geometry in production)
    (
        SELECT MIN(
            SQRT(POWER(p.centroid_lat - fs.lat, 2) +
                 POWER(p.centroid_lon - fs.lon, 2)) * 111  -- Approx km per degree
        )
        FROM fire_stations fs
        WHERE fs.is_active = 1
    ) AS nearest_station_km
FROM city_parcels p
WHERE p.parcel_id NOT IN (
    -- Parcels within any 5-minute response zone
    -- In production: SELECT parcel_id FROM parcels WHERE ST_Intersects(shape, zone_shape)
    SELECT DISTINCT p2.parcel_id
    FROM city_parcels p2
    CROSS JOIN fire_stations fs
    WHERE SQRT(POWER(p2.centroid_lat - fs.lat, 2) +
               POWER(p2.centroid_lon - fs.lon, 2)) * 111 < 4.5  -- ~5 min at 50km/h
)
AND p.is_residential = 1  -- Focus on residential for life safety
ORDER BY p.assessed_value DESC;
GO


/*
------------------------------------------------------------------------------
QUERY 2: Average Response Time by Station (Last 12 Months)
------------------------------------------------------------------------------
Purpose: Calculates average response times for each station to monitor
         NFPA 1710 compliance and identify performance trends.

Business Use:
- Monthly performance reporting to Fire Chief
- City Council quarterly updates
- Accreditation documentation
- Identifies stations needing additional resources

NFPA 1710 Target: 320 seconds (5:20) for first-due engine arrival
------------------------------------------------------------------------------
*/
SELECT
    fs.station_id,
    fs.name AS station_name,
    COUNT(i.incident_id) AS total_incidents,

    -- Response time metrics
    AVG(i.response_time_sec) AS avg_response_sec,
    AVG(i.response_time_sec) / 60.0 AS avg_response_min,
    MIN(i.response_time_sec) AS fastest_response_sec,
    MAX(i.response_time_sec) AS slowest_response_sec,

    -- NFPA 1710 compliance rate (under 320 seconds)
    CAST(
        SUM(CASE WHEN i.response_time_sec <= 320 THEN 1 ELSE 0 END) * 100.0 /
        NULLIF(COUNT(i.incident_id), 0)
    AS DECIMAL(5,2)) AS nfpa_compliance_pct,

    -- 90th percentile indicator (target for NFPA)
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY i.response_time_sec)
        OVER (PARTITION BY fs.station_id) AS response_90th_percentile

FROM fire_stations fs
LEFT JOIN incidents i ON fs.station_id = i.station_id
    AND i.incident_date >= DATEADD(MONTH, -12, GETDATE())
    AND i.resolved = 1
WHERE fs.is_active = 1
GROUP BY fs.station_id, fs.name
ORDER BY avg_response_sec;
GO


/*
------------------------------------------------------------------------------
QUERY 3: Incident Count by Type per Station
------------------------------------------------------------------------------
Purpose: Breaks down incident volume by type for each station to understand
         service demand patterns and resource allocation needs.

Business Use:
- Staffing and shift planning
- Equipment procurement justification
- Training needs assessment
- Budget allocation by service type
------------------------------------------------------------------------------
*/
SELECT
    fs.name AS station_name,
    i.incident_type,
    COUNT(i.incident_id) AS incident_count,

    -- Percentage of station's total calls
    CAST(
        COUNT(i.incident_id) * 100.0 /
        SUM(COUNT(i.incident_id)) OVER (PARTITION BY fs.station_id)
    AS DECIMAL(5,2)) AS pct_of_station_calls,

    -- Average response for this incident type
    AVG(i.response_time_sec) AS avg_response_sec,

    -- Priority breakdown
    SUM(CASE WHEN i.priority = 1 THEN 1 ELSE 0 END) AS priority_1_count,
    SUM(CASE WHEN i.priority = 2 THEN 1 ELSE 0 END) AS priority_2_count,
    SUM(CASE WHEN i.priority >= 3 THEN 1 ELSE 0 END) AS priority_3plus_count

FROM fire_stations fs
INNER JOIN incidents i ON fs.station_id = i.station_id
WHERE i.incident_date >= DATEADD(YEAR, -1, GETDATE())
GROUP BY fs.station_id, fs.name, i.incident_type
ORDER BY fs.name, incident_count DESC;
GO


/*
------------------------------------------------------------------------------
QUERY 4: Stations Not Meeting NFPA 1710 4-Minute Travel Time Benchmark
------------------------------------------------------------------------------
Purpose: Identifies stations where more than 10% of incidents exceed the
         NFPA 1710 standard of 240 seconds (4 minutes) travel time.

Business Use:
- Accreditation risk assessment
- Justification for station relocation or addition
- Apparatus deployment optimization
- Traffic signal preemption system evaluation

NFPA 1710 Standard:
- Travel time shall be 240 seconds or less for the first arriving engine
- This standard should be met 90% of the time
------------------------------------------------------------------------------
*/
SELECT
    fs.station_id,
    fs.name AS station_name,
    fs.address AS station_address,
    COUNT(i.incident_id) AS total_incidents,

    -- Incidents meeting 4-minute benchmark
    SUM(CASE WHEN i.travel_time_sec <= 240 THEN 1 ELSE 0 END) AS within_4min,
    SUM(CASE WHEN i.travel_time_sec > 240 THEN 1 ELSE 0 END) AS over_4min,

    -- Compliance percentage
    CAST(
        SUM(CASE WHEN i.travel_time_sec <= 240 THEN 1 ELSE 0 END) * 100.0 /
        NULLIF(COUNT(i.incident_id), 0)
    AS DECIMAL(5,2)) AS compliance_pct,

    -- Gap from 90% target
    CAST(
        90.0 - (SUM(CASE WHEN i.travel_time_sec <= 240 THEN 1 ELSE 0 END) * 100.0 /
        NULLIF(COUNT(i.incident_id), 0))
    AS DECIMAL(5,2)) AS gap_from_target,

    -- Average travel time
    AVG(i.travel_time_sec) AS avg_travel_sec

FROM fire_stations fs
INNER JOIN incidents i ON fs.station_id = i.station_id
WHERE i.incident_date >= DATEADD(MONTH, -12, GETDATE())
    AND i.resolved = 1
    AND i.travel_time_sec IS NOT NULL
GROUP BY fs.station_id, fs.name, fs.address
HAVING
    -- Flag stations below 90% compliance threshold
    SUM(CASE WHEN i.travel_time_sec <= 240 THEN 1 ELSE 0 END) * 100.0 /
    NULLIF(COUNT(i.incident_id), 0) < 90.0
ORDER BY compliance_pct ASC;
GO


/*
------------------------------------------------------------------------------
QUERY 5: New Residential Parcels Added in Last 6 Months Outside Coverage
------------------------------------------------------------------------------
Purpose: Identifies recently platted or developed residential parcels that
         fall outside the current 5-minute response coverage zone.

Business Use:
- Growth impact analysis for Fire Department
- Development review input (new subdivisions need coverage)
- Capital improvement plan updates
- New station feasibility studies
- Developer impact fee assessments

This query is critical for rapidly growing cities like Weatherford where
new residential development may outpace emergency service expansion.
------------------------------------------------------------------------------
*/
SELECT
    p.parcel_id,
    p.address,
    p.owner_name,
    p.zoning,
    p.acreage,
    p.assessed_value,
    p.year_built,
    p.last_updated AS date_added,

    -- Nearest station analysis
    nearest.station_name,
    nearest.distance_km,
    nearest.estimated_drive_min,

    -- Coverage gap flag
    CASE
        WHEN nearest.estimated_drive_min > 5 THEN 'COVERAGE GAP'
        ELSE 'Within Coverage'
    END AS coverage_status

FROM city_parcels p
CROSS APPLY (
    -- Find nearest station with estimated drive time
    SELECT TOP 1
        fs.name AS station_name,
        SQRT(POWER(p.centroid_lat - fs.lat, 2) +
             POWER(p.centroid_lon - fs.lon, 2)) * 111 AS distance_km,
        -- Estimate drive time: distance / average emergency speed (50 km/h) * 60
        (SQRT(POWER(p.centroid_lat - fs.lat, 2) +
              POWER(p.centroid_lon - fs.lon, 2)) * 111) / 50.0 * 60 AS estimated_drive_min
    FROM fire_stations fs
    WHERE fs.is_active = 1
    ORDER BY
        SQRT(POWER(p.centroid_lat - fs.lat, 2) +
             POWER(p.centroid_lon - fs.lon, 2))
) nearest

WHERE
    -- New parcels added in last 6 months
    p.last_updated >= DATEADD(MONTH, -6, GETDATE())

    -- Residential properties only
    AND p.is_residential = 1

    -- Outside 5-minute coverage (estimated drive > 5 minutes)
    AND nearest.estimated_drive_min > 5

ORDER BY nearest.estimated_drive_min DESC, p.assessed_value DESC;
GO


-- ============================================================================
-- SECTION 4: VIEWS FOR COMMON REPORTING
-- ============================================================================

/*
View for ArcGIS Dashboard - Station Performance Summary
*/
CREATE VIEW vw_station_performance_summary AS
SELECT
    fs.station_id,
    fs.name,
    fs.station_type,
    fs.units,
    fs.lat,
    fs.lon,
    COUNT(i.incident_id) AS incidents_ytd,
    AVG(i.response_time_sec) AS avg_response_sec,
    CAST(
        SUM(CASE WHEN i.response_time_sec <= 320 THEN 1 ELSE 0 END) * 100.0 /
        NULLIF(COUNT(i.incident_id), 0)
    AS DECIMAL(5,2)) AS nfpa_compliance_pct
FROM fire_stations fs
LEFT JOIN incidents i ON fs.station_id = i.station_id
    AND YEAR(i.incident_date) = YEAR(GETDATE())
WHERE fs.is_active = 1
GROUP BY fs.station_id, fs.name, fs.station_type, fs.units, fs.lat, fs.lon;
GO


/*
View for Coverage Gap Analysis Dashboard
*/
CREATE VIEW vw_coverage_gaps AS
SELECT
    frz.zone_id,
    frz.zone_type,
    frz.drive_time_minutes,
    fs.name AS station_name,
    frz.area_sqkm,
    frz.coverage_pct,
    100.0 - frz.coverage_pct AS gap_pct,
    frz.last_updated
FROM fire_response_zones frz
INNER JOIN fire_stations fs ON frz.station_id = fs.station_id
WHERE fs.is_active = 1;
GO


PRINT '================================================================================';
PRINT 'City of Weatherford GIS Database Schema Created Successfully';
PRINT '================================================================================';
PRINT '';
PRINT 'Tables created:';
PRINT '  - fire_stations        (3 sample records)';
PRINT '  - fire_response_zones  (9 sample records)';
PRINT '  - city_parcels         (schema only - sync with PCAD)';
PRINT '  - incidents            (10 sample records)';
PRINT '';
PRINT 'Views created:';
PRINT '  - vw_station_performance_summary';
PRINT '  - vw_coverage_gaps';
PRINT '';
PRINT 'Ready for ArcGIS Enterprise geodatabase registration.';
PRINT '================================================================================';
GO
