import os
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
        self.client = None
        if self.api_key:
            try:
                import anthropic
                self.client = anthropic.Anthropic(api_key=self.api_key)
            except Exception as e:
                logger.warning(f"Failed to initialize Anthropic client: {e}")

    async def parse_intent(self, transcript: str) -> VoiceIntentResponse:
        """Parses user speech into structured intent using Claude or fallback heuristic."""
        clean_text = transcript.strip().lower()
        if not clean_text:
            return VoiceIntentResponse(action="UNKNOWN", target=None, raw_transcript=transcript)

        # Check for stop / cancel
        if any(w in clean_text for w in ["stop", "cancel", "quit", "abort", "nevermind"]):
            return VoiceIntentResponse(action="STOP", target=None, raw_transcript=transcript)

        # Check for help (only if not asking to help find something)
        if any(w in clean_text for w in ["what can you do", "instructions", "how do i use", "how does this work"]) or (clean_text in ["help", "help me"]):
            return VoiceIntentResponse(action="HELP", target=None, raw_transcript=transcript)

        # Try Claude if available
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
                    model="claude-3-haiku-20240307",
                    max_tokens=100,
                    temperature=0.0,
                    messages=[{"role": "user", "content": prompt}]
                )
                content = response.content[0].text.strip()
                # Parse JSON
                data = json.loads(content)
                return VoiceIntentResponse(
                    action=data.get("action", "FIND_OBJECT"),
                    target=data.get("target"),
                    raw_transcript=transcript
                )
            except Exception as e:
                logger.error(f"Claude API call failed: {e}. Falling back to rule-based parser.")

        # Fallback heuristic
        target = clean_text
        prefixes = [
            "can you help me find my ", "can you help me find the ", "can you help me find a ", "can you help me find ",
            "help me find my ", "help me find the ", "help me find a ", "help me find ",
            "please find my ", "please find the ", "please find a ", "please find ",
            "find my ", "find the ", "find a ", "find ",
            "where are my ", "where is my ", "where's my ", "where did i leave my ", "where are the ", "where is the ",
            "look for my ", "look for the ", "look for ",
            "locate my ", "locate the ", "locate "
        ]
        for p in prefixes:
            if target.startswith(p):
                target = target[len(p):].strip()
                break
        
        target = target.rstrip(".?! ")
        return VoiceIntentResponse(
            action="FIND_OBJECT",
            target=target if target else "object",
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
        sensor_distance_cm: Optional[float] = None
    ) -> GuidanceResponse:
        """
        Multimodal scene understanding using Claude 3.5 Vision.
        Accepts user voice question + phone camera photo and generates
        contextual spoken guidance and directional haptic commands.
        """
        intent = await self.parse_intent(transcript)
        target = intent.target or "object"

        if self.client:
            try:
                clean_b64 = image_base64
                if "," in clean_b64:
                    clean_b64 = clean_b64.split(",", 1)[1]

                system_prompt = (
                    "You are SENSE, an AI assistant for a visually impaired user. "
                    "The user is holding a phone camera facing their surroundings. "
                    "Examine the image carefully to find the object requested in the user's speech.\n"
                    "1. If found, determine its horizontal position: 'left' (left third of image), 'center' (middle third), or 'right' (right third).\n"
                    "2. Determine haptic command: 'LEFT', 'RIGHT', 'CENTER', 'NEAR', or 'STOP'. If the object appears close or large, use 'NEAR'.\n"
                    "3. Provide a clear, natural spoken guidance message in under 2 concise sentences (e.g. 'I see your keys to your right, next to the keyboard.').\n"
                    "4. If the object is not visible, set detected=false, image_position='none', haptic_command='STOP', and advise the user to pan slowly.\n"
                    "Return ONLY a valid JSON object matching this schema:\n"
                    "{\n"
                    '  "target": "<object name>",\n'
                    '  "detected": <true/false>,\n'
                    '  "image_position": "<left/center/right/none>",\n'
                    '  "voice_message": "<spoken guidance>",\n'
                    '  "haptic_command": "<LEFT/RIGHT/CENTER/NEAR/STOP>",\n'
                    '  "proximity": "<close/medium/far/unknown>"\n'
                    "}\n"
                    "No markdown fences, no other text."
                )

                response = self.client.messages.create(
                    model="claude-3-5-sonnet-20241022",
                    max_tokens=250,
                    temperature=0.1,
                    system=system_prompt,
                    messages=[
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "image",
                                    "source": {
                                        "type": "base64",
                                        "media_type": "image/jpeg",
                                        "data": clean_b64,
                                    },
                                },
                                {
                                    "type": "text",
                                    "text": f"User question: '{transcript}'",
                                },
                            ],
                        }
                    ],
                )
                content = response.content[0].text.strip()
                if content.startswith("```"):
                    content = content.split("\n", 1)[1].rsplit("```", 1)[0].strip()
                data = json.loads(content)
                return GuidanceResponse(**data)
            except Exception as e:
                logger.error(f"Claude Vision API call error: {e}")

        # Fallback guidance when offline or invalid API key
        return GuidanceResponse(
            target=target,
            detected=True,
            image_position="center",
            voice_message=f"I am searching for your {target}. Point the camera straight ahead.",
            haptic_command="CENTER",
            proximity="unknown"
        )
