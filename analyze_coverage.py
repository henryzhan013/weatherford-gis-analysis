#!/usr/bin/env python3
"""
Drive-time coverage analysis for Weatherford Fire/EMS stations.
Uses OSMnx to pull road network and computes service areas via Dijkstra.
"""

import os
import warnings
import osmnx as ox
import networkx as nx
import geopandas as gpd
import pandas as pd
from shapely.geometry import Point
from shapely.ops import unary_union
from shapely.validation import make_valid

warnings.filterwarnings('ignore')

# Config
OUTPUT_DIR = "output_shapefiles"
CRS = "EPSG:4326"

# Station locations (lat, lon)
STATIONS = {
    "Station 1 Central": (32.7577280, -97.8006822),
    "Station 2 East Side": (32.7545750, -97.7122169),
    "Station 3 West": (32.7452730, -97.7428256),
}

TIME_THRESHOLDS = [5, 10, 15]  # minutes


def get_street_network():
    """Pull drivable street network from OSM, centered on Weatherford."""
    print("Downloading street network...")

    # 15km radius to make sure we capture full 15-min drive times
    G = ox.graph_from_point(
        (32.7593, -97.7973),  # city center approx
        dist=15000,
        network_type="drive",
        simplify=True
    )

    G = ox.add_edge_speeds(G)
    G = ox.add_edge_travel_times(G)

    print(f"  Got {G.number_of_nodes():,} nodes, {G.number_of_edges():,} edges")
    return G


def get_city_boundary():
    """Grab city boundary polygon for coverage calculations."""
    print("Fetching city boundary...")
    gdf = ox.geocode_to_gdf("Weatherford, Texas, USA")
    boundary = gdf.geometry.iloc[0]

    area_km2 = gdf.to_crs("EPSG:32614").geometry.area.iloc[0] / 1e6
    print(f"  City area: {area_km2:.1f} sq km")
    return boundary


def compute_service_area(G, lat, lon, minutes):
    """
    Find all nodes reachable within `minutes` drive time from a point.
    Returns a convex hull polygon of those nodes.
    """
    node = ox.nearest_nodes(G, lon, lat)
    seconds = minutes * 60

    # Dijkstra to find reachable nodes
    reachable = nx.single_source_dijkstra_path_length(
        G, node, cutoff=seconds, weight="travel_time"
    )

    # Build polygon from node coordinates
    coords = [(G.nodes[n]["x"], G.nodes[n]["y"]) for n in reachable]

    if len(coords) < 3:
        return Point(lon, lat).buffer(0.001)

    points = gpd.GeoDataFrame(geometry=[Point(c) for c in coords], crs=CRS)
    return points.unary_union.convex_hull


def run_analysis():
    """Main analysis routine."""
    print("\n=== Weatherford Fire/EMS Coverage Analysis ===\n")

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    G = get_street_network()
    city_boundary = get_city_boundary()

    # Compute zones for each station and time threshold
    print("\nComputing service areas...")
    zones_by_time = {t: [] for t in TIME_THRESHOLDS}

    for name, (lat, lon) in STATIONS.items():
        print(f"  {name}")
        for t in TIME_THRESHOLDS:
            poly = compute_service_area(G, lat, lon, t)
            zones_by_time[t].append(poly)
            print(f"    {t}-min: done")

    # Merge all stations' zones for each time threshold
    print("\nMerging zones...")
    merged = {}
    for t in TIME_THRESHOLDS:
        m = unary_union(zones_by_time[t])
        if not m.is_valid:
            m = make_valid(m)
        merged[t] = m

    # Calculate coverage stats
    print("\nCoverage results:")
    city_gdf = gpd.GeoDataFrame(geometry=[city_boundary], crs=CRS).to_crs("EPSG:32614")
    city_area = city_gdf.geometry.area.iloc[0]

    for t in TIME_THRESHOLDS:
        zone_gdf = gpd.GeoDataFrame(geometry=[merged[t]], crs=CRS).to_crs("EPSG:32614")
        covered = zone_gdf.geometry.iloc[0].intersection(city_gdf.geometry.iloc[0]).area
        pct = covered / city_area * 100
        print(f"  {t:2d}-min: {pct:.2f}% ({covered/1e6:.2f} of {city_area/1e6:.2f} sq km)")

    # Export shapefiles
    print("\nExporting shapefiles...")
    for t in TIME_THRESHOLDS:
        gdf = gpd.GeoDataFrame({
            "time_min": [t],
            "zone_type": [f"{t}-min Response"],
            "geometry": [merged[t]]
        }, crs=CRS)
        gdf.to_file(f"{OUTPUT_DIR}/zone_{t}min.shp")

    # Stations shapefile
    stations_gdf = gpd.GeoDataFrame({
        "name": list(STATIONS.keys()),
        "geometry": [Point(lon, lat) for lat, lon in STATIONS.values()]
    }, crs=CRS)
    stations_gdf.to_file(f"{OUTPUT_DIR}/stations.shp")

    # GeoJSON with everything
    print("Exporting GeoJSON...")
    export_geojson(merged, stations_gdf, city_boundary)

    print("\nDone!")
    print(f"Output in {OUTPUT_DIR}/ and weatherford_coverage.geojson")


def export_geojson(merged_zones, stations_gdf, city_boundary):
    """Export all layers to a single GeoJSON file."""
    import json
    from shapely.geometry import mapping

    features = []

    # Zones (reverse order so smaller zones draw on top)
    for t in reversed(TIME_THRESHOLDS):
        features.append({
            "type": "Feature",
            "properties": {
                "zone_type": f"{t}-min Response",
                "time_minutes": t,
                "feature_type": "service_area"
            },
            "geometry": mapping(merged_zones[t])
        })

    # Stations
    for _, row in stations_gdf.iterrows():
        features.append({
            "type": "Feature",
            "properties": {
                "name": row["name"],
                "feature_type": "station"
            },
            "geometry": mapping(row["geometry"])
        })

    # City boundary
    features.append({
        "type": "Feature",
        "properties": {
            "name": "Weatherford City Boundary",
            "feature_type": "boundary"
        },
        "geometry": mapping(city_boundary)
    })

    geojson = {
        "type": "FeatureCollection",
        "features": features
    }

    with open("weatherford_coverage.geojson", "w") as f:
        json.dump(geojson, f)


if __name__ == "__main__":
    run_analysis()
