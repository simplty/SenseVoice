# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SenseVoice is a speech foundation model with multiple speech understanding capabilities:
- Automatic Speech Recognition (ASR) for 50+ languages
- Spoken Language Identification (LID)
- Speech Emotion Recognition (SER)
- Audio Event Detection (AED)

The model uses a non-autoregressive end-to-end architecture for fast inference (15x faster than Whisper-Large).

## Git Configuration

### Repository Information
- Repository: simplty/SenseVoice
- Main branch: main
- Development branch: docker_deploy_on_cpu
- Remote: origin configured with authentication

### Common Git Commands
```bash
# Push to current branch
git push origin docker_deploy_on_cpu

# Create pull request
# Visit: https://github.com/simplty/SenseVoice/pull/new/docker_deploy_on_cpu
```

### Merge Rules
**重要**: 当将 main 分支合并到当前分支时，请遵守以下规则：
- 千万不要擅自修改当前分支的文件
- 如果当前分支的文件与 main 分支的文件有冲突，需要让用户自己选择如何解决冲突
- 在合并前先通知用户可能存在的冲突，让用户决定合并策略

## Commands

### Environment Setup with uv
```bash
# Install uv if not already installed
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create a virtual environment
uv venv

# Activate the environment (macOS/Linux)
source .venv/bin/activate

# Install dependencies (fast parallel installation)
uv pip install -r requirements.txt

# Alternative: sync exact versions
uv pip sync requirements.txt
```

### Running Inference
```python
from funasr import AutoModel
model = AutoModel(model="iic/SenseVoiceSmall", trust_remote_code=True)
res = model.generate("audio.wav")
```

### Fine-tuning
```bash
bash finetune.sh
```

### API Service
```bash
export SENSEVOICE_DEVICE=cuda:0  # or cpu
fastapi run --port 50000
```

### Web UI
```bash
python webui.py
```

### Model Export
- ONNX: `python demo_onnx.py`
- LibTorch: `python demo_libtorch.py`

## Architecture

### Core Components
- `model.py`: Main SenseVoice model implementation using FunASR framework
- `api.py`: FastAPI service providing REST endpoints
- `webui.py`: Gradio-based web interface
- `utils/`: Processing utilities including frontend audio processing, CTC alignment, and export tools

### Model Loading Flow
1. Models are loaded from ModelScope/HuggingFace hubs
2. FunASR AutoModel handles model initialization
3. Supports both SenseVoiceSmall and SenseVoiceLarge variants
4. Models can run on CPU or CUDA devices

### Inference Pipeline
1. Audio preprocessing via `utils/frontend.py` (resampling to 16kHz)
2. Model inference with optional VAD for long audio
3. Post-processing includes:
   - Text with punctuation
   - Language identification
   - Emotion labels (happy, sad, angry, neutral)
   - Event detection (applause, laughter, crying, etc.)
   - Optional CTC alignment for timestamps

### Training Data Format
JSONL format with fields:
- `source`: Audio file path
- `target`: Transcription text
- `text_language`: Language code
- `emo_target`: Emotion label
- `event_target`: Event labels
- `with_or_wo_itn`: ITN flag

### Key Dependencies
- Python environment managed with uv (faster than pip)
- PyTorch <=2.3 with TorchAudio
- FunASR >=1.1.3 (core ASR framework)
- NumPy <=1.26.4
- Gradio for web UI
- FastAPI for API service

## Development Notes

### Testing
- All test files should be placed in test/ directory
- Any temporary test scripts or experimental code should go in test/ directory, not in the project root
- Use demo files (demo1.py, demo2.py) as integration test references
- No formal unit testing framework currently in place

### Model Variants
- SenseVoiceSmall: Faster, lighter model
- SenseVoiceLarge: More accurate, slower model
- Both support same features but differ in performance/accuracy tradeoff

### Deployment Considerations
- Dynamic batching based on token count or time duration
- Supports batch_size_token=12800 or batch_size_time=500 seconds
- VAD integration recommended for long audio files
- Export to ONNX/LibTorch for production deployment