"""Provider-independent helpers: intent rules and bbox -> guidance.

Both the local Qwen3-VL engine and Claude go through these, so the wristband
always receives the same haptic command for the same geometry.
"""
import re
from typing import Optional

from models.schemas import GuidanceResponse, VoiceIntentResponse

LEFT_THRESHOLD = 0.35
RIGHT_THRESHOLD = 0.65
NEAR_AREA_RATIO = 0.35
TOUCHING_CM = 8.0
NEAR_CM = 20.0

STOP_WORDS_RE = re.compile(r"\b(stop|cancel|quit|abort|nevermind)\b")
HELP_PHRASES = ("what can you do", "instructions", "how do i use", "how does this work")

_PREFIXES = [
    "can you help me find my ", "can you help me find the ", "can you help me find a ", "can you help me find ",
    "help me find my ", "help me find the ", "help me find a ", "help me find ",
    "please find my ", "please find the ", "please find a ", "please find ",
    "find my ", "find the ", "find a ", "find ",
    "where are my ", "where is my ", "where's my ", "where did i leave my ", "where are the ", "where is the ",
    "look for my ", "look for the ", "look for ",
    "locate my ", "locate the ", "locate ",
]
_SUFFIXES = (" please", " for me", " thanks", " thank you")


def verb(target: str, singular: str, plural: str) -> str:
    """Pick the right verb form: 'keys are' / 'phone is' / 'glasses are' / 'glass is'."""
    t = target.strip().lower()
    is_plural = t.endswith("s") and not t.endswith(("ss", "us", "is"))
    return plural if is_plural else singular


def extract_target_fast(transcript: str) -> Optional[str]:
    clean_text = transcript.strip().lower()
    for p in _PREFIXES:
        if clean_text.startswith(p):
            target = clean_text[len(p):].rstrip(".?! ").strip()
            for s in _SUFFIXES:
                if target.endswith(s):
                    target = target[:-len(s)].rstrip(".?! ").strip()
            if target:
                return target
    return None


def rule_intent(transcript: str) -> Optional[VoiceIntentResponse]:
    """Instant rule-based intent. Returns None when an LLM should decide."""
    clean_text = transcript.strip().lower()
    if not clean_text:
        return VoiceIntentResponse(action="UNKNOWN", target=None, raw_transcript=transcript)
    if STOP_WORDS_RE.search(clean_text):
        return VoiceIntentResponse(action="STOP", target=None, raw_transcript=transcript)
    if any(w in clean_text for w in HELP_PHRASES) or clean_text in ("help", "help me"):
        return VoiceIntentResponse(action="HELP", target=None, raw_transcript=transcript)
    target = extract_target_fast(transcript)
    if target:
        return VoiceIntentResponse(action="FIND_OBJECT", target=target, raw_transcript=transcript)
    return None


def _position(center_x: float) -> str:
    if center_x < LEFT_THRESHOLD:
        return "left"
    if center_x > RIGHT_THRESHOLD:
        return "right"
    return "center"


def parse_box(result) -> Optional[tuple[float, float, float, float]]:
    """Validate a {is_target, bbox_2d} answer and return a normalized (0-1) box, or None."""
    if not isinstance(result, dict):
        return None
    is_target = result.get("is_target")
    if isinstance(is_target, str):
        is_target = is_target.strip().lower() == "true"
    bbox = result.get("bbox_2d")
    if not is_target or not isinstance(bbox, (list, tuple)) or len(bbox) != 4:
        return None
    try:
        x1, y1, x2, y2 = (min(1000.0, max(0.0, float(v))) / 1000.0 for v in bbox)
    except (TypeError, ValueError):
        return None
    x1, x2 = sorted((x1, x2))
    y1, y2 = sorted((y1, y2))
    area = (x2 - x1) * (y2 - y1)
    # Empty boxes and near-full-frame boxes are how the 2B model says "not here".
    if area <= 0.0005 or area >= 0.9:
        return None
    return x1, y1, x2, y2


def not_detected(target: str, provider: str, message: Optional[str] = None) -> GuidanceResponse:
    return GuidanceResponse(
        target=target,
        detected=False,
        image_position="none",
        voice_message=message or f"I don't see the {target} yet. Please point your camera around slowly.",
        haptic_command="STOP",
        proximity="unknown",
        provider=provider,
    )


def guidance_from_box(
    target: str,
    x_min: float,
    y_min: float,
    x_max: float,
    y_max: float,
    sensor_distance_cm: Optional[float],
    provider: str,
) -> GuidanceResponse:
    """Turn a normalized (0-1) box into direction, haptic command and spoken message."""
    center_x = (x_min + x_max) / 2.0
    area_ratio = max(0.0, x_max - x_min) * max(0.0, y_max - y_min)
    pos = _position(center_x)

    def resp(voice: str, haptic: str, proximity: str = "unknown") -> GuidanceResponse:
        return GuidanceResponse(
            target=target, detected=True, image_position=pos, voice_message=voice,
            haptic_command=haptic, proximity=proximity, provider=provider,
        )

    if sensor_distance_cm is not None:
        prox = f"{sensor_distance_cm:.1f} cm"
        if sensor_distance_cm <= TOUCHING_CM:
            return resp(f"Target reached! The {target} {verb(target, 'is', 'are')} right beneath your hand.", "TOUCHING", prox)
        if sensor_distance_cm < NEAR_CM:
            return resp(f"The {target} {verb(target, 'is', 'are')} very close to your hand.", "NEAR", prox)
    else:
        prox = "unknown"
        if area_ratio > NEAR_AREA_RATIO:
            return resp(f"Your {target} {verb(target, 'is', 'are')} right in front of you.", "NEAR", "close (visual)")

    if pos == "left":
        return resp(f"The {target} {verb(target, 'appears', 'appear')} to your left.", "LEFT", prox)
    if pos == "right":
        return resp(f"The {target} {verb(target, 'appears', 'appear')} to your right.", "RIGHT", prox)
    return resp(f"Straight ahead. The {target} {verb(target, 'is', 'are')} in front of you.", "CENTER", prox)
