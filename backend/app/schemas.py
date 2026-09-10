from __future__ import annotations

from math import isfinite
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Source(StrictModel):
    id: str = Field(min_length=1, max_length=150)
    text: str = Field(min_length=1, max_length=8_000)


class ExtractRequest(StrictModel):
    occurrence_id: str = Field(min_length=1, max_length=100)
    revision: int = Field(ge=0)
    input_hash: str = Field(min_length=1, max_length=128)
    sources: list[Source] = Field(min_length=1, max_length=20)

    @model_validator(mode="after")
    def validate_sources(self) -> "ExtractRequest":
        source_ids = [source.id for source in self.sources]
        if len(source_ids) != len(set(source_ids)):
            raise ValueError("Os IDs das fontes devem ser únicos.")
        if sum(len(source.text) for source in self.sources) > 24_000:
            raise ValueError("As fontes excedem o limite total de 24.000 caracteres.")
        return self


class FieldSuggestion(StrictModel):
    value: str | None = Field(default=None, max_length=8_000)
    source_id: str | None = Field(default=None, max_length=150)
    evidence: str | None = Field(default=None, max_length=2_000)

    @model_validator(mode="after")
    def all_present_or_null(self) -> "FieldSuggestion":
        values = (self.value, self.source_id, self.evidence)
        if any(value is None for value in values) and not all(
            value is None for value in values
        ):
            raise ValueError("value, source_id e evidence devem ser informados juntos.")
        return self


class ExtractionFields(StrictModel):
    visit_date: FieldSuggestion
    visit_type: FieldSuggestion
    enterprise: FieldSuggestion
    location_reference: FieldSuggestion
    environmental_occurrence: FieldSuggestion
    technical_opinion: FieldSuggestion


class AIExtractionPayload(StrictModel):
    fields: ExtractionFields
    warnings: list[str] = Field(default_factory=list, max_length=20)


class ExtractResponse(StrictModel):
    occurrence_id: str
    revision: int
    input_hash: str
    fields: ExtractionFields
    warnings: list[str]


class MapProperties(StrictModel):
    status: Literal["draft", "finalized"]
    visit_date: str = Field(min_length=1, max_length=40)
    enterprise: str = Field(max_length=500)
    environmental_occurrence: str = Field(max_length=8_000)
    technical_opinion: str | None = Field(default=None, max_length=8_000)
    location_reference: str = Field(default="", max_length=1_000)
    accuracy_m: float | None = Field(default=None, ge=0)
    location_source: Literal["gps", "manual_demo"] | None = None
    is_demo: bool = False


class MapPoint(StrictModel):
    occurrence_id: str = Field(min_length=1, max_length=100)
    latitude: float = Field(ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)
    properties: MapProperties

    @model_validator(mode="after")
    def finite_coordinates(self) -> "MapPoint":
        if not isfinite(self.latitude) or not isfinite(self.longitude):
            raise ValueError("As coordenadas devem ser números finitos.")
        return self


class MapRequest(StrictModel):
    visit_id: str = Field(min_length=1, max_length=100)
    input_hash: str = Field(min_length=1, max_length=128)
    points: list[MapPoint] = Field(min_length=1, max_length=5_000)

    @model_validator(mode="after")
    def unique_occurrence_ids(self) -> "MapRequest":
        ids = [point.occurrence_id for point in self.points]
        if len(ids) != len(set(ids)):
            raise ValueError("Há IDs de ocorrência repetidos no payload.")
        return self


class MapResponse(StrictModel):
    visit_id: str
    input_hash: str
    point_count: int
    unique_point_count: int
    has_hull: bool
    warnings: list[str]
    geojson: dict[str, Any]
    kml: str
