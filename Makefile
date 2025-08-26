# Makefile for SenseVoice API
# Default target when running 'make' without arguments
.DEFAULT_GOAL := run

# Variables
# Use venv Python if it exists, otherwise use system Python
PYTHON := $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
API_FILE := transcriptions_api.py
PORT := 7861
DEVICE := cpu
LOG_DIR := logs
LOG_FILE := $(LOG_DIR)/sensevoice_api_$(shell date +%Y%m%d_%H%M%S).log
PID_FILE := .sensevoice.pid

# Phony targets (not actual files)
.PHONY: run run-gpu run-docker install clean help docker-build docker-up docker-down start stop status logs tail

# Default target: Run API in background with logging
run: start

# Start API in background with CPU
start:
	@mkdir -p $(LOG_DIR)
	@if [ -f $(PID_FILE) ] && kill -0 `cat $(PID_FILE)` 2>/dev/null; then \
		echo "SenseVoice API is already running (PID: `cat $(PID_FILE)`)"; \
		echo "Use 'make stop' to stop it first"; \
		exit 1; \
	fi
	@echo "Starting SenseVoice API in background on CPU (port $(PORT))..."
	@echo "Log file: $(LOG_FILE)"
	@nohup sh -c 'SENSEVOICE_DEVICE=$(DEVICE) PORT=$(PORT) $(PYTHON) -u $(API_FILE)' > $(LOG_FILE) 2>&1 & echo $$! > $(PID_FILE)
	@sleep 2
	@if kill -0 `cat $(PID_FILE)` 2>/dev/null; then \
		echo "✓ SenseVoice API started successfully (PID: `cat $(PID_FILE)`)"; \
		echo "  View logs: make logs"; \
		echo "  Tail logs: make tail"; \
		echo "  Stop API: make stop"; \
	else \
		echo "✗ Failed to start SenseVoice API. Check logs: cat $(LOG_FILE)"; \
		rm -f $(PID_FILE); \
		exit 1; \
	fi

# Start with GPU support in background
start-gpu:
	@mkdir -p $(LOG_DIR)
	@if [ -f $(PID_FILE) ] && kill -0 `cat $(PID_FILE)` 2>/dev/null; then \
		echo "SenseVoice API is already running (PID: `cat $(PID_FILE)`)"; \
		echo "Use 'make stop' to stop it first"; \
		exit 1; \
	fi
	@echo "Starting SenseVoice API in background on GPU (port $(PORT))..."
	@echo "Log file: $(LOG_FILE)"
	@nohup sh -c 'SENSEVOICE_DEVICE=cuda:0 PORT=$(PORT) $(PYTHON) -u $(API_FILE)' > $(LOG_FILE) 2>&1 & echo $$! > $(PID_FILE)
	@sleep 2
	@if kill -0 `cat $(PID_FILE)` 2>/dev/null; then \
		echo "✓ SenseVoice API started successfully (PID: `cat $(PID_FILE)`)"; \
		echo "  View logs: make logs"; \
		echo "  Tail logs: make tail"; \
		echo "  Stop API: make stop"; \
	else \
		echo "✗ Failed to start SenseVoice API. Check logs: cat $(LOG_FILE)"; \
		rm -f $(PID_FILE); \
		exit 1; \
	fi

# Stop the running API
stop:
	@if [ -f $(PID_FILE) ]; then \
		if kill -0 `cat $(PID_FILE)` 2>/dev/null; then \
			echo "Stopping SenseVoice API (PID: `cat $(PID_FILE)`)..."; \
			kill `cat $(PID_FILE)`; \
			rm -f $(PID_FILE); \
			echo "✓ SenseVoice API stopped"; \
		else \
			echo "Process not found. Cleaning up PID file..."; \
			rm -f $(PID_FILE); \
		fi \
	else \
		echo "SenseVoice API is not running"; \
	fi

# Restart the API
restart: stop start

# Check API status
status:
	@if [ -f $(PID_FILE) ] && kill -0 `cat $(PID_FILE)` 2>/dev/null; then \
		echo "✓ SenseVoice API is running (PID: `cat $(PID_FILE)`)"; \
		echo "  Port: $(PORT)"; \
		echo "  Device: $(DEVICE)"; \
		echo "  Latest log: `ls -t $(LOG_DIR)/sensevoice_api_*.log 2>/dev/null | head -1`"; \
		echo "  API URL: http://localhost:$(PORT)"; \
	else \
		echo "✗ SenseVoice API is not running"; \
		if [ -f $(PID_FILE) ]; then \
			rm -f $(PID_FILE); \
		fi \
	fi

# View latest log file
logs:
	@if ls $(LOG_DIR)/sensevoice_api_*.log 1> /dev/null 2>&1; then \
		LATEST_LOG=`ls -t $(LOG_DIR)/sensevoice_api_*.log | head -1`; \
		echo "Viewing log: $$LATEST_LOG"; \
		echo "---"; \
		cat $$LATEST_LOG; \
	else \
		echo "No log files found in $(LOG_DIR)/"; \
	fi

