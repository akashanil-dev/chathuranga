import os
import re
import json
import logging
from typing import Optional
from dotenv import load_dotenv
from models.schemas import VoiceIntentResponse, GuidanceResponse, GuidanceRequest

load_dotenv()
logger = logging.getLogger(__name__)

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")

class ClaudeService:
    def __init__(self):
        self.api_key = os.getenv("ANTHROPIC_API_KEY")
        self.model = os.getenv("ANTHROPIC_MODEL", "claude-haiku-4-5-20251001")
        self.client = None
        if self.api_key:
            try:
                import anthropic
                self.client = anthropic.Anthropic(api_key=self.api_key)
                logger.info(f"Initialized Anthropic client with model: {self.model}")
            except Exception as e:
                logger.warning(f"Failed to initialize Anthropic client: {e}")

    @staticmethod
    def extract_target_fast(transcript: str) -> Optional[str]:
        if not transcript or not transcript.strip():
            return None
        clean = transcript.strip().lower()
        clean = re.sub(r'[\.\?\!\,\;]+$', '', clean).strip()

        # Repeatedly strip leading conversational prefixes, fillers, and command verbs
        prefix_patterns = [
            r'^(?:hey\s+|ok\s+)?sense\s+',
            r'^(?:hello|hi|please|um|uh)\s+',
            r'^(?:can\s+you|could\s+you|would\s+you)\s+(?:please\s+)?',
            r'^(?:i\s+want\s+to|i\s+need\s+to|i\s+would\s+like\s+to|i\'m\s+trying\s+to|im\s+trying\s+to)\s+',
            r'^(?:i\s+am\s+looking\s+for|i\'m\s+looking\s+for|im\s+looking\s+for|looking\s+for)\s+',
            r'^(?:help\s+me|help\s+me\s+to)\s+',
            r'^(?:find|locate|search\s+for|look\s+for|detect|track|spot|see|show\s+me)\s+(?:me\s+)?',
            r'^(?:where\s+is|where\s+are|where\'s|wheres|where\s+did\s+i\s+leave|where\s+did\s+i\s+put)\s+',
            r'^(?:my|the|a|an|some)\s+',
        ]

        changed = True
        while changed:
            changed = False
            for p in prefix_patterns:
                m = re.match(p, clean)
                if m:
                    clean = clean[m.end():].strip()
                    changed = True

        # Strip trailing polite suffixes
        clean = re.sub(r'\s+(?:please|for\s+me|thanks|thank\s+you|now)$', '', clean).strip()
        clean = re.sub(r'^(?:my|the|a|an)\s+', '', clean).strip()

        return clean if clean else None

    async def parse_intent(self, transcript: str) -> VoiceIntentResponse:
        """Parses user speech into structured intent using fast rules or Claude Haiku."""
        clean_text = transcript.strip().lower()
        if not clean_text:
            return VoiceIntentResponse(action="UNKNOWN", target=None, raw_transcript=transcript)

        # Check for stop / cancel (0ms)
        if any(w in clean_text for w in ["stop", "cancel", "quit", "abort", "nevermind"]):
            return VoiceIntentResponse(action="STOP", target=None, raw_transcript=transcript)

        # Check for help (0ms)
        if any(w in clean_text for w in ["what can you do", "instructions", "how do i use", "how does this work"]) or (clean_text in ["help", "help me"]):
            return VoiceIntentResponse(action="HELP", target=None, raw_transcript=transcript)

        # Fast heuristic extraction (0ms latency for common phrases like "find my keys")
        fast_target = self.extract_target_fast(transcript)
        if fast_target:
            return VoiceIntentResponse(
                action="FIND_OBJECT",
                target=fast_target,
                raw_transcript=transcript
            )

        # Try fast Claude Haiku if available for complex or ambiguous sentences
        if self.client:
            try:
                prompt = f"""You are SENSE, an AI intent extractor for a visually impaired user's assistive device.
Extract the target object the user wants to locate from the following transcript:
Transcript: "{transcript}"

Return ONLY a valid JSON object with the following schema:
{{
  "action": "FIND_OBJECT",
  "target": "<normalized single-word or short noun phrase for the object, e.g., 'keys', 'water bottle', 'phone'>"
}}
Do not include markdown fences or any other text."""
                
                response = self.client.messages.create(
                    model=self.model,
                    max_tokens=100,
                    messages=[{"role": "user", "content": prompt}]
                )
                text_block = next((b for b in response.content if getattr(b, "type", None) == "text"), None)
                content = text_block.text.strip() if text_block and hasattr(text_block, "text") else "{}"
                if content.startswith("```"):
                    content = content.split("\n", 1)[1].rsplit("```", 1)[0].strip()
                data = json.loads(content)
                return VoiceIntentResponse(
                    action=data.get("action", "FIND_OBJECT"),
                    target=data.get("target"),
                    raw_transcript=transcript
                )
            except Exception as e:
                logger.error(f"Claude API call failed: {e}. Falling back to default target.")

        return VoiceIntentResponse(
            action="FIND_OBJECT",
            target=clean_text.rstrip(".?! "),
            raw_transcript=transcript
        )

    def calculate_guidance(self, req: GuidanceRequest) -> GuidanceResponse:
        """
        Generates structured guidance matching:
        {
          "target": "keys",
          "detected": true,
          "image_position": "right",
          "voice_message": "The keys appear to your right.",
          "haptic_command": "RIGHT",
          "proximity": "unknown"
        }
        """
        target = req.target.lower().strip()
        matched_box = None

        if req.bounding_boxes:
            for box in req.bounding_boxes:
                label = box.label.lower()
                if target in label or label in target:
                    matched_box = box
                    break
            if not matched_box:
                # Take highest confidence box if nothing matched exactly
                matched_box = max(req.bounding_boxes, key=lambda b: b.confidence, default=None)

        if not matched_box:
            return GuidanceResponse(
                target=target,
                detected=False,
                image_position="none",
                voice_message=f"I don't see the {target} yet. Please scan slowly.",
                haptic_command="STOP",
                proximity="unknown"
            )

        # Center X in normalized coordinate [0.0, 1.0]
        center_x = (matched_box.x_min + matched_box.x_max) / 2.0
        width = matched_box.x_max - matched_box.x_min
        height = matched_box.y_max - matched_box.y_min
        area_ratio = width * height

        # Proximity estimation
        proximity_str = "unknown"
        if req.sensor_distance_cm is not None:
            proximity_str = f"{req.sensor_distance_cm:.1f} cm"
            if req.sensor_distance_cm < 20.0:
                return GuidanceResponse(
                    target=target,
                    detected=True,
                    image_position="center" if 0.35 <= center_x <= 0.65 else ("left" if center_x < 0.35 else "right"),
                    voice_message=f"The {target} is very close to your hand.",
                    haptic_command="NEAR",
                    proximity=proximity_str
                )
        elif area_ratio > 0.35:
            proximity_str = "close (visual)"
            return GuidanceResponse(
                target=target,
                detected=True,
                image_position="center" if 0.35 <= center_x <= 0.65 else ("left" if center_x < 0.35 else "right"),
                voice_message=f"Your {target} is right in front of you.",
                haptic_command="NEAR",
                proximity=proximity_str
            )

        # Direction calculation
        if center_x < 0.35:
            pos = "left"
            voice = f"The {target} appears to your left."
            haptic = "LEFT"
        elif center_x > 0.65:
            pos = "right"
            voice = f"The {target} appears to your right."
            haptic = "RIGHT"
        else:
            pos = "center"
            voice = f"Straight ahead. The {target} is in front of you."
            haptic = "CENTER"

        return GuidanceResponse(
            target=target,
            detected=True,
            image_position=pos,
            voice_message=voice,
            haptic_command=haptic,
            proximity=proximity_str
        )

    async def analyze_multimodal_vision(
        self,
        transcript: str,
        image_base64: str,
        target: Optional[str] = None,
        sensor_distance_cm: Optional[float] = None
    ) -> GuidanceResponse:
        """
        Multimodal scene understanding using fast Claude Vision (Haiku).
        Accepts user voice question + phone camera photo and generates
        contextual spoken guidance and directional haptic commands in ~1.5 seconds.
        """
        clean_target = (target and target.strip()) or self.extract_target_fast(transcript) or "object"

        if self.client:
            try:
                clean_b64 = image_base64
                media_type = "image/jpeg"
                if clean_b64.startswith("data:"):
                    header, clean_b64 = clean_b64.split(",", 1)
                    if "image/png" in header:
                        media_type = "image/png"
                    elif "image/webp" in header:
                        media_type = "image/webp"
                elif clean_b64.startswith("iVBOR"):
                    media_type = "image/png"
                system_prompt = (
                    f"You are SENSE, an AI assistant for a visually impaired user holding a phone camera. "
                    f"The user is searching for: '{clean_target}'. "
                    f"Examine the image carefully to find the '{clean_target}'.\n"
                    f"1. If found, determine its horizontal position: 'left' (left third of image), 'center' (middle third), or 'right' (right third).\n"
                    f"2. Determine haptic command: 'LEFT', 'RIGHT', 'CENTER', 'NEAR', or 'STOP'. If the object appears close or large, use 'NEAR'.\n"
                    f"3. Provide a clear, natural spoken guidance message in under 2 concise sentences (e.g. 'I see your {clean_target} to your right, next to the keyboard.').\n"
                    f"4. If the '{clean_target}' is not visible, set detected=false, image_position='none', haptic_command='STOP', and advise the user to pan slowly.\n"
                    f"Return ONLY a valid JSON object matching this schema:\n"
                    f"{{\n"
                    f'  "target": "{clean_target}",\n'
                    f'  "detected": <true/false>,\n'
                    f'  "image_position": "<left/center/right/none>",\n'
                    f'  "voice_message": "<spoken guidance>",\n'
                    f'  "haptic_command": "<LEFT/RIGHT/CENTER/NEAR/TOUCHING/STOP>",\n'
                    f'  "proximity": "<close/medium/far/unknown>"\n'
                    f"}}\n"
                    f"No markdown fences, no other text."
                )

                response = self.client.messages.create(
                    model=self.model,
                    max_tokens=250,
                    system=system_prompt,
                    messages=[
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "image",
                                    "source": {
                                        "type": "base64",
                                        "media_type": media_type,
                                        "data": clean_b64,
                                    },
                                },
                                {
                                    "type": "text",
                                    "text": f"User question: '{transcript}'. Target to find: '{clean_target}'",
                                },
                            ],
                        }
                    ],
                )
                text_block = next((b for b in response.content if getattr(b, "type", None) == "text"), None)
                content = text_block.text.strip() if text_block and hasattr(text_block, "text") else "{}"
                if content.startswith("```"):
                    content = content.split("\n", 1)[1].rsplit("```", 1)[0].strip()
                data = json.loads(content)
                if "detected" in data and isinstance(data["detected"], str):
                    data["detected"] = data["detected"].lower() == "true"
                if not data.get("image_position"):
                    data["image_position"] = "none" if not data.get("detected") else "center"
                data["target"] = clean_target
                if not data.get("voice_message"):
                    data["voice_message"] = f"Looking for your {target}."
                if not data.get("proximity"):
                    data["proximity"] = "unknown"
                if sensor_distance_cm is not None and data.get("detected", False):
                    data["proximity"] = f"{sensor_distance_cm:.1f} cm"
                    if sensor_distance_cm <= 8.0:
                        data["haptic_command"] = "TOUCHING"
                        data["voice_message"] = f"Target reached! Your {target} is right under your hand."
                    elif sensor_distance_cm <= 25.0:
                        data["haptic_command"] = "NEAR"
                return GuidanceResponse(**data)
            except Exception as e:
                logger.error(f"Claude Vision API call error: {e}")

        # Fallback guidance when offline or invalid API key
        return GuidanceResponse(
            target=target,
            detected=False,
            image_position="none",
            voice_message=f"I don't see the {target} yet. Please point your camera around slowly.",
            haptic_command="STOP",
            proximity="unknown"
        )
