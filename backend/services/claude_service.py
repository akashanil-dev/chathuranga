import os
import json
import logging
from typing import Optional
from dotenv import load_dotenv
from models.schemas import GuidanceResponse, GuidanceRequest
from services.guidance import extract_target_fast, guidance_from_box, not_detected, parse_box

load_dotenv()
logger = logging.getLogger(__name__)


class ProviderUnavailable(Exception):
    """Raised when an AI provider cannot answer, so the router can fall back."""


def _strip_fences(content: str) -> str:
    content = content.strip()
    if content.startswith("```"):
        content = content.split("\n", 1)[1].rsplit("```", 1)[0].strip()
    return content


def split_data_url(image_base64: str) -> tuple[str, str]:
    """Return (media_type, raw_base64) for a plain or data: URL base64 image."""
    media_type = "image/jpeg"
    data = image_base64
    if data.startswith("data:"):
        header, data = data.split(",", 1)
        if "image/png" in header:
            media_type = "image/png"
        elif "image/webp" in header:
            media_type = "image/webp"
    elif data.startswith("iVBOR"):
        media_type = "image/png"
    return media_type, data


class ClaudeService:
    """Anthropic Claude provider. Used as the fallback when the local VLM fails."""

    def __init__(self):
        self.api_key = os.getenv("ANTHROPIC_API_KEY")
        self.model = os.getenv("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
        self.timeout_s = float(os.getenv("CLAUDE_TIMEOUT_S", "8"))
        self.client = None
        if self.api_key and self.api_key.startswith("your_"):
            logger.warning("ANTHROPIC_API_KEY is still the placeholder; running without Claude.")
            self.api_key = None
        if self.api_key:
            try:
                import ssl
                import anthropic
                # An explicit stdlib SSL context avoids the SDK's truststore default, which hits
                # infinite recursion in ssl.verify_mode on Python 3.10 ("Connection error.").
                self.client = anthropic.AsyncAnthropic(
                    api_key=self.api_key,
                    timeout=self.timeout_s,
                    max_retries=0,
                    http_client=anthropic.DefaultAsyncHttpxClient(verify=ssl.create_default_context()),
                )
                logger.info(f"Initialized Anthropic client with model: {self.model}")
            except Exception as e:
                logger.warning(f"Failed to initialize Anthropic client: {e}")

    @property
    def available(self) -> bool:
        return self.client is not None

    async def _ask(self, content, max_tokens: int, system: Optional[str] = None) -> dict:
        if not self.client:
            raise ProviderUnavailable("Claude is not configured (no ANTHROPIC_API_KEY)")
        kwargs = {"system": system} if system else {}
        try:
            response = await self.client.messages.create(
                model=self.model,
                max_tokens=max_tokens,
                messages=[{"role": "user", "content": content}],
                **kwargs,
            )
            text_block = next((b for b in response.content if getattr(b, "type", None) == "text"), None)
            return json.loads(_strip_fences(text_block.text if text_block else "{}"))
        except Exception as e:
            raise ProviderUnavailable(f"Claude call failed: {e}") from e

    async def extract_target(self, transcript: str) -> Optional[str]:
        """LLM target extraction for sentences the fast rules could not parse."""
        prompt = (
            "You are SENSE, an intent extractor for a visually impaired user's assistive device.\n"
            f'Transcript: "{transcript}"\n'
            'Return ONLY JSON: {"target": "<short noun phrase for the object to find, e.g. keys, water bottle, phone>"}'
        )
        data = await self._ask(prompt, max_tokens=60)
        target = (data.get("target") or "").strip()
        return target or None

    def calculate_guidance(self, req: GuidanceRequest) -> GuidanceResponse:
        """Deterministic guidance from on-device detector boxes (no LLM)."""
        target = req.target.lower().strip()
        boxes = req.bounding_boxes or []
        matched = next((b for b in boxes if target in b.label.lower() or b.label.lower() in target), None)
        if not matched and boxes:
            matched = max(boxes, key=lambda b: b.confidence)
        if not matched:
            return not_detected(target, "rules", f"I don't see the {target} yet. Please scan slowly.")
        return guidance_from_box(
            target, matched.x_min, matched.y_min, matched.x_max, matched.y_max, req.sensor_distance_cm, "rules"
        )

    async def analyze_multimodal_vision(
        self,
        transcript: str,
        image_base64: str,
        sensor_distance_cm: Optional[float] = None,
        target: Optional[str] = None,
    ) -> GuidanceResponse:
        """Ground the target with Claude Vision. Raises ProviderUnavailable on failure."""
        target = target or extract_target_fast(transcript) or "object"
        media_type, data = split_data_url(image_base64)
        system = (
            "You are SENSE, helping a visually impaired user find an object with a phone camera. "
            "Look for the requested object. Return ONLY JSON: "
            '{"seen_object": "<what is at that spot>", "is_target": <true/false>, '
            '"bbox_2d": [x1, y1, x2, y2]} with coordinates 0-1000 relative to the image. '
            "If the object is not visible, set is_target=false and bbox_2d=[0,0,0,0]. No other text."
        )
        result = await self._ask(
            [
                {"type": "image", "source": {"type": "base64", "media_type": media_type, "data": data}},
                {"type": "text", "text": f"Find the {target}. User said: '{transcript}'"},
            ],
            max_tokens=150,
            system=system,
        )
        box = parse_box(result)
        if box is None:
            return not_detected(target, "claude")
        return guidance_from_box(target, *box, sensor_distance_cm, "claude")
