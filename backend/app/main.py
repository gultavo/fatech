from __future__ import annotations

import asyncio

from fastapi import FastAPI, File, Form, UploadFile

from .ai import make_ai_service
from .config import get_settings
from .errors import AppError, install_error_handlers
from .geometry import generate_geodata
from .kml import build_kml
from .schemas import ExtractRequest, ExtractResponse, MapRequest, MapResponse

app = FastAPI(
    title="FAtech Processing API",
    version="1.0.0",
    description="API local, sem banco central, para IA e geoprocessamento do MVP.",
)
install_error_handlers(app)

ALLOWED_AUDIO_TYPES = {
    "audio/mp4",
    "audio/m4a",
    "audio/aac",
    "audio/mpeg",
    "audio/wav",
    "audio/x-wav",
    "audio/ogg",
    "audio/webm",
}


@app.get("/health")
async def health() -> dict:
    settings = get_settings()
    return {
        "status": "ok",
        "capabilities": {"maps": True, "ai_configured": settings.ai_configured},
    }


@app.post("/api/v1/audio/transcribe")
async def transcribe_audio(
    file: UploadFile = File(...),
    occurrence_id: str = Form(..., min_length=1, max_length=100),
    attachment_id: str = Form(..., min_length=1, max_length=100),
) -> dict:
    settings = get_settings()
    content_type = (file.content_type or "").lower()
    if content_type not in ALLOWED_AUDIO_TYPES:
        await file.close()
        raise AppError(
            "UNSUPPORTED_AUDIO",
            "Formato de áudio não aceito. Use M4A/AAC, MP3, WAV, OGG ou WebM.",
            415,
            {"content_type": content_type},
        )
    contents = bytearray()
    try:
        while chunk := await file.read(1024 * 1024):
            contents.extend(chunk)
            if len(contents) > settings.max_audio_bytes:
                raise AppError(
                    "AUDIO_TOO_LARGE",
                    "O áudio excede o limite de 10 MiB.",
                    413,
                    {"max_bytes": settings.max_audio_bytes},
                )
        if not contents:
            raise AppError("EMPTY_AUDIO", "O arquivo de áudio está vazio.", 422)
        service = make_ai_service(settings)
        try:
            transcript, warnings = await asyncio.wait_for(
                asyncio.to_thread(service.transcribe, bytes(contents), content_type),
                timeout=settings.ai_timeout_seconds,
            )
        except TimeoutError as exc:
            raise AppError(
                "AI_TIMEOUT",
                "O processamento do áudio excedeu o tempo limite. Tente novamente.",
                504,
            ) from exc
        return {
            "occurrence_id": occurrence_id,
            "attachment_id": attachment_id,
            "transcript": transcript,
            "warnings": warnings,
        }
    finally:
        contents.clear()
        await file.close()


@app.post("/api/v1/forms/extract", response_model=ExtractResponse)
async def extract_form(request: ExtractRequest) -> ExtractResponse:
    settings = get_settings()
    service = make_ai_service(settings)
    try:
        payload = await asyncio.wait_for(
            asyncio.to_thread(service.extract, request),
            timeout=settings.ai_timeout_seconds,
        )
    except TimeoutError as exc:
        raise AppError(
            "AI_TIMEOUT",
            "A extração excedeu o tempo limite. Tente novamente.",
            504,
        ) from exc
    return ExtractResponse(
        occurrence_id=request.occurrence_id,
        revision=request.revision,
        input_hash=request.input_hash,
        fields=payload.fields,
        warnings=payload.warnings,
    )


@app.post("/api/v1/maps/generate", response_model=MapResponse)
async def generate_map(request: MapRequest) -> MapResponse:
    settings = get_settings()
    geojson, hull, warnings, unique_count = await asyncio.to_thread(
        generate_geodata, request, settings.max_visit_diagonal_m
    )
    kml = await asyncio.to_thread(build_kml, request, hull)
    return MapResponse(
        visit_id=request.visit_id,
        input_hash=request.input_hash,
        point_count=len(request.points),
        unique_point_count=unique_count,
        has_hull=hull is not None,
        warnings=warnings,
        geojson=geojson,
        kml=kml,
    )
