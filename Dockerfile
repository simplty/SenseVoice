# Use DaoCloud mirror for Python image
FROM docker.m.daocloud.io/python:3.12-slim

# Set working directory in container
WORKDIR /app

# Install system dependencies
# 使用阿里云镜像源加速 apt 下载，并只安装未安装的软件
RUN sed -i 's@http://deb.debian.org@http://mirrors.aliyun.com@g' /etc/apt/sources.list.d/debian.sources && \
    apt-get update && \
    for pkg in build-essential git curl ffmpeg; do \
        dpkg -l | grep -q "^ii  $pkg " || apt-get install -y $pkg; \
    done && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements first to leverage Docker cache
COPY requirements.txt .

# Add uvicorn to requirements since the API needs it
# RUN pip install --no-cache-dir uvicorn -i https://pypi.tuna.tsinghua.edu.cn/simple
RUN pip install  uvicorn -i https://pypi.tuna.tsinghua.edu.cn/simple

# Install Python dependencies
# RUN pip install --no-cache-dir -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
RUN pip install  -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

# Copy all application files
COPY . .

# Set environment variables
# Default to CPU, can be overridden in docker-compose
ENV SENSEVOICE_DEVICE=cpu
ENV PORT=7861

# Expose the port the app runs on
EXPOSE 7861

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:7861/health || exit 1

# Run the transcription API
CMD ["python", "transcriptions_api.py"]