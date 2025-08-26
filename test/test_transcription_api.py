#!/usr/bin/env python
# Test script for debugging transcription API

import os
import sys
sys.path.append('..')

from model import SenseVoiceSmall
import torchaudio
import numpy as np

# Load model
model_dir = "../models/SenseVoiceSmall"
device = "cpu"
print(f"Loading model from {model_dir}...")
m, kwargs = SenseVoiceSmall.from_pretrained(model=model_dir, device=device)
m.eval()

# Load test audio
audio_path = "../models/SenseVoiceSmall/example/zh.mp3"
data, fs = torchaudio.load(audio_path)

# Resample if needed
if fs != 16000:
    resampler = torchaudio.transforms.Resample(orig_freq=fs, new_freq=16000)
    data = resampler(data)

# Convert to mono
data = data.mean(0)

print(f"Audio shape: {data.shape}")
print(f"Audio sample rate: {fs}")

# Test inference
res = m.inference(
    data_in=data.cpu().numpy(),
    language="zh",
    use_itn=True,
    ban_emo_unk=False,
    **kwargs,
)

print(f"Result type: {type(res)}")
print(f"Result: {res}")

if res and res[0]:
    print(f"res[0] type: {type(res[0])}")
    print(f"res[0]: {res[0]}")