from typing import Optional, List, Literal
from pydantic import BaseModel, Field

class VoiceIntentRequest(BaseModel):
    transcript: str = Field(..., description="Transcribed user speech, e.g., 'Find my keys'")

class VoiceIntentResponse(BaseModel):
    action: Literal["FIND_OBJECT", "STOP", "HELP", "UNKNOWN"] = "FIND_OBJECT"
    target: Optional[str] = Field(None, description="The normalized target object name, e.g., 'keys'")
    raw_transcript: str

class BoundingBox(BaseModel):
    label: str
    confidence: float
    x_min: float
    y_min: float
    x_max: float
    y_max: float

class VisionAnalysisRequest(BaseModel):
    transcript: str = Field(..., description="User's spoken request, e.g. 'Where are my keys?'")
    target: Optional[str] = Field(None, description="Pre-extracted target object name, e.g. 'water bottle'")
    image_base64: str = Field(..., description="Base64 encoded JPEG image captured by the camera")
    sensor_distance_cm: Optional[float] = None

class GuidanceRequest(BaseModel):
    target: str = Field(..., description="Target object to find")
    bounding_boxes: Optional[List[BoundingBox]] = None
    image_base64: Optional[str] = None
    sensor_distance_cm: Optional[float] = None

class GuidanceResponse(BaseModel):
    target: str
    detected: bool
    image_position: Literal["left", "center", "right", "none", "unknown"]
    voice_message: str
    haptic_command: Literal["LEFT", "RIGHT", "CENTER", "NEAR", "TOUCHING", "STOP"]
    proximity: str = "unknown"
