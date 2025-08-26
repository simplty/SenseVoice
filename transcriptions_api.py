#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
OpenAI-compatible Transcriptions API for SenseVoice
Compatible with OpenAI's Whisper API format
"""

import os
import re
import logging
import json
from datetime import datetime
from fastapi import FastAPI, File, Form, UploadFile, HTTPException, Request
from fastapi.responses import JSONResponse, PlainTextResponse
from typing import Optional, Literal
from io import BytesIO
import torchaudio
from model import SenseVoiceSmall
from funasr.utils.postprocess_utils import rich_transcription_postprocess

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Initialize model
model_dir = "./models/SenseVoiceSmall"
device = os.getenv("SENSEVOICE_DEVICE", "cpu")
logger.info(f"Loading model from {model_dir} on {device}...")
m, kwargs = SenseVoiceSmall.from_pretrained(model=model_dir, device=device)
m.eval()
logger.info("Model loaded successfully!")

app = FastAPI(
    title="SenseVoice Transcription API",
    description="OpenAI-compatible transcription API using SenseVoice model",
    version="1.0.0"
)

# Add middleware to log requests
@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Middleware to log all requests and responses"""
    start_time = datetime.now()
    
    # Log request info
    logger.info(f"Request: {request.method} {request.url.path}")
    
    # Process request
    response = await call_next(request)
    
    # Calculate duration
    duration = (datetime.now() - start_time).total_seconds()
    
    # Log response info
    logger.info(f"Response: Status={response.status_code}, Duration={duration:.2f}s")
    
    return response

# Clean text patterns
regex = r"<\|.*?\|>"
TARGET_FS = 16000

# Language mapping (OpenAI format to SenseVoice format)
LANGUAGE_MAP = {
    "zh": "zh",        # Chinese
    "en": "en",        # English
    "ja": "ja",        # Japanese
    "ko": "ko",        # Korean
    "yue": "yue",      # Cantonese
    "auto": "auto",    # Auto-detect
}

# Response format types
ResponseFormat = Literal["json", "text", "srt", "verbose_json", "vtt"]


def clean_transcription_text(text: str) -> str:
    """Remove special tokens from transcription text"""
    # Remove all special tokens like <|zh|>, <|NEUTRAL|>, etc.
    cleaned = re.sub(regex, "", text)
    # Remove extra spaces
    cleaned = " ".join(cleaned.split())
    return cleaned.strip()


def detect_language_from_text(text: str) -> str:
    """Extract language code from raw text"""
    lang_match = re.search(r"<\|(zh|en|ja|ko|yue)\|>", text)
    if lang_match:
        return lang_match.group(1)
    return "unknown"


@app.get("/")
async def root():
    """API information"""
    return {
        "message": "SenseVoice Transcription API (OpenAI-compatible)",
        "endpoints": {
            "/v1/audio/transcriptions": "Transcribe audio (OpenAI-compatible)",
            "/docs": "API documentation"
        }
    }


