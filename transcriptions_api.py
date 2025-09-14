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
import yaml
import httpx
from datetime import datetime
from fastapi import FastAPI, File, Form, UploadFile, HTTPException, Request, Header
from fastapi.responses import JSONResponse, PlainTextResponse
from typing import Optional, Literal
from io import BytesIO
import torchaudio
from model import SenseVoiceSmall
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Load LLM configuration from environment variables
LLM_API_KEY = os.getenv("LLM_API_KEY")
LLM_MODEL = os.getenv("LLM_MODEL", "gpt-3.5-turbo")
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "https://api.openai.com/v1")
LLM_TIMEOUT = float(os.getenv("LLM_TIMEOUT", "4.0"))
LLM_SYSTEM_PROMPT = os.getenv("LLM_SYSTEM_PROMPT", "你是一个专业的语音识别结果校对助手。你的任务是纠正语音识别结果中的错误，包括但不限于：标点符号、专业术语、语法问题、同音异义词等。请保持原意不变，只进行必要的纠正。")
LLM_USER_PROMPT = os.getenv("LLM_USER_PROMPT", "请纠正以下语音识别结果中的错误，只返回纠正后的文本，不要添加任何解释或说明：\n\n{text}")

# Check if LLM post-processing is enabled
LLM_ENABLED_CONFIG = os.getenv("LLM_ENABLED", "false").lower() in ("true", "1", "yes", "on")
LLM_ENABLED = LLM_ENABLED_CONFIG and bool(LLM_API_KEY)
if LLM_ENABLED:
    logger.info(f"LLM post-processing enabled. Using model: {LLM_MODEL}")
else:
    if not LLM_ENABLED_CONFIG:
        logger.info("LLM post-processing disabled. LLM_ENABLED is set to false.")
    elif not LLM_API_KEY:
        logger.info("LLM post-processing disabled. No API key configured.")
    else:
        logger.info("LLM post-processing disabled.")

# Load authentication configuration
auth_config = {}
try:
    with open("auth_config.yaml", "r", encoding="utf-8") as f:
        auth_config = yaml.safe_load(f)
    logger.info("Authentication configuration loaded successfully")
except FileNotFoundError:
    logger.warning("Authentication config file not found, authentication disabled")
except Exception as e:
    logger.error(f"Error loading authentication config: {e}")

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


def verify_bearer_token(authorization: Optional[str] = Header(None)) -> str:
    """验证 Bearer Token，返回用户名称"""
    # 如果认证配置为空或认证被禁用，则跳过验证
    if not auth_config or not auth_config.get("auth", {}).get("settings", {}).get("enabled", True):
        return "anonymous"
    
    if not authorization:
        raise HTTPException(status_code=401, detail="Authorization header required")
    
    # 检查 Bearer 前缀
    token_prefix = auth_config.get("auth", {}).get("settings", {}).get("token_prefix", "Bearer")
    if not authorization.startswith(f"{token_prefix} "):
        raise HTTPException(status_code=401, detail=f"Invalid authorization format, expected '{token_prefix} <token>'")
    
    # 提取 token
    token = authorization[len(f"{token_prefix} "):]
    
    # 检查 token 是否在配置的 tokens 中
    users = auth_config.get("auth", {}).get("users", {})
    for user_name, tokens in users.items():
        if token in tokens:
            logger.info(f"Token validated for user: {user_name}")
            return user_name
    
    raise HTTPException(status_code=401, detail="Invalid token")


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


