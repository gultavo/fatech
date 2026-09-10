from __future__ import annotations

import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class Settings:
    ai_provider: str
    gemini_api_key: str
    gemini_model: str
    ai_timeout_seconds: float
    max_audio_bytes: int
    max_visit_diagonal_m: float

    @property
    def ai_configured(self) -> bool:
        return (
            self.ai_provider == "gemini"
            and bool(self.gemini_api_key)
            and bool(self.gemini_model)
        )


def get_settings() -> Settings:
    return Settings(
        ai_provider=os.getenv("AI_PROVIDER", "disabled").strip().lower(),
        gemini_api_key=os.getenv("GEMINI_API_KEY", "").strip(),
        gemini_model=os.getenv("GEMINI_MODEL", "").strip(),
        ai_timeout_seconds=float(os.getenv("AI_TIMEOUT_SECONDS", "45")),
        max_audio_bytes=int(os.getenv("MAX_AUDIO_BYTES", str(10 * 1024 * 1024))),
        max_visit_diagonal_m=float(
            os.getenv("MAX_VISIT_DIAGONAL_M", "200000")
        ),
    )