@app.post("/v1/audio/transcriptions")
async def create_transcription(
    file: UploadFile = File(..., description="The audio file to transcribe"),
    model: str = Form(default="whisper-1", description="Model name (for compatibility)"),
    language: Optional[str] = Form(default=None, description="Language code (zh, en, ja, ko, yue)"),
    prompt: Optional[str] = Form(default=None, description="Optional prompt (not used by SenseVoice)"),
    response_format: ResponseFormat = Form(default="json", description="Response format"),
    temperature: Optional[float] = Form(default=0, description="Temperature (not used by SenseVoice)"),
    timestamp_granularities: Optional[str] = Form(default=None, description="Timestamp granularities")
):
    """
    Transcribe audio using SenseVoice model
    
    Compatible with OpenAI's Whisper API format
    """
    try:
        # Log request parameters
        logger.info(f"Transcription request: filename={file.filename}, size={file.size if hasattr(file, 'size') else 'unknown'}, "
                   f"language={language}, response_format={response_format}")
        
        # Read audio file
        file_io = BytesIO(await file.read())
        data_or_path_or_list, audio_fs = torchaudio.load(file_io)
        
        # Log audio info
        logger.info(f"Audio loaded: sample_rate={audio_fs}, shape={data_or_path_or_list.shape}")
        
        # Resample if needed
        if audio_fs != TARGET_FS:
            resampler = torchaudio.transforms.Resample(orig_freq=audio_fs, new_freq=TARGET_FS)
            data_or_path_or_list = resampler(data_or_path_or_list)
        
        # Convert to mono
        data_or_path_or_list = data_or_path_or_list.mean(0)
        
        # Map language
        lang = "auto"
        if language and language.lower() in LANGUAGE_MAP:
            lang = LANGUAGE_MAP[language.lower()]
        
        logger.info(f"Starting inference with language={lang}")
        
        # Perform transcription
        res = m.inference(
            data_in=data_or_path_or_list.cpu().numpy(),
            language=lang,
            use_itn=True,
            ban_emo_unk=False,
            **kwargs,
        )
        
        logger.info(f"Inference completed")
        
        if not res or not res[0]:
            raise HTTPException(status_code=500, detail="Transcription failed")
        
        # Extract text from result
        # res is a tuple: (results_list, stats_dict)
        # results_list contains dicts with 'key' and 'text'
        if isinstance(res[0], list) and len(res[0]) > 0:
            raw_text = res[0][0].get('text', '')
        else:
            raise HTTPException(status_code=500, detail="Unexpected result format")
        
        # Clean text
        clean_text = clean_transcription_text(raw_text)
        
        # Detect language if auto
        detected_language = detect_language_from_text(raw_text) if lang == "auto" else lang
        
        # Log the transcription result
        logger.info(f"Transcription result: detected_language={detected_language}, "
                   f"text_length={len(clean_text)}, text_preview={clean_text[:100]}...")
        
        # Format response based on response_format
        if response_format == "text":
            logger.info(f"Returning text response: {clean_text}")
            return PlainTextResponse(content=clean_text)
        
        elif response_format == "srt":
            # Simple SRT format (without timestamps for now)
            srt_content = f"1\n00:00:00,000 --> 00:00:10,000\n{clean_text}\n"
            logger.info(f"Returning SRT response")
            return PlainTextResponse(content=srt_content, media_type="text/plain")
        
        elif response_format == "vtt":
            # Simple VTT format (without timestamps for now)
            vtt_content = f"WEBVTT\n\n00:00:00.000 --> 00:00:10.000\n{clean_text}\n"
            logger.info(f"Returning VTT response")
            return PlainTextResponse(content=vtt_content, media_type="text/vtt")
        
        elif response_format == "verbose_json":
            # Verbose JSON with more details
            response_data = {
                "task": "transcribe",
                "language": detected_language,
                "duration": None,  # Would need to calculate from audio
                "text": clean_text,
                "segments": [{
                    "id": 0,
                    "seek": 0,
                    "start": 0.0,
                    "end": None,
                    "text": clean_text,
                    "tokens": [],
                    "temperature": temperature or 0.0,
                    "avg_logprob": None,
                    "compression_ratio": None,
                    "no_speech_prob": 0.0
                }]
            }
            logger.info(f"Returning verbose JSON response: {json.dumps(response_data, ensure_ascii=False)[:500]}...")
            return JSONResponse(response_data)
        
        else:  # json (default)
            response_data = {
                "text": clean_text,
                "language": detected_language,
                "model": "sensevoice-small"
            }
            logger.info(f"Returning JSON response: {json.dumps(response_data, ensure_ascii=False)}")
            return JSONResponse(response_data)
            
    except Exception as e:
        logger.error(f"Transcription error: {str(e)}", exc_info=True)
        if "load" in str(e).lower() or "audio" in str(e).lower():
            raise HTTPException(status_code=400, detail="Invalid audio file format")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/v1/audio/translations")
async def create_translation(
    file: UploadFile = File(..., description="The audio file to translate"),
    model: str = Form(default="whisper-1", description="Model name (for compatibility)"),
    prompt: Optional[str] = Form(default=None, description="Optional prompt"),
    response_format: ResponseFormat = Form(default="json", description="Response format"),
    temperature: Optional[float] = Form(default=0, description="Temperature")
):
    """
    Translate audio to English (currently just transcribes)
    Note: SenseVoice doesn't do translation, only transcription
    """
    # For now, just transcribe with language set to auto
    # Real translation would require a separate translation model
    return await create_transcription(
        file=file,
        model=model,
        language="auto",
        prompt=prompt,
        response_format=response_format,
        temperature=temperature,
        timestamp_granularities=None
    )


@app.get("/v1/models")
async def list_models():
    """List available models (for compatibility)"""
    return {
        "object": "list",
        "data": [
            {
                "id": "sensevoice-small",
                "object": "model",
                "created": 1677649963,
                "owned_by": "funaudiollm",
                "permission": [],
                "root": "sensevoice-small",
                "parent": None
            }
        ]
    }


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "model": "sensevoice-small", "device": device}


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 7861))
    logger.info(f"Starting SenseVoice API server on port {port}, device: {device}")
    logger.info(f"API endpoints: http://0.0.0.0:{port}/v1/audio/transcriptions")
    logger.info(f"Documentation: http://0.0.0.0:{port}/docs")
    uvicorn.run(app, host="0.0.0.0", port=port, log_config={
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "default": {
                "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
            },
        },
        "handlers": {
            "default": {
                "formatter": "default",
                "class": "logging.StreamHandler",
                "stream": "ext://sys.stdout"
            },
        },
        "root": {
            "level": "INFO",
            "handlers": ["default"]
        },
    })