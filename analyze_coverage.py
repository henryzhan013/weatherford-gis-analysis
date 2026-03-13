#!/usr/bin/env python3
"""
Fire/EMS Station Coverage Analysis for Weatherford, Texas
Analyzes drive-time service areas for emergency response planning.

Author: Portfolio Project for City of Weatherford GIS Position
"""

import os
import warnings
import osmnx as ox
import networkx as nx
import geopandas as gpd
import pandas as pd
from shapely.geometry import Point, Polygon
from shapely.ops import unary_union
from shapely.validation import make_valid

# Suppress warnings for cleaner output
warnings.filterwarnings('ignore')

# Configuration
OUTPUT_DIR = "output_shapefiles"
CRS = "EPSG:4326"

# Fire/EMS Station Locations
STATIONS = {
    "Station 1 Central": {"lat": 32.7601, "lon": -97.7974},
    "Station 2 East Side": {"lat": 32.7488, "lon": -97.7645},
    "Station 3 West": {"lat": 32.7712, "lon": -97.8250},
}

# Drive-time thresholds in minutes
TIME_THRESHOLDS = [5, 10, 15]

# Average driving speed in km/h for emergency vehicles
EMERGENCY_SPEED_KMH = 50


def create_output_directory():
    """Create output directory if it doesn't exist."""
    print("\n" + "=" * 60)
    print("STEP 1: Setting up output directory")
    print("=" * 60)

    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
        print(f"  Created directory: {OUTPUT_DIR}/")
    else:
        print(f"  Directory already exists: {OUTPUT_DIR}/")


def download_street_network():
    """Download street network for Weatherford, Texas from OpenStreetMap."""
    print("\n" + "=" * 60)
    print("STEP 2: Downloading street network from OpenStreetMap")
    print("=" * 60)

    print("  Querying OpenStreetMap for Weatherford, Texas...")
    print("  This may take a minute depending on network speed...")

    # Center point of Weatherford (approximate)
    center_lat = 32.7593
    center_lon = -97.7973

    # Download a larger network using distance from center point
    # 15 km radius ensures we capture full 15-minute drive times
    # (At ~50 km/h, 15 min = 12.5 km, so 15 km provides buffer)
    print("  Downloading 15 km radius network to ensure full coverage...")
    G = ox.graph_from_point(
        (center_lat, center_lon),
        dist=15000,  # 15 km radius in meters
        network_type="drive",
        simplify=True
    )

    # Add travel time to edges based on length and speed
    print("  Adding travel time attributes to network edges...")
    G = ox.add_edge_speeds(G)
    G = ox.add_edge_travel_times(G)

    # Get network statistics
    num_nodes = G.number_of_nodes()
    num_edges = G.number_of_edges()

    print(f"  Network downloaded successfully!")
    print(f"    - Nodes: {num_nodes:,}")
    print(f"    - Edges: {num_edges:,}")
    print(f"    - Coverage: 15 km radius from city center")

    return G


def get_city_boundary():
    """Download city boundary polygon for Weatherford, Texas."""
    print("\n" + "=" * 60)
    print("STEP 3: Downloading city boundary")
    print("=" * 60)

    print("  Fetching administrative boundary from OpenStreetMap...")

    gdf = ox.geocode_to_gdf("Weatherford, Texas, USA")
    boundary = gdf.geometry.iloc[0]

    area_sq_km = gdf.to_crs("EPSG:32614").geometry.area.iloc[0] / 1_000_000
    print(f"  City boundary retrieved!")
    print(f"    - Area: {area_sq_km:.2f} sq km")

    return boundary, gdf


def create_stations_geodataframe():
    """Create a GeoDataFrame for fire/EMS stations."""
    print("\n" + "=" * 60)
    print("STEP 4: Defining fire/EMS station locations")
    print("=" * 60)

    stations_data = []
    for name, coords in STATIONS.items():
        stations_data.append({
            "name": name,
            "latitude": coords["lat"],
            "longitude": coords["lon"],
            "geometry": Point(coords["lon"], coords["lat"])
        })

    stations_gdf = gpd.GeoDataFrame(stations_data, crs=CRS)

    print("  Fire/EMS Stations defined:")
    for name, coords in STATIONS.items():
        print(f"    - {name}: ({coords['lat']}, {coords['lon']})")

    return stations_gdf