# Tail latest log file
tail:
	@if ls $(LOG_DIR)/sensevoice_api_*.log 1> /dev/null 2>&1; then \
		LATEST_LOG=`ls -t $(LOG_DIR)/sensevoice_api_*.log | head -1`; \
		echo "Tailing log: $$LATEST_LOG (Ctrl+C to stop)"; \
		echo "---"; \
		tail -f $$LATEST_LOG; \
	else \
		echo "No log files found in $(LOG_DIR)/"; \
	fi

# Run in foreground (for debugging)
run-fg:
	@echo "Starting SenseVoice API in foreground on CPU (port $(PORT))..."
	SENSEVOICE_DEVICE=$(DEVICE) PORT=$(PORT) $(PYTHON) $(API_FILE)

# Run with GPU in foreground
run-gpu:
	@echo "Starting SenseVoice API in foreground on GPU (port $(PORT))..."
	SENSEVOICE_DEVICE=cuda:0 PORT=$(PORT) $(PYTHON) $(API_FILE)

# Run with custom port in foreground
run-port:
	@echo "Starting SenseVoice API in foreground on port $(PORT)..."
	SENSEVOICE_DEVICE=$(DEVICE) PORT=$(PORT) $(PYTHON) $(API_FILE)

# Install dependencies
install:
	@echo "Installing dependencies..."
	pip install -r requirements.txt

# Install with uv (faster)
install-uv:
	@echo "Installing dependencies with uv..."
	uv pip install -r requirements.txt

# Docker operations
docker-build:
	@echo "Building Docker image..."
	docker-compose build

docker-up:
	@echo "Starting Docker container..."
	docker-compose up -d

docker-down:
	@echo "Stopping Docker container..."
	docker-compose down

docker-logs:
	@echo "Showing Docker logs..."
	docker-compose logs -f

docker-restart:
	@echo "Restarting Docker container..."
	docker-compose restart

# Run tests
test:
	@echo "Running tests..."
	cd test && $(PYTHON) -m pytest

# Clean up cache and temp files
clean:
	@echo "Cleaning up..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name ".DS_Store" -delete
	rm -rf .pytest_cache
	rm -rf .coverage
	rm -rf htmlcov
	rm -rf dist
	rm -rf build
	rm -rf *.egg-info

# Clean log files
clean-logs:
	@echo "Cleaning log files..."
	rm -rf $(LOG_DIR)
	rm -f $(PID_FILE)

# Check if model files exist
check-models:
	@echo "Checking for model files..."
	@if [ -d "models" ]; then \
		echo "Models directory exists"; \
		ls -la models/; \
	else \
		echo "Models directory not found. Models will be downloaded on first run."; \
	fi

# Display help
help:
	@echo "SenseVoice Makefile Commands:"
	@echo ""
	@echo "Background Process Management:"
	@echo "  make              - Start API in background with CPU (default)"
	@echo "  make start        - Same as 'make'"
	@echo "  make start-gpu    - Start API in background with GPU"
	@echo "  make stop         - Stop the running API"
	@echo "  make restart      - Restart the API"
	@echo "  make status       - Check API status"
	@echo ""
	@echo "Log Management:"
	@echo "  make logs         - View latest log file"
	@echo "  make tail         - Follow latest log file in real-time"
	@echo "  make clean-logs   - Remove all log files"
	@echo ""
	@echo "Foreground Execution (for debugging):"
	@echo "  make run-fg       - Run API in foreground with CPU"
	@echo "  make run-gpu      - Run API in foreground with GPU"
	@echo "  make run-port PORT=8080  - Run in foreground with custom port"
	@echo ""
	@echo "Dependencies:"
	@echo "  make install      - Install Python dependencies"
	@echo "  make install-uv   - Install dependencies with uv (faster)"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-build - Build Docker image"
	@echo "  make docker-up    - Start Docker container"
	@echo "  make docker-down  - Stop Docker container"
	@echo "  make docker-logs  - Show Docker logs"
	@echo "  make docker-restart - Restart Docker container"
	@echo ""
	@echo "Others:"
	@echo "  make test         - Run tests"
	@echo "  make clean        - Clean cache and temp files"
	@echo "  make check-models - Check if model files exist"
	@echo "  make help         - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make              # Start in background (CPU, port 7861)"
	@echo "  make start-gpu    # Start in background with GPU"
	@echo "  make status       # Check if API is running"
	@echo "  make tail         # Follow logs in real-time"
	@echo "  make stop         # Stop the API"
	@echo ""
	@echo "Logs are saved in: $(LOG_DIR)/"
	@echo "PID file: $(PID_FILE)"