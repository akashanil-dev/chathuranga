import os
os.environ["HF_HUB_DISABLE_XET"] = "1"
import logging
import threading
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from starlette.concurrency import run_in_threadpool

from models.schemas import (
    VoiceIntentRequest,
    VoiceIntentResponse,
    GuidanceRequest,
    GuidanceResponse,
    VisionAnalysisRequest
)
from services.claude_service import ClaudeService
from services.qwen_service import QwenVLService

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sense_backend")

qwen_service = QwenVLService()
claude_service = ClaudeService()

VISION_ENGINE = os.getenv("VISION_ENGINE", "qwen").lower()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Warmup / load Qwen2-VL-2B in background
    logger.info("Starting background load of Qwen2-VL-2B model...")
    threading.Thread(target=qwen_service.load_model, daemon=True).start()
    yield

app = FastAPI(
    title="SENSE Assistive API",
    description="Backend service for SENSE AI-Powered Assistive Object Finder (Qwen2-VL-2B local)",
    version="2.0.0",
    lifespan=lifespan
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
        "vision_engine": VISION_ENGINE,
        "qwen_loaded": qwen_service.is_loaded,
        "qwen_loading": qwen_service.is_loading,
        "claude_available": claude_service.client is not None and VISION_ENGINE != "qwen"
    }

@app.post("/api/v1/intent", response_model=VoiceIntentResponse)
async def parse_voice_intent(req: VoiceIntentRequest):
    """
    Parses user voice transcription into structured action and target object.
    Fast local parsing (<5ms) prioritizing local Qwen extraction.
    """
    try:
        res = qwen_service.parse_intent(req.transcript)
        if res and res.action != "UNKNOWN":
            return res
        if VISION_ENGINE != "qwen" and claude_service.client is not None:
            return await claude_service.parse_intent(req.transcript)
        return res
    except Exception as e:
        logger.error(f"Error parsing intent: {e}")
        return VoiceIntentResponse(action="UNKNOWN", target=None, raw_transcript=req.transcript)

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
    Multimodal scene analysis.
    Uses local Qwen2-VL engine when VISION_ENGINE=qwen (Claude API disabled).
    """
    try:
        if VISION_ENGINE == "qwen":
            if not qwen_service.is_loaded:
                logger.info("Qwen2-VL model loading triggered on demand...")
                qwen_service.load_model()
            logger.info("Using local Qwen2-VL visual grounding engine (Claude API disabled)...")
            return await run_in_threadpool(
                qwen_service.analyze_scene_with_grounding,
                req.transcript,
                req.image_base64,
                req.target,
                req.sensor_distance_cm
            )

        if claude_service.client is not None:
            return await claude_service.analyze_multimodal_vision(
                transcript=req.transcript,
                image_base64=req.image_base64,
                target=req.target,
                sensor_distance_cm=req.sensor_distance_cm
            )

        if qwen_service.is_loaded:
            return await run_in_threadpool(
                qwen_service.analyze_scene_with_grounding,
                req.transcript,
                req.image_base64,
                req.target,
                req.sensor_distance_cm
            )

        target = req.target or QwenVLService.extract_target_fast(req.transcript) or "object"
        return GuidanceResponse(
            target=target,
            detected=False,
            image_position="none",
            voice_message=f"Vision model initializing. Please scan slowly.",
            haptic_command="STOP",
            proximity="unknown"
        )
    except Exception as e:
        logger.error(f"Error analyzing vision: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/v1/analyze_local", response_model=GuidanceResponse)
async def analyze_local_qwen(req: VisionAnalysisRequest):
    """
    Direct endpoint for 100% offline local Qwen2-VL visual grounding.
    """
    try:
        if not qwen_service.is_loaded:
            qwen_service.load_model()
        return await run_in_threadpool(
            qwen_service.analyze_scene_with_grounding,
            req.transcript,
            req.image_base64,
            req.target,
            req.sensor_distance_cm
        )
    except Exception as e:
        logger.error(f"Local Qwen error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)

