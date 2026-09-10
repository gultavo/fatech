from __future__ import annotations

from math import hypot
from typing import Any

import geopandas as gpd
from shapely.geometry import MultiPoint, Point, Polygon, mapping

from .schemas import MapPoint, MapRequest


def generate_geodata(
    request: MapRequest, max_visit_diagonal_m: float
) -> tuple[dict[str, Any], Polygon | None, list[str], int]:
    warnings: list[str] = []
    features = [_point_feature(point) for point in request.points]
    unique_coordinates = sorted(
        {(point.longitude, point.latitude) for point in request.points}
    )
    hull_wgs84: Polygon | None = None

    if len(unique_coordinates) < 3:
        warnings.append(
            "São necessários pelo menos três pontos distintos para gerar um contorno."
        )
    elif _crosses_antimeridian(unique_coordinates):
        warnings.append(
            "Os pontos atravessam o antimeridiano; o contorno foi omitido."
        )
    else:
        try:
            points_wgs84 = gpd.GeoSeries(
                [Point(longitude, latitude) for longitude, latitude in unique_coordinates],
                crs="EPSG:4326",
            )
            utm_crs = points_wgs84.estimate_utm_crs()
            if utm_crs is None:
                warnings.append(
                    "Não foi possível estimar uma projeção local; o contorno foi omitido."
                )
            else:
                projected = points_wgs84.to_crs(utm_crs)
                min_x, min_y, max_x, max_y = projected.total_bounds
                diagonal = hypot(max_x - min_x, max_y - min_y)
                if diagonal > max_visit_diagonal_m:
                    warnings.append(
                        "A extensão dos pontos excede "
                        f"{max_visit_diagonal_m / 1000:g} km; o contorno foi omitido."
                    )
                else:
                    hull = MultiPoint(list(projected)).convex_hull
                    nearly_collinear = (
                        hull.geom_type == "Polygon"
                        and hull.area / max(diagonal * diagonal, 1.0) < 1e-5
                    )
                    if (
                        hull.geom_type != "Polygon"
                        or hull.is_empty
                        or not hull.is_valid
                        or nearly_collinear
                    ):
                        warnings.append(
                            "Os pontos são colineares; não há polígono de contorno."
                        )
                    else:
                        hull_wgs84 = gpd.GeoSeries([hull], crs=utm_crs).to_crs(
                            "EPSG:4326"
                        )[0]
        except Exception:
            warnings.append(
                "Não foi possível projetar os pontos; o contorno foi omitido."
            )

    if hull_wgs84 is not None:
        features.append(
            {
                "type": "Feature",
                "geometry": mapping(hull_wgs84),
                "properties": {"kind": "hull", "visit_id": request.visit_id},
            }
        )

    return (
        {"type": "FeatureCollection", "features": features},
        hull_wgs84,
        warnings,
        len(unique_coordinates),
    )


def _crosses_antimeridian(coordinates: list[tuple[float, float]]) -> bool:
    longitudes = [longitude for longitude, _ in coordinates]
    return max(longitudes) - min(longitudes) > 180


def _point_feature(point: MapPoint) -> dict[str, Any]:
    properties = point.properties.model_dump()
    properties.update({"occurrence_id": point.occurrence_id, "kind": "occurrence"})
    return {
        "type": "Feature",
        "geometry": {
            "type": "Point",
            "coordinates": [point.longitude, point.latitude],
        },
        "properties": properties,
    }
