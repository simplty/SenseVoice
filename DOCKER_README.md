# Docker 部署指南

本指南介绍如何使用 Docker 部署 SenseVoice Transcription API。

## 快速开始

### 1. 使用 docker-compose (推荐)

```bash
# 构建并启动服务
docker-compose up -d

# 查看日志
docker-compose logs -f

# 停止服务
docker-compose down

# 重新构建镜像并启动
docker-compose up --build -d
```

### 2. 使用 Docker 命令

```bash
# 构建镜像
docker build -t sensevoice-api .

# 运行容器
docker run -d \
  --name sensevoice-transcription-api \
  -p 7861:7861 \
  -e SENSEVOICE_DEVICE=cpu \
  sensevoice-api

# 查看容器日志
docker logs -f sensevoice-transcription-api

# 停止容器
docker stop sensevoice-transcription-api

# 删除容器
docker rm sensevoice-transcription-api
```

## 配置说明

### 环境变量

- `SENSEVOICE_DEVICE`: 设备选择
  - `cpu`: 使用 CPU (默认)
  - `cuda:0`: 使用第一个 GPU
- `PORT`: API 端口 (默认: 7861)

### 修改配置

编辑 `docker-compose.yml` 文件中的环境变量：

```yaml
environment:
  - SENSEVOICE_DEVICE=cpu  # 改为 cuda:0 使用 GPU
  - PORT=7861              # 修改端口
```

## GPU 支持

如果需要使用 GPU，请修改 Dockerfile：

```dockerfile
# 将基础镜像改为 PyTorch GPU 版本
FROM pytorch/pytorch:2.0.0-cuda11.7-cudnn8-runtime

# ... 其余配置不变 ...
```

并在 docker-compose.yml 中添加 GPU 支持：

```yaml
services:
  sensevoice-api:
    # ... 其他配置 ...
    
    # GPU 支持
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    
    environment:
      - SENSEVOICE_DEVICE=cuda:0
```

## 数据持久化

如果需要从主机挂载模型文件（避免每次构建都复制模型），可以取消注释 docker-compose.yml 中的 volumes 部分：

```yaml
volumes:
  - ./models:/app/models:ro
  - ./data:/app/data:ro
```

## API 使用

服务启动后，可以通过以下端点访问：

- API 根路径: http://localhost:7861/
- API 文档: http://localhost:7861/docs
- 健康检查: http://localhost:7861/health

### 转写音频示例

```bash
# 使用 curl 调用 API
curl -X POST "http://localhost:7861/v1/audio/transcriptions" \
  -H "accept: application/json" \
  -F "file=@audio.wav" \
  -F "language=zh" \
  -F "response_format=json"
```

### Python 调用示例

```python
import requests

# 上传音频文件进行转写
with open("audio.wav", "rb") as f:
    response = requests.post(
        "http://localhost:7861/v1/audio/transcriptions",
        files={"file": f},
        data={
            "language": "zh",  # 或 en, ja, ko, yue, auto
            "response_format": "json"
        }
    )
    
print(response.json())
```

## 故障排除

### 1. 端口被占用

修改 docker-compose.yml 中的端口映射：

```yaml
ports:
  - "8080:7861"  # 将主机端口改为 8080
```

### 2. 内存不足

在 docker-compose.yml 中设置资源限制：

```yaml
deploy:
  resources:
    limits:
      memory: 8G  # 根据需要调整
```

### 3. 查看详细日志

```bash
# 查看所有日志
docker-compose logs

# 实时查看日志
docker-compose logs -f

# 查看最近 100 行日志
docker-compose logs --tail=100
```

## 生产环境建议

1. **使用反向代理**: 在生产环境中，建议使用 Nginx 或 Traefik 作为反向代理
2. **启用 HTTPS**: 配置 SSL 证书保护 API 通信
3. **设置资源限制**: 根据服务器配置设置合适的 CPU 和内存限制
4. **配置日志轮转**: 避免日志文件过大
5. **监控和告警**: 集成 Prometheus 等监控工具

## 镜像优化

为了减小镜像大小，可以使用多阶段构建：

```dockerfile
# 第一阶段：构建
FROM python:3.10-slim as builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# 第二阶段：运行
FROM python:3.10-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY . .
ENV PATH=/root/.local/bin:$PATH
CMD ["python", "transcriptions_api.py"]
```