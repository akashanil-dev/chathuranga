import logging
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from models.schemas import (
    VoiceIntentRequest,
    VoiceIntentResponse,
    GuidanceRequest,
    GuidanceResponse,
    VisionAnalysisRequest
)
from services.claude_service import ClaudeService

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sense_backend")

app = FastAPI(
    title="SENSE Assistive API",
    description="Backend service for SENSE AI-Powered Assistive Object Finder",
    version="1.0.0"
)

# Enable CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

claude_service = ClaudeService()

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "SENSE Assistive API",
        "claude_available": claude_service.client is not None
    }

@app.post("/api/v1/intent", response_model=VoiceIntentResponse)
async def parse_voice_intent(req: VoiceIntentRequest):
    """
    Parses user voice transcription into structured action and target object.
    Example: 'Find my keys' -> {'action': 'FIND_OBJECT', 'target': 'keys'}
    """
    try:
        result = await claude_service.parse_intent(req.transcript)
        return result
    except Exception as e:
        logger.error(f"Error parsing intent: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/guidance", response_model=GuidanceResponse)
async def generate_guidance(req: GuidanceRequest):
    """
    Computes guidance response matching SENSE specification.
    """
    try:
        response = claude_service.calculate_guidance(req)
        return response
    except Exception as e:
        logger.error(f"Error generating guidance: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/analyze", response_model=GuidanceResponse)
async def analyze_camera_and_voice(req: VisionAnalysisRequest):
    """
    Multimodal scene analysis with Claude Vision.
    Processes user voice command + camera image, returns structured guidance.
    """
    try:
        response = await claude_service.analyze_multimodal_vision(
            transcript=req.transcript,
            image_base64=req.image_base64,
            sensor_distance_cm=req.sensor_distance_cm
        )
        return response
    except Exception as e:
        logger.error(f"Error analyzing vision: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
