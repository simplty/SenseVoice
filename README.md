# SenseVoice - 语音识别与转写 API 服务

这是一个基于 FunAudioLLM/SenseVoice 的语音识别服务项目，提供了 OpenAI Whisper 兼容的 API 接口。

## 项目来源

本项目基于原始项目 [FunAudioLLM/SenseVoice](https://github.com/FunAudioLLM/SenseVoice)，这是阿里巴巴达摩院开发的语音基础模型，具备多种语音理解能力。

## 主要修改

相对于原始项目，本项目进行了以下增强和修改：

1. **新增 OpenAI 兼容 API** (`transcriptions_api.py`)
   - 提供与 OpenAI Whisper API 完全兼容的接口
   - 支持多种音频格式和输出格式
   - 增加了详细的请求日志和错误处理

2. **容器化部署支持**
   - 添加了 Dockerfile 和 docker-compose.yml
   - 使用国内镜像源加速构建
   - 支持 CPU 和 GPU 环境部署

3. **进程管理工具** (Makefile)
   - 提供后台运行和进程管理功能
   - 支持日志追踪和状态检查
   - 简化部署和运维操作
   - 新增 WebUI 管理功能

4. **配置优化**
   - API 默认端口：7861
   - WebUI 默认端口：7862
   - 支持本地模型路径配置
   - 环境变量配置更灵活

## 快速开始

### 方式一：使用 Makefile（推荐）

```bash
# 安装依赖
make install

# 启动 API 服务（后台运行，使用 CPU）
make

# 或者使用 GPU
make start-gpu

# 启动 WebUI（Gradio 界面）
make webui

# 查看服务状态
make status        # API 状态
make webui-status  # WebUI 状态

# 查看实时日志
make tail

# 停止服务
make stop          # 停止 API
make webui-stop    # 停止 WebUI
```

### 方式二：Docker 部署

```bash
# 构建镜像
docker-compose build

# 启动服务
docker-compose up -d

# 查看日志
docker-compose logs -f

# 停止服务
docker-compose down
```

### 方式三：直接运行

```bash
# 安装依赖
pip install -r requirements.txt

# 运行 API 服务
# CPU 运行
SENSEVOICE_DEVICE=cpu python transcriptions_api.py

# GPU 运行
SENSEVOICE_DEVICE=cuda:0 python transcriptions_api.py

# 运行 WebUI
python webui.py

# 指定 WebUI 端口
GRADIO_SERVER_PORT=8080 python webui.py
```

## 使用方式

### API 使用

服务启动后，可通过以下方式调用：

```bash
# 音频转写
curl -X POST http://localhost:7861/v1/audio/transcriptions \
  -H "Content-Type: multipart/form-data" \
  -F "file=@audio.mp3" \
  -F "language=zh"
```

支持的参数：
- `file`: 音频文件
- `language`: 语言（auto/zh/en/yue/ja/ko）
- `response_format`: 输出格式（json/text/srt/vtt）

### WebUI 使用

启动 WebUI 后，在浏览器中访问：
- 默认地址：http://localhost:7862
- 支持上传音频文件或使用麦克风录音
- 可视化显示转写结果、情感标签和事件检测

## 功能特性

- **多语言支持**：中文、英文、粤语、日语、韩语等50+语言
- **情感识别**：识别开心、悲伤、愤怒、中性等情绪
- **事件检测**：掌声、笑声、哭声、咳嗽等声音事件
- **高性能**：比 Whisper-Large 快15倍
- **时间戳支持**：基于 CTC 对齐的精确时间戳

## 环境要求

- Python 3.8+
- PyTorch (CPU 或 CUDA)
- 4GB+ 内存（CPU）/ 8GB+ 显存（GPU）

## 模型下载

首次运行会自动下载模型文件到 `models/` 目录。也可以手动下载：
- [ModelScope](https://www.modelscope.cn/models/iic/SenseVoiceSmall)
- [HuggingFace](https://huggingface.co/FunAudioLLM/SenseVoiceSmall)

## 项目结构

```
.
├── transcriptions_api.py  # OpenAI 兼容 API 服务
├── api.py                 # 原始 FastAPI 服务
├── model.py               # SenseVoice 模型实现
├── webui.py               # Gradio Web 界面
├── Dockerfile             # Docker 镜像构建
├── docker-compose.yml     # Docker 编排配置
├── Makefile              # 进程管理和部署工具
├── requirements.txt       # Python 依赖
└── models/               # 模型文件目录（自动下载）
```

## 常用命令

```bash
# 查看所有可用命令
make help

# API 服务管理
make start         # 启动 API（CPU）
make start-gpu     # 启动 API（GPU）
make stop          # 停止 API
make restart       # 重启 API
make status        # API 状态

# WebUI 管理
make webui         # 启动 WebUI
make webui-stop    # 停止 WebUI
make webui-status  # WebUI 状态
make webui-fg      # 前台运行 WebUI（调试用）

# 日志管理
make logs          # 查看日志
make tail          # 实时日志
make clean-logs    # 清理日志

# Docker 操作
make docker-build  # 构建镜像
make docker-up     # 启动容器
make docker-down   # 停止容器
make docker-logs   # 查看日志

# 其他
make install       # 安装依赖
make install-uv    # 使用 uv 安装（更快）
make test          # 运行测试
make clean         # 清理缓存文件
make check-models  # 检查模型文件
```

### 端口配置

- API 服务默认端口：7861
- WebUI 默认端口：7862

自定义端口：
```bash
# 自定义 API 端口
make run-port PORT=8080

# 自定义 WebUI 端口
make webui WEBUI_PORT=8000
```

## 许可证

本项目继承原始 SenseVoice 项目的许可证。详见原项目仓库。

## 致谢

感谢阿里巴巴达摩院 FunAudioLLM 团队开发的 SenseVoice 模型。