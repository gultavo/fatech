from __future__ import annotations

import re
from xml.etree import ElementTree as ET

from shapely.geometry import Polygon

from .schemas import MapRequest

KML_NS = "http://www.opengis.net/kml/2.2"
ET.register_namespace("", KML_NS)
_INVALID_XML = re.compile(r"[^\x09\x0A\x0D\x20-\uD7FF\uE000-\uFFFD]")


def build_kml(request: MapRequest, hull: Polygon | None) -> str:
    kml = ET.Element(_tag("kml"))
    document = ET.SubElement(kml, _tag("Document"))
    ET.SubElement(document, _tag("name")).text = _clean(
        f"FAtech - visita {request.visit_id}"
    )

    occurrences_folder = ET.SubElement(document, _tag("Folder"))
    ET.SubElement(occurrences_folder, _tag("name")).text = "Ocorrências"
    for point in request.points:
        placemark = ET.SubElement(occurrences_folder, _tag("Placemark"))
        description = (
            point.properties.environmental_occurrence.strip()
            or f"Ocorrência {point.occurrence_id}"
        )
        ET.SubElement(placemark, _tag("name")).text = _clean(
            f"Ocorrência {point.occurrence_id[:8]}"
        )
        ET.SubElement(placemark, _tag("description")).text = _clean(description)
        extended = ET.SubElement(placemark, _tag("ExtendedData"))
        attributes = {
            "occurrence_id": point.occurrence_id,
            "status": point.properties.status,
            "visit_date": point.properties.visit_date,
            "enterprise": point.properties.enterprise,
            "environmental_occurrence": point.properties.environmental_occurrence,
            "technical_opinion": point.properties.technical_opinion,
            "location_reference": point.properties.location_reference,
            "accuracy_m": point.properties.accuracy_m,
            "location_source": point.properties.location_source,
            "is_demo": point.properties.is_demo,
        }
        for name, value in attributes.items():
            data = ET.SubElement(extended, _tag("Data"), {"name": name})
            ET.SubElement(data, _tag("value")).text = _clean(_stringify(value))
        geometry = ET.SubElement(placemark, _tag("Point"))
        ET.SubElement(geometry, _tag("coordinates")).text = (
            f"{point.longitude:.10f},{point.latitude:.10f},0"
        )

    hull_folder = ET.SubElement(document, _tag("Folder"))
    ET.SubElement(hull_folder, _tag("name")).text = "Contorno dos pontos"
    if hull is not None:
        placemark = ET.SubElement(hull_folder, _tag("Placemark"))
        ET.SubElement(placemark, _tag("name")).text = "Envelope convexo"
        ET.SubElement(placemark, _tag("description")).text = (
            "Contorno dos pontos registrados. Não representa uma delimitação "
            "técnica da área afetada."
        )
        polygon = ET.SubElement(placemark, _tag("Polygon"))
        ET.SubElement(polygon, _tag("tessellate")).text = "1"
        outer = ET.SubElement(polygon, _tag("outerBoundaryIs"))
        ring = ET.SubElement(outer, _tag("LinearRing"))
        coordinates = list(hull.exterior.coords)
        if coordinates and coordinates[0] != coordinates[-1]:
            coordinates.append(coordinates[0])
        ET.SubElement(ring, _tag("coordinates")).text = " ".join(
            f"{longitude:.10f},{latitude:.10f},0"
            for longitude, latitude in coordinates
        )

    return ET.tostring(kml, encoding="utf-8", xml_declaration=True).decode("utf-8")


def _tag(name: str) -> str:
    return f"{{{KML_NS}}}{name}"


def _clean(value: str) -> str:
    return _INVALID_XML.sub("", value)


def _stringify(value: object | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)
