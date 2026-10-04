"""Local Qwen3-VL-2B vision provider served by Ollama.

The installed `qwen3-vl:2b` tag is a *thinking* model. Through /api/chat with a
JSON `format`, it spends its token budget on hidden reasoning and returns an
empty `content`. So this service calls /api/generate with `raw: true`, a
hand-written ChatML prompt and a pre-filled empty <think></think> block. The
JSON schema is still enforced through `format`.
"""
import base64
import json
import logging
import os
import time
from io import BytesIO
from typing import Optional

import httpx
from dotenv import load_dotenv
from PIL import Image

from models.schemas import GuidanceResponse
from services.claude_service import ProviderUnavailable, split_data_url
from services.guidance import extract_target_fast, guidance_from_box, not_detected, parse_box

load_dotenv()
logger = logging.getLogger(__name__)

_VISION_SCHEMA = {
    "type": "object",
    "properties": {
        "seen_object": {"type": "string"},
        "is_target": {"type": "boolean"},
        "bbox_2d": {"type": "array", "items": {"type": "integer"}, "minItems": 4, "maxItems": 4},
    },
    "required": ["seen_object", "is_target", "bbox_2d"],
}
_TARGET_SCHEMA = {"type": "object", "properties": {"target": {"type": "string"}}, "required": ["target"]}


def _chatml(user_text: str, with_image: bool) -> str:
    image = "<|vision_start|>[img-0]<|vision_end|>" if with_image else ""
    return (
        f"<|im_start|>user\n{image}{user_text}<|im_end|>\n"
        "<|im_start|>assistant\n<think>\n\n</think>\n\n"
    )


class LocalVLMService:
    def __init__(self):
        self.base_url = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
        self.model = os.getenv("VLM_MODEL", "qwen3-vl:2b")
        self.max_side = int(os.getenv("VLM_IMAGE_MAX_SIDE", "448"))
        self.timeout_s = float(os.getenv("VLM_TIMEOUT_S", "6"))
        self.enabled = os.getenv("LOCAL_VLM_ENABLED", "true").lower() != "false"
        self._client = httpx.AsyncClient(timeout=self.timeout_s)
        # After a connection failure, skip Ollama for a while so frames go straight to Claude.
        self._down_until = 0.0

    def _prepare_image(self, image_base64: str) -> str:
        _, data = split_data_url(image_base64)
        try:
            image = Image.open(BytesIO(base64.b64decode(data))).convert("RGB")
        except Exception as e:
            raise ValueError(f"Invalid image data: {e}") from e
        image.thumbnail((self.max_side, self.max_side), Image.Resampling.BILINEAR)
        buf = BytesIO()
        image.save(buf, "JPEG", quality=85)
        return base64.b64encode(buf.getvalue()).decode()

    async def _generate(self, prompt: str, schema: dict, images: Optional[list] = None, num_predict: int = 128,
                        timeout: Optional[float] = None) -> dict:
        if not self.enabled:
            raise ProviderUnavailable("Local VLM disabled (LOCAL_VLM_ENABLED=false)")
        if time.monotonic() < self._down_until:
            raise ProviderUnavailable("Ollama recently unreachable; skipping local model")
        payload = {
            "model": self.model,
            "prompt": prompt,
            "raw": True,
            "stream": False,
            "format": schema,
            "keep_alive": "30m",
            "options": {"temperature": 0, "num_predict": num_predict},
        }
        if images:
            payload["images"] = images
        try:
            r = await self._client.post(f"{self.base_url}/api/generate", json=payload, timeout=timeout or self.timeout_s)
            r.raise_for_status()
            body = r.json()
            if body.get("error"):
                raise ProviderUnavailable(f"Ollama error: {body['error']}")
            text = (body.get("response") or "").strip()
            if not text:
                raise ProviderUnavailable("Ollama returned an empty response")
            return json.loads(text)
        except ProviderUnavailable:
            raise
        except httpx.ConnectError as e:
            self._down_until = time.monotonic() + 15
            raise ProviderUnavailable(f"Ollama unreachable at {self.base_url}: {e}") from e
        except Exception as e:
            raise ProviderUnavailable(f"Local VLM call failed: {type(e).__name__}: {e}") from e

    async def analyze(
        self,
        transcript: str,
        image_base64: str,
        sensor_distance_cm: Optional[float] = None,
        target: Optional[str] = None,
    ) -> GuidanceResponse:
        """Ground the target in the frame. Raises ProviderUnavailable if the model can't answer."""
        target = target or extract_target_fast(transcript) or "object"
        image = self._prepare_image(image_base64)
        question = (
            f"Find the {target}. Report what object you see at the most likely location, "
            f"whether it really is the {target}, and its bounding box [x1,y1,x2,y2] in 0-1000 coordinates."
        )
        result = await self._generate(_chatml(question, with_image=True), _VISION_SCHEMA, images=[image])
        logger.info(f"Local VLM: {result}")
        box = parse_box(result)
        if box is None:
            return not_detected(target, "local")
        return guidance_from_box(target, *box, sensor_distance_cm, "local")

    async def extract_target(self, transcript: str) -> Optional[str]:
        prompt = _chatml(
            "A visually impaired user said the sentence below. What object do they want to find? "
            f'Answer with a short noun phrase (e.g. keys, water bottle, phone).\nSentence: "{transcript}"',
            with_image=False,
        )
        data = await self._generate(prompt, _TARGET_SCHEMA, num_predict=32)
        target = (data.get("target") or "").strip().lower()
        return target or None

    async def warm_up(self) -> None:
        """Load the model into GPU memory at startup so the first frame is fast."""
        if not self.enabled:
            return
        try:
            img = Image.new("RGB", (64, 64), "white")
            buf = BytesIO()
            img.save(buf, "JPEG")
            await self._generate(
                _chatml("Find the cup.", with_image=True), _VISION_SCHEMA,
                images=[base64.b64encode(buf.getvalue()).decode()], num_predict=64, timeout=120,
            )
            logger.info(f"Local VLM {self.model} warmed up")
        except Exception as e:
            logger.warning(f"Local VLM warm-up failed (Claude fallback will be used): {e}")

    async def status(self) -> dict:
        info = {"local_enabled": self.enabled, "ollama_reachable": False, "model_installed": False, "model_loaded": False}
        if not self.enabled:
            return info
        try:
            tags = (await self._client.get(f"{self.base_url}/api/tags", timeout=2)).json()
            info["ollama_reachable"] = True
            self._down_until = 0.0
            info["model_installed"] = any(m.get("name") == self.model for m in tags.get("models", []))
            ps = (await self._client.get(f"{self.base_url}/api/ps", timeout=2)).json()
            info["model_loaded"] = any(m.get("name") == self.model for m in ps.get("models", []))
        except Exception:
            pass
        return info

    async def close(self) -> None:
        await self._client.aclose()
