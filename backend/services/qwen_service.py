import os
import socket

# Force IPv4 preference for network requests to prevent AWS CDN IPv6 timeouts
_orig_getaddrinfo = socket.getaddrinfo
def _ipv4_getaddrinfo(*args, **kwargs):
    responses = _orig_getaddrinfo(*args, **kwargs)
    return [r for r in responses if r[0] == socket.AF_INET] or responses
socket.getaddrinfo = _ipv4_getaddrinfo

os.environ["HF_HUB_DISABLE_XET"] = "1"
import re
import json
import base64
import logging
from io import BytesIO
from typing import Optional, Tuple
from PIL import Image
from models.schemas import VoiceIntentResponse, GuidanceResponse, GuidanceRequest

import threading

logger = logging.getLogger(__name__)

class QwenVLService:
    def __init__(self, model_id: str = "Qwen/Qwen2-VL-2B-Instruct"):
        self.model_id = model_id
        self.model = None
        self.processor = None
        self.device = "cpu"
        self._is_loaded = False
        self._is_loading = False
        self._lock = threading.Lock()

    @property
    def is_loaded(self) -> bool:
        return self._is_loaded

    @property
    def is_loading(self) -> bool:
        return self._is_loading

    def load_model(self):
        """Loads Qwen2-VL-2B model into RAM for local inference."""
        if self._is_loaded:
            return
        with self._lock:
            if self._is_loaded or self._is_loading:
                return
            self._is_loading = True

        try:
            import torch
            torch.set_num_threads(4)
            from transformers import Qwen2VLForConditionalGeneration, AutoProcessor

            logger.info(f"Loading local VLM {self.model_id} on {self.device}...")
            # Use bfloat16 on CPU with AVX-512 / VNNI
            self.model = Qwen2VLForConditionalGeneration.from_pretrained(
                self.model_id,
                torch_dtype=torch.bfloat16,
                device_map="cpu",
                low_cpu_mem_usage=True
            )
            self.processor = AutoProcessor.from_pretrained(
                self.model_id,
                min_pixels=128 * 128,
                max_pixels=256 * 256
            )
            self._is_loaded = True
            logger.info(f"Local {self.model_id} loaded successfully into memory!")
        except Exception as e:
            logger.error(f"Failed to load local Qwen2-VL model: {e}")
            self._is_loaded = False
        finally:
            self._is_loading = False

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

    def parse_intent(self, transcript: str) -> VoiceIntentResponse:
        clean = transcript.strip()
        if not clean:
            return VoiceIntentResponse(action="UNKNOWN", target=None, raw_transcript=transcript)

        lower = clean.lower()
        if any(w in lower for w in ["stop", "cancel", "quit", "abort", "nevermind"]):
            return VoiceIntentResponse(action="STOP", target=None, raw_transcript=transcript)

        if any(w in lower for w in ["what can you do", "instructions", "how do i use", "how does this work"]) or (lower in ["help", "help me"]):
            return VoiceIntentResponse(action="HELP", target=None, raw_transcript=transcript)

        fast_target = self.extract_target_fast(transcript)
        return VoiceIntentResponse(
            action="FIND_OBJECT",
            target=fast_target if fast_target else "object",
            raw_transcript=transcript
        )

    def analyze_scene_with_grounding(
        self,
        transcript: str,
        image_base64: str,
        target: Optional[str] = None,
        sensor_distance_cm: Optional[float] = None
    ) -> GuidanceResponse:
        """
        Executes local open-vocabulary visual grounding with Qwen2-VL-2B.
        Extracts exact bounding boxes [ymin, xmin, ymax, xmax] normalized to [0, 1000].
        """
        target = (target and target.strip()) or self.extract_target_fast(transcript) or "object"

        if not self._is_loaded:
            self.load_model()

        if not self._is_loaded or self.model is None:
            # Fallback heuristic
            return GuidanceResponse(
                target=target,
                detected=False,
                image_position="none",
                voice_message=f"Local vision model initializing. Please scan slowly for {target}.",
                haptic_command="STOP",
                proximity="unknown"
            )

        try:
            import torch
            from qwen_vl_utils import process_vision_info

            # Decode base64 to PIL Image
            clean_b64 = image_base64
            if "," in clean_b64:
                clean_b64 = clean_b64.split(",", 1)[1]
            img_bytes = base64.b64decode(clean_b64)
            image = Image.open(BytesIO(img_bytes)).convert("RGB")
            # Downscale image to thumbnail to minimize vision tokens on CPU
            image.thumbnail((256, 256), Image.Resampling.BILINEAR)

            # Visual grounding prompt for Qwen2-VL
            prompt = (
                f"Locate the {target} in this image. "
                f"If the {target} is visible, output its bounding box as: <|box_start|>(ymin,xmin),(ymax,xmax)<|box_end|>. "
                f"If the {target} is NOT in the image, output 'NOT_FOUND'."
            )

            messages = [
                {
                    "role": "user",
                    "content": [
                        {"type": "image", "image": image},
                        {"type": "text", "text": prompt}
                    ]
                }
            ]

            text = self.processor.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
            image_inputs, video_inputs = process_vision_info(messages)
            inputs = self.processor(
                text=[text],
                images=image_inputs,
                videos=video_inputs,
                padding=True,
                return_tensors="pt"
            ).to(self.device)

            with torch.no_grad():
                generated_ids = self.model.generate(
                    **inputs,
                    max_new_tokens=24,
                    do_sample=False
                )
                generated_ids_trimmed = [
                    out_ids[len(in_ids):] for in_ids, out_ids in zip(inputs.input_ids, generated_ids)
                ]
                output_text = self.processor.batch_decode(
                    generated_ids_trimmed,
                    skip_special_tokens=False,
                    clean_up_tokenization_spaces=False
                )[0]

            logger.info(f"Qwen2-VL local output: {output_text}")

            # Parse bounding box: <|box_start|>(ymin,xmin),(ymax,xmax)<|box_end|>
            # coordinates are normalized to [0, 1000]
            box_match = re.search(r"\((\d+),(\d+)\),\((\d+),(\d+)\)", output_text)
            if box_match and "not_found" not in output_text.lower():
                ymin = int(box_match.group(1)) / 1000.0
                xmin = int(box_match.group(2)) / 1000.0
                ymax = int(box_match.group(3)) / 1000.0
                xmax = int(box_match.group(4)) / 1000.0

                center_x = (xmin + xmax) / 2.0
                width = xmax - xmin
                height = ymax - ymin
                area_ratio = width * height

                # Proximity estimation
                proximity_str = "unknown"
                if sensor_distance_cm is not None:
                    proximity_str = f"{sensor_distance_cm:.1f} cm"
                    if sensor_distance_cm <= 8.0:
                        return GuidanceResponse(
                            target=target,
                            detected=True,
                            image_position="center",
                            voice_message=f"Target reached! Your {target} is right beneath your hand.",
                            haptic_command="TOUCHING",
                            proximity=proximity_str
                        )
                    elif sensor_distance_cm <= 25.0:
                        return GuidanceResponse(
                            target=target,
                            detected=True,
                            image_position="center",
                            voice_message=f"Approaching {target}. Reach forward slowly.",
                            haptic_command="NEAR",
                            proximity=proximity_str
                        )
                elif area_ratio >= 0.30:
                    proximity_str = "close (visual)"
                    return GuidanceResponse(
                        target=target,
                        detected=True,
                        image_position="center",
                        voice_message=f"Your {target} is right in front of you.",
                        haptic_command="NEAR",
                        proximity=proximity_str
                    )

                # Directional spatial computation
                if center_x < 0.35:
                    pos = "left"
                    voice = f"The {target} is to your left."
                    haptic = "LEFT"
                elif center_x > 0.65:
                    pos = "right"
                    voice = f"The {target} is to your right."
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

        except Exception as e:
            logger.error(f"Local Qwen2-VL visual grounding error: {e}")

        # If not detected in current frame
        return GuidanceResponse(
            target=target,
            detected=False,
            image_position="none",
            voice_message=f"I don't see the {target} in this view. Pan your camera slowly.",
            haptic_command="STOP",
            proximity="unknown"
        )