def compute_service_area(G, station_coords, time_minutes):
    """
    Compute drive-time service area for a single station.

    Uses Dijkstra's algorithm to find all nodes reachable within the
    travel time threshold, then creates a convex hull polygon.

    Note: We use single_source_dijkstra_path_length instead of ego_graph
    because ego_graph can have issues with directed multigraphs and
    weighted edges. Dijkstra explicitly computes shortest paths using
    the travel_time edge weight.
    """
    lat, lon = station_coords["lat"], station_coords["lon"]

    # Find nearest node to station location
    center_node = ox.nearest_nodes(G, lon, lat)

    # Convert time threshold to seconds
    time_seconds = time_minutes * 60

    # Use Dijkstra's algorithm to find all nodes reachable within time threshold
    # This returns a dict of {node: travel_time} for all reachable nodes
    reachable = nx.single_source_dijkstra_path_length(
        G,
        center_node,
        cutoff=time_seconds,
        weight="travel_time"
    )

    # Get coordinates of all reachable nodes
    node_coords = []
    for node in reachable.keys():
        node_data = G.nodes[node]
        node_coords.append((node_data["x"], node_data["y"]))

    # Debug: print node count for this threshold
    print(f"({len(node_coords)} nodes)", end=" ")

    if len(node_coords) < 3:
        # Not enough points for a polygon, return a small buffer around station
        return Point(lon, lat).buffer(0.001)

    # Create polygon from reachable nodes using convex hull
    points_gdf = gpd.GeoDataFrame(
        geometry=[Point(coord) for coord in node_coords],
        crs=CRS
    )

    # Use convex hull to create service area polygon
    service_area = points_gdf.unary_union.convex_hull

    return service_area


def compute_all_service_areas(G):
    """Compute service areas for all stations at all time thresholds."""
    print("\n" + "=" * 60)
    print("STEP 5: Computing drive-time service areas")
    print("=" * 60)

    # Dictionary to store service areas by time threshold
    service_areas = {t: [] for t in TIME_THRESHOLDS}

    for station_name, coords in STATIONS.items():
        print(f"\n  Processing {station_name}...")

        for time_min in TIME_THRESHOLDS:
            print(f"    Computing {time_min}-minute service area...", end=" ")

            try:
                polygon = compute_service_area(G, coords, time_min)
                service_areas[time_min].append(polygon)
                print("Done")
            except Exception as e:
                print(f"Error: {e}")
                # Create fallback buffer if computation fails
                point = Point(coords["lon"], coords["lat"])
                # Approximate buffer based on time (rough estimate)
                buffer_deg = time_min * 0.005  # ~0.5km per minute
                service_areas[time_min].append(point.buffer(buffer_deg))
                print(f"    Using fallback buffer for {time_min}-minute zone")

    return service_areas


def merge_service_areas(service_areas):
    """Merge service areas from all stations for each time threshold."""
    print("\n" + "=" * 60)
    print("STEP 6: Merging service areas across stations")
    print("=" * 60)

    merged_zones = {}

    for time_min in TIME_THRESHOLDS:
        print(f"  Merging {time_min}-minute zones from {len(STATIONS)} stations...", end=" ")

        # Use unary_union to merge all polygons for this time threshold
        merged = unary_union(service_areas[time_min])

        # Ensure valid geometry
        if not merged.is_valid:
            merged = make_valid(merged)

        merged_zones[time_min] = merged
        print("Done")

    return merged_zones


def calculate_coverage(merged_zones, city_boundary):
    """Calculate what percentage of the city each zone covers."""
    print("\n" + "=" * 60)
    print("STEP 7: Calculating coverage statistics")
    print("=" * 60)

    # Project to UTM for accurate area calculations (UTM Zone 14N for Texas)
    utm_crs = "EPSG:32614"

    # Create GeoDataFrame for city boundary
    city_gdf = gpd.GeoDataFrame(geometry=[city_boundary], crs=CRS)
    city_gdf_utm = city_gdf.to_crs(utm_crs)
    city_area = city_gdf_utm.geometry.area.iloc[0]

    coverage_stats = {}

    print("\n  Coverage Summary:")
    print("  " + "-" * 40)

    for time_min in TIME_THRESHOLDS:
        zone = merged_zones[time_min]

        # Create GeoDataFrame and project
        zone_gdf = gpd.GeoDataFrame(geometry=[zone], crs=CRS)
        zone_gdf_utm = zone_gdf.to_crs(utm_crs)

        # Intersect with city boundary to get coverage within city limits
        intersection = zone_gdf_utm.geometry.iloc[0].intersection(
            city_gdf_utm.geometry.iloc[0]
        )

        covered_area = intersection.area
        coverage_pct = (covered_area / city_area) * 100

        coverage_stats[time_min] = {
            "zone_area_sqkm": zone_gdf_utm.geometry.area.iloc[0] / 1_000_000,
            "covered_area_sqkm": covered_area / 1_000_000,
            "city_area_sqkm": city_area / 1_000_000,
            "coverage_percent": coverage_pct
        }

        print(f"  {time_min:2d}-minute zone: {coverage_pct:6.2f}% of city covered")
        print(f"      ({covered_area/1_000_000:.2f} sq km of {city_area/1_000_000:.2f} sq km)")

    print("  " + "-" * 40)

    return coverage_stats


def export_shapefiles(merged_zones, stations_gdf):
    """Export service area zones and stations as shapefiles."""
    print("\n" + "=" * 60)
    print("STEP 8: Exporting shapefiles")
    print("=" * 60)

    # Export each time zone as separate shapefile
    for time_min in TIME_THRESHOLDS:
        zone = merged_zones[time_min]

        # Create GeoDataFrame with attributes
        zone_gdf = gpd.GeoDataFrame(
            {
                "time_min": [time_min],
                "zone_type": [f"{time_min}_minute_response"],
                "geometry": [zone]
            },
            crs=CRS
        )

        filename = f"zone_{time_min}min.shp"
        filepath = os.path.join(OUTPUT_DIR, filename)
        zone_gdf.to_file(filepath)
        print(f"  Exported: {filepath}")

    # Export stations shapefile
    stations_filepath = os.path.join(OUTPUT_DIR, "stations.shp")
    stations_gdf.to_file(stations_filepath)
    print(f"  Exported: {stations_filepath}")


def export_geojson(merged_zones, stations_gdf, city_boundary):
    """Export all layers as a single GeoJSON file."""
    print("\n" + "=" * 60)
    print("STEP 9: Exporting combined GeoJSON")
    print("=" * 60)

    all_features = []

    # Add service zones
    for time_min in TIME_THRESHOLDS:
        zone = merged_zones[time_min]
        zone_gdf = gpd.GeoDataFrame(
            {
                "layer": [f"zone_{time_min}min"],
                "zone_type": [f"{time_min}-min Response"],
                "time_minutes": [time_min],
                "type": ["service_area"],
                "geometry": [zone]
            },
            crs=CRS
        )
        all_features.append(zone_gdf)

    # Add stations
    stations_export = stations_gdf.copy()
    stations_export["station_name"] = stations_export["name"]
    stations_export["layer"] = "stations"
    stations_export["type"] = "station"
    stations_export["zone_type"] = None
    stations_export["time_minutes"] = None
    all_features.append(stations_export)

    # Add city boundary
    city_gdf = gpd.GeoDataFrame(
        {
            "layer": ["city_boundary"],
            "zone_type": [None],
            "type": ["boundary"],
            "time_minutes": [None],
            "geometry": [city_boundary]
        },
        crs=CRS
    )
    all_features.append(city_gdf)

    # Combine all features
    combined_gdf = gpd.GeoDataFrame(
        pd.concat(all_features, ignore_index=True),
        crs=CRS
    )

    # Export to GeoJSON
    geojson_path = "weatherford_coverage.geojson"
    combined_gdf.to_file(geojson_path, driver="GeoJSON")
    print(f"  Exported: {geojson_path}")
    print(f"    - Contains {len(combined_gdf)} features")
    print(f"    - Layers: zones (5, 10, 15 min), stations, city boundary")


def export_geojson_v2(merged_zones, stations_gdf, city_boundary):
    """
    Export all layers as a clean GeoJSON file (v2).

    Builds GeoJSON structure directly using Python dicts to ensure
    proper feature separation and attribute handling for ArcGIS Online.
    """
    import json
    from shapely.geometry import mapping

    print("\n" + "=" * 60)
    print("STEP 10: Exporting clean GeoJSON (v2)")
    print("=" * 60)

    features = []

    # Add each zone as a SEPARATE feature
    for time_min in TIME_THRESHOLDS:
        zone_geom = merged_zones[time_min]

        feature = {
            "type": "Feature",
            "properties": {
                "zone_type": f"{time_min}-min Response",
                "time_minutes": time_min,
                "feature_type": "service_area"
            },
            "geometry": mapping(zone_geom)
        }
        features.append(feature)
        print(f"  Added zone: {time_min}-min Response")

    # Add each station as a SEPARATE point feature
    for idx, row in stations_gdf.iterrows():
        feature = {
            "type": "Feature",
            "properties": {
                "name": row["name"],
                "latitude": row["latitude"],
                "longitude": row["longitude"],
                "feature_type": "station"
            },
            "geometry": mapping(row["geometry"])
        }
        features.append(feature)
        print(f"  Added station: {row['name']}")

    # Add city boundary as a feature
    feature = {
        "type": "Feature",
        "properties": {
            "name": "Weatherford City Boundary",
            "feature_type": "boundary"
        },
        "geometry": mapping(city_boundary)
    }
    features.append(feature)
    print(f"  Added: City Boundary")

    # Build the FeatureCollection
    geojson = {
        "type": "FeatureCollection",
        "crs": {
            "type": "name",
            "properties": {
                "name": "urn:ogc:def:crs:OGC:1.3:CRS84"
            }
        },
        "features": features
    }

    # Write to file
    geojson_path = "weatherford_coverage_v2.geojson"
    with open(geojson_path, 'w') as f:
        json.dump(geojson, f, indent=2)

    print(f"\n  Exported: {geojson_path}")
    print(f"    - Total features: {len(features)}")
    print(f"    - Zones: 3 (5-min, 10-min, 15-min)")
    print(f"    - Stations: {len(stations_gdf)}")
    print(f"    - Boundary: 1")

    # Verify by printing first feature's properties
    print("\n  Verification - First feature properties:")
    first_props = features[0]["properties"]
    for key, value in first_props.items():
        print(f"    {key}: {value}")


def main():
    """Main execution function."""
    print("\n" + "=" * 60)
    print("  WEATHERFORD FIRE/EMS COVERAGE ANALYSIS")
    print("  City of Weatherford, Texas - GIS Portfolio Project")
    print("=" * 60)

    # Step 1: Create output directory
    create_output_directory()

    # Step 2: Download street network
    G = download_street_network()

    # Step 3: Get city boundary
    city_boundary, city_gdf = get_city_boundary()

    # Step 4: Define station locations
    stations_gdf = create_stations_geodataframe()

    # Step 5: Compute service areas
    service_areas = compute_all_service_areas(G)

    # Step 6: Merge service areas
    merged_zones = merge_service_areas(service_areas)

    # Step 7: Calculate coverage statistics
    coverage_stats = calculate_coverage(merged_zones, city_boundary)

    # Step 8: Export shapefiles
    export_shapefiles(merged_zones, stations_gdf)

    # Step 9: Export GeoJSON (original)
    export_geojson(merged_zones, stations_gdf, city_boundary)

    # Step 10: Export clean GeoJSON v2 (ArcGIS Online compatible)
    export_geojson_v2(merged_zones, stations_gdf, city_boundary)

    # Final summary
    print("\n" + "=" * 60)
    print("  ANALYSIS COMPLETE")
    print("=" * 60)
    print(f"\n  Output files created in '{OUTPUT_DIR}/':")
    print("    - zone_5min.shp")
    print("    - zone_10min.shp")
    print("    - zone_15min.shp")
    print("    - stations.shp")
    print("\n  Combined GeoJSON:")
    print("    - weatherford_coverage.geojson (original)")
    print("    - weatherford_coverage_v2.geojson (ArcGIS compatible)")
    print("\n  All outputs use CRS: EPSG:4326 (WGS 84)")
    print("=" * 60 + "\n")

    return coverage_stats


if __name__ == "__main__":
    main()
