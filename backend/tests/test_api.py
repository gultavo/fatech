from __future__ import annotations

from xml.etree import ElementTree as ET

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture(autouse=True)
def disabled_ai(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AI_PROVIDER", "disabled")
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.delenv("GEMINI_MODEL", raising=False)


@pytest.fixture
def client() -> TestClient:
    return TestClient(app, raise_server_exceptions=False)


def test_health_keeps_maps_available_without_ai(client: TestClient) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "capabilities": {"maps": True, "ai_configured": False},
    }


def test_audio_without_configuration_is_honest(client: TestClient) -> None:
    response = client.post(
        "/api/v1/audio/transcribe",
        data={"occurrence_id": "occ-1", "attachment_id": "audio-1"},
        files={"file": ("audio.m4a", b"not-a-real-clip", "audio/mp4")},
    )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "AI_NOT_CONFIGURED"


@pytest.mark.parametrize(
    ("filename", "contents", "content_type", "status", "code"),
    [
        ("empty.m4a", b"", "audio/mp4", 422, "EMPTY_AUDIO"),
        ("script.exe", b"x", "application/octet-stream", 415, "UNSUPPORTED_AUDIO"),
    ],
)
def test_audio_validation(
    client: TestClient,
    filename: str,
    contents: bytes,
    content_type: str,
    status: int,
    code: str,
) -> None:
    response = client.post(
        "/api/v1/audio/transcribe",
        data={"occurrence_id": "occ-1", "attachment_id": "audio-1"},
        files={"file": (filename, contents, content_type)},
    )
    assert response.status_code == status
    assert response.json()["error"]["code"] == code


def test_extraction_without_configuration(client: TestClient) -> None:
    response = client.post(
        "/api/v1/forms/extract",
        json={
            "occurrence_id": "occ-1",
            "revision": 3,
            "input_hash": "abc",
            "sources": [
                {"id": "written_report", "text": "Possível assoreamento."}
            ],
        },
    )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "AI_NOT_CONFIGURED"


def test_validation_errors_have_stable_shape(client: TestClient) -> None:
    response = client.post("/api/v1/maps/generate", json={"visit_id": "x"})
    assert response.status_code == 422
    body = response.json()["error"]
    assert body["code"] == "VALIDATION_ERROR"
    assert isinstance(body["details"]["issues"], list)


def point(
    occurrence_id: str,
    latitude: float,
    longitude: float,
    description: str = "Possível alteração & observação <visual>",
) -> dict:
    return {
        "occurrence_id": occurrence_id,
        "latitude": latitude,
        "longitude": longitude,
        "properties": {
            "status": "draft",
            "visit_date": "2026-09-10",
            "enterprise": "Empreendimento fictício",
            "environmental_occurrence": description,
            "technical_opinion": None,
            "location_reference": "km 214+300",
            "accuracy_m": None,
            "location_source": "manual_demo",
            "is_demo": True,
        },
    }


def generate(client: TestClient, points: list[dict]) -> dict:
    response = client.post(
        "/api/v1/maps/generate",
        json={"visit_id": "visit-1", "input_hash": "hash-1", "points": points},
    )
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.parametrize("count", [1, 2])
def test_one_or_two_points_export_without_artificial_polygon(
    client: TestClient, count: int
) -> None:
    points = [
        point(f"occ-{index}", -27.595 + index * 0.001, -48.548)
        for index in range(count)
    ]
    body = generate(client, points)
    assert body["point_count"] == count
    assert body["has_hull"] is False
    assert len(body["geojson"]["features"]) == count


def test_collinear_points_have_warning_and_no_polygon(client: TestClient) -> None:
    body = generate(
        client,
        [
            point("a", -27.595, -48.548),
            point("b", -27.594, -48.547),
            point("c", -27.593, -48.546),
        ],
    )
    assert body["has_hull"] is False
    assert any("colineares" in warning for warning in body["warnings"])


def test_hull_and_kml_preserve_all_occurrences_and_escape_text(
    client: TestClient,
) -> None:
    body = generate(
        client,
        [
            point("a", -27.595, -48.548),
            point("b", -27.596, -48.546),
            point("c", -27.597, -48.549),
            point("d", -27.595, -48.548),
        ],
    )
    assert body["point_count"] == 4
    assert body["unique_point_count"] == 3
    assert body["has_hull"] is True
    assert len(body["geojson"]["features"]) == 5

    root = ET.fromstring(body["kml"])
    namespace = {"k": "http://www.opengis.net/kml/2.2"}
    point_nodes = root.findall(".//k:Point", namespace)
    assert len(point_nodes) == 4
    polygon_coordinates = root.find(
        ".//k:Polygon/k:outerBoundaryIs/k:LinearRing/k:coordinates", namespace
    )
    assert polygon_coordinates is not None
    ring = polygon_coordinates.text.strip().split()
    assert ring[0] == ring[-1]
    assert "-48." in point_nodes[0].find("k:coordinates", namespace).text
    assert "&amp;" in body["kml"] and "&lt;visual&gt;" in body["kml"]


def test_capture_order_and_internal_point_do_not_change_hull(client: TestClient) -> None:
    exterior = [
        point("a", -27.595, -48.548),
        point("b", -27.596, -48.546),
        point("c", -27.597, -48.549),
    ]
    first = generate(client, exterior)
    second = generate(
        client,
        [
            point("c", -27.597, -48.549),
            point("inside", -27.596, -48.548),
            point("a", -27.595, -48.548),
            point("b", -27.596, -48.546),
        ],
    )

    def hull_coordinates(body: dict) -> set[tuple[float, float]]:
        feature = next(
            item
            for item in body["geojson"]["features"]
            if item["properties"]["kind"] == "hull"
        )
        return {tuple(pair) for pair in feature["geometry"]["coordinates"][0]}

    assert hull_coordinates(first) == hull_coordinates(second)
    assert second["point_count"] == 4


def test_invalid_coordinate_and_repeated_id_are_rejected(client: TestClient) -> None:
    invalid = client.post(
        "/api/v1/maps/generate",
        json={
            "visit_id": "visit-1",
            "input_hash": "hash",
            "points": [point("a", 95, -48)],
        },
    )
    assert invalid.status_code == 422
    duplicate = client.post(
        "/api/v1/maps/generate",
        json={
            "visit_id": "visit-1",
            "input_hash": "hash",
            "points": [point("a", -27, -48), point("a", -28, -49)],
        },
    )
    assert duplicate.status_code == 422


def test_antimeridian_keeps_points_but_omits_hull(client: TestClient) -> None:
    body = generate(
        client,
        [
            point("a", 0, 179.9),
            point("b", 0.1, -179.9),
            point("c", -0.1, 179.8),
        ],
    )
    assert body["point_count"] == 3
    assert body["has_hull"] is False
    assert any("antimeridiano" in warning for warning in body["warnings"])


def test_500_point_fixture_generates_without_partial_export(client: TestClient) -> None:
    points = [
        point(
            f"occ-{index}",
            -27.60 + (index // 25) * 0.0001,
            -48.55 + (index % 25) * 0.0001,
            "Registro fictício",
        )
        for index in range(500)
    ]
    body = generate(client, points)
    assert body["point_count"] == 500
    assert body["unique_point_count"] == 500
    assert body["has_hull"] is True
    assert len(body["geojson"]["features"]) == 501
