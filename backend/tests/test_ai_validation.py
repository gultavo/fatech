from __future__ import annotations

import pytest

from app.ai import _validate_evidence
from app.errors import AppError
from app.schemas import (
    AIExtractionPayload,
    ExtractRequest,
    ExtractionFields,
    FieldSuggestion,
    Source,
)


def empty() -> FieldSuggestion:
    return FieldSuggestion(value=None, source_id=None, evidence=None)


def test_explicit_evidence_is_accepted_and_technical_opinion_stays_null() -> None:
    request = ExtractRequest(
        occurrence_id="occ-1",
        revision=1,
        input_hash="hash",
        sources=[Source(id="written_report", text="Há possível assoreamento.")],
    )
    payload = AIExtractionPayload(
        fields=ExtractionFields(
            visit_date=empty(),
            visit_type=empty(),
            enterprise=empty(),
            location_reference=empty(),
            environmental_occurrence=FieldSuggestion(
                value="Possível assoreamento",
                source_id="written_report",
                evidence="possível assoreamento",
            ),
            technical_opinion=empty(),
        ),
        warnings=[],
    )
    _validate_evidence(payload, request)
    assert payload.fields.technical_opinion.value is None


def test_invented_evidence_rejects_entire_ai_response() -> None:
    request = ExtractRequest(
        occurrence_id="occ-1",
        revision=1,
        input_hash="hash",
        sources=[Source(id="written_report", text="Não foi possível avaliar.")],
    )
    payload = AIExtractionPayload(
        fields=ExtractionFields(
            visit_date=empty(),
            visit_type=empty(),
            enterprise=empty(),
            location_reference=empty(),
            environmental_occurrence=FieldSuggestion(
                value="Sem irregularidade",
                source_id="written_report",
                evidence="Sem irregularidade",
            ),
            technical_opinion=empty(),
        ),
        warnings=[],
    )
    with pytest.raises(AppError) as captured:
        _validate_evidence(payload, request)
    assert captured.value.code == "AI_INVALID_EVIDENCE"
