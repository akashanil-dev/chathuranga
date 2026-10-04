import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from models.schemas import (
    VoiceIntentRequest,
    VoiceIntentResponse,
    GuidanceRequest,
    GuidanceResponse,
    VisionAnalysisRequest
)
from services.claude_service import ClaudeService, ProviderUnavailable
from services.guidance import extract_target_fast, not_detected, rule_intent
from services.vlm_service import LocalVLMService

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sense_backend")

local_vlm = LocalVLMService()
claude_service = ClaudeService()


@asynccontextmanager
async def lifespan(app: FastAPI):
    await local_vlm.warm_up()
    yield
    await local_vlm.close()


app = FastAPI(
    title="SENSE Assistive API",
    description="Backend service for SENSE AI-Powered Assistive Object Finder",
    version="2.0.0",
    lifespan=lifespan,
)

# Enable CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "SENSE Assistive API",
        "vision_order": ["local", "claude"],
        "local_model": local_vlm.model,
        **(await local_vlm.status()),
        "claude_available": claude_service.available,
        "claude_model": claude_service.model,
    }

@app.post("/api/v1/intent", response_model=VoiceIntentResponse)
async def parse_voice_intent(req: VoiceIntentRequest):
    """
    Parses user voice transcription into structured action and target object.
    Example: 'Find my keys' -> {'action': 'FIND_OBJECT', 'target': 'keys'}
    Order: instant rules -> local Qwen3-VL -> Claude -> raw transcript.
    """
    fast = rule_intent(req.transcript)
    if fast:
        return fast
    for name, provider in (("local", local_vlm), ("claude", claude_service)):
        try:
            target = await provider.extract_target(req.transcript)
            if target:
                return VoiceIntentResponse(action="FIND_OBJECT", target=target, raw_transcript=req.transcript)
        except ProviderUnavailable as e:
            logger.warning(f"Intent via {name} failed: {e}")
    return VoiceIntentResponse(
        action="FIND_OBJECT", target=req.transcript.strip().lower().rstrip(".?! "), raw_transcript=req.transcript
    )

@app.post("/api/v1/guidance", response_model=GuidanceResponse)
async def generate_guidance(req: GuidanceRequest):
    """
    Computes guidance response matching SENSE specification.
    """
    try:
        return claude_service.calculate_guidance(req)
    except Exception as e:
        logger.error(f"Error generating guidance: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/analyze", response_model=GuidanceResponse)
async def analyze_camera_and_voice(req: VisionAnalysisRequest):
    """
    Multimodal scene analysis: local Qwen3-VL (Ollama) first, Claude Vision as fallback.
    A clean "not found" from the local model is a valid answer and does not trigger the fallback;
    only errors, timeouts or an unreachable Ollama do.
    """
    target = extract_target_fast(req.transcript) or "object"
    for name, analyze in (("local", local_vlm.analyze), ("claude", claude_service.analyze_multimodal_vision)):
        try:
            return await analyze(req.transcript, req.image_base64, req.sensor_distance_cm, target)
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e))
        except ProviderUnavailable as e:
            logger.warning(f"Vision via {name} failed: {e}")
    return not_detected(target, "none", "The vision service is unavailable. Please try again in a moment.")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000)