async def post_process_with_llm(text: str) -> str:
    """Post-process ASR result with LLM to correct errors"""
    if not LLM_ENABLED or not text.strip():
        return text
    
    try:
        async with httpx.AsyncClient(timeout=LLM_TIMEOUT) as client:
            headers = {
                "Authorization": f"Bearer {LLM_API_KEY}",
                "Content-Type": "application/json"
            }
            
            # Format user prompt with text placeholder
            user_content = LLM_USER_PROMPT.format(text=text)
            
            payload = {
                "model": LLM_MODEL,
                "messages": [
                    {
                        "role": "system",
                        "content": LLM_SYSTEM_PROMPT
                    },
                    {
                        "role": "user", 
                        "content": user_content
                    }
                ],
                "temperature": 0.1,
                "max_tokens": len(text) * 2 + 100
            }
            
            response = await client.post(
                f"{LLM_BASE_URL}/chat/completions",
                headers=headers,
                json=payload
            )
            
            if response.status_code == 200:
                result = response.json()
                corrected_text = result['choices'][0]['message']['content'].strip()
                logger.info(f"LLM API call successful. Model: {LLM_MODEL}, Original length: {len(text)}, Corrected length: {len(corrected_text)}")
                return corrected_text
            else:
                error_details = {
                    "status_code": response.status_code,
                    "reason": response.reason_phrase,
                    "headers": dict(response.headers),
                    "response_body": response.text,
                    "request_url": str(response.url),
                    "model": LLM_MODEL,
                    "base_url": LLM_BASE_URL
                }
                logger.error(f"LLM API error: {response.status_code} - {response.reason_phrase}")
                logger.error(f"LLM error details: {json.dumps(error_details, indent=2, ensure_ascii=False)}")
                return text
    
    except httpx.TimeoutException as e:
        logger.error(f"LLM post-processing timeout: {str(e)}")
        logger.error(f"Timeout details: timeout={LLM_TIMEOUT}s, model={LLM_MODEL}, base_url={LLM_BASE_URL}")
        return text
    except httpx.ConnectError as e:
        logger.error(f"LLM post-processing connection error: {str(e)}")
        logger.error(f"Connection details: model={LLM_MODEL}, base_url={LLM_BASE_URL}")
        return text
    except httpx.HTTPStatusError as e:
        logger.error(f"LLM post-processing HTTP error: {str(e)}")
        logger.error(f"HTTP error details: status={e.response.status_code}, model={LLM_MODEL}, base_url={LLM_BASE_URL}")
        return text
    except json.JSONDecodeError as e:
        logger.error(f"LLM post-processing JSON decode error: {str(e)}")
        logger.error(f"JSON error details: model={LLM_MODEL}, base_url={LLM_BASE_URL}")
        return text
    except KeyError as e:
        logger.error(f"LLM post-processing response format error: {str(e)}")
        logger.error(f"Response format error details: missing key={str(e)}, model={LLM_MODEL}, base_url={LLM_BASE_URL}")
        return text
    except Exception as e:
        logger.error(f"LLM post-processing failed with unexpected error: {str(e)}")
        logger.error(f"Unexpected error details: type={type(e).__name__}, model={LLM_MODEL}, base_url={LLM_BASE_URL}")
        import traceback
        logger.error(f"Full traceback: {traceback.format_exc()}")
        return text


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
    timestamp_granularities: Optional[str] = Form(default=None, description="Timestamp granularities"),
    authorization: Optional[str] = Header(None)
):
    """
    Transcribe audio using SenseVoice model
    
    Compatible with OpenAI's Whisper API format
    """
    try:
        # 验证 Bearer Token 并获取用户名称
        username = verify_bearer_token(authorization)
        
        # 获取token用于日志记录（显示完整token）
        token_for_log = "anonymous"
        if authorization and authorization.startswith("Bearer "):
            token_for_log = authorization[7:]  # Remove "Bearer " prefix
        
        # Log request parameters including token and username
        logger.info(f"Transcription request from user: {username}, token: {token_for_log}, "
                   f"filename={file.filename}, size={file.size if hasattr(file, 'size') else 'unknown'}, "
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
        
        # Post-process with LLM if enabled
        if LLM_ENABLED:
            logger.info(f"Post-processing text with LLM for user: {username}")
            original_text = clean_text
            clean_text = await post_process_with_llm(clean_text)
            
            # Log LLM correction details
            if original_text != clean_text:
                logger.info("-------------------")
                logger.info(f"| LLM correction applied for user: {username}")
                logger.info(f"| Model: {LLM_MODEL}")
                logger.info(f"| Original: {original_text}")
                logger.info(f"| Corrected: {clean_text}")
                logger.info("-------------------")
            else:
                logger.info(f"LLM processing completed, no changes made for user: {username}")
        
        # Detect language if auto
        detected_language = detect_language_from_text(raw_text) if lang == "auto" else lang
        
        # Log the transcription result
        logger.info(f"Transcription result for user: {username}, detected_language={detected_language}, "
                   f"text_length={len(clean_text)}, text_preview={clean_text[:100]}...")
        
        # Format response based on response_format
        if response_format == "text":
            logger.info(f"Returning text response for user: {username}")
            return PlainTextResponse(content=clean_text)
        
        elif response_format == "srt":
            # Simple SRT format (without timestamps for now)
            srt_content = f"1\n00:00:00,000 --> 00:00:10,000\n{clean_text}\n"
            logger.info(f"Returning SRT response for user: {username}")
            return PlainTextResponse(content=srt_content, media_type="text/plain")
        
        elif response_format == "vtt":
            # Simple VTT format (without timestamps for now)
            vtt_content = f"WEBVTT\n\n00:00:00.000 --> 00:00:10.000\n{clean_text}\n"
            logger.info(f"Returning VTT response for user: {username}")
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
            logger.info(f"Returning verbose JSON response for user: {username}: {json.dumps(response_data, ensure_ascii=False)[:500]}...")
            return JSONResponse(response_data)
        
        else:  # json (default)
            response_data = {
                "text": clean_text,
                "language": detected_language,
                "model": "sensevoice-small"
            }
            logger.info(f"Returning JSON response for user: {username}: {json.dumps(response_data, ensure_ascii=False)}")
            
            # 添加格式化的用户转录结果日志
            logger.info("-------------------")
            logger.info(f"|{username}: {clean_text}")
            logger.info("-------------------")
            
            return JSONResponse(response_data)
            
    except Exception as e:
        # Try to get username for error logging, but don't fail if token is invalid
        try:
            username_for_error = verify_bearer_token(authorization)
        except:
            username_for_error = "unknown"
        
        logger.error(f"Transcription error for user: {username_for_error}: {str(e)}", exc_info=True)
        if "load" in str(e).lower() or "audio" in str(e).lower():
            raise HTTPException(status_code=400, detail="Invalid audio file format")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/v1/audio/translations")
async def create_translation(
    file: UploadFile = File(..., description="The audio file to translate"),
    model: str = Form(default="whisper-1", description="Model name (for compatibility)"),
    prompt: Optional[str] = Form(default=None, description="Optional prompt"),
    response_format: ResponseFormat = Form(default="json", description="Response format"),
    temperature: Optional[float] = Form(default=0, description="Temperature"),
    authorization: Optional[str] = Header(None)
):
    """
    Translate audio to English (currently just transcribes)
    Note: SenseVoice doesn't do translation, only transcription
    """
    # 验证 Bearer Token 并获取用户名称
    username = verify_bearer_token(authorization)
    
    # 记录请求信息，包含用户名称
    logger.info(f"Translation request from user: {username}, filename={file.filename}, size={file.size if hasattr(file, 'size') else 'unknown'}")
    
    # For now, just transcribe with language set to auto
    # Real translation would require a separate translation model
    result = await create_transcription(
        file=file,
        model=model,
        language="auto",
        prompt=prompt,
        response_format=response_format,
        temperature=temperature,
        timestamp_granularities=None
    )
    
    # 记录响应信息，包含用户名称
    logger.info(f"Translation response for user: {username} completed successfully")
    
    return result


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