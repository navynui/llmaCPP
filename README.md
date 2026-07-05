# llmaCPP — Local LLM Control Center

A personal Docker-based stack for managing local LLM inference, a web-based manager, and image generation.

## Architecture

The system consists of four main components:

| Component | Role | Details |
|---|---|---|
| **`llama-server`** (Primary) | Core LLM Server | llama.cpp inference backend on GPU 0 (Tesla P100), Port `8080`. Configured via `models.ini`. |
| **`llama-server-mini`** (Secondary) | Secondary LLM Server | llama.cpp inference backend on GPU 1 (GTX 1060), Port `8081`. Configured via `modelg.ini`. |
| **`llm-mobile`** | Web Control Panel | UI for server control, chat, benchmarking, model management, and ComfyUI gateway (Port `8000`). |
| **`comfyUI`** | Image Generation | Third-party container for single/batch image generation (Port `8188`). |

Both `llama-server` instances share the same `/models` volume but maintain separate model preset configurations and can run different models simultaneously on separate GPUs.

## Key Features

- **Dual LLM Inference**: Run two independent `llama-server` instances on separate GPUs (Tesla P100 + GTX 1060), each with its own model preset config.
- **Per-Server Control**: Independently start, stop, and restart each server from the web UI.
- **Per-Server Model Management**: Each server has its own INI file (`models.ini` for primary, `modelg.ini` for secondary) with load/unload/scan/delete via the web UI.
- **Chat Server Selector**: Choose which server to chat with from the Chat tab.
- **Multi-GPU Telemetry**: Temperature, utilization, and VRAM metrics for both GPUs via MQTT.
- **Model Orchestration**: Seamlessly switch models via Router Mode.
- **Intelligent Benchmarking**: Integrated Benchmark module to track model TPS and qualitative scores via SQLite.
- **Image Pipeline**: Integrated ComfyUI interface with batch generation and local gallery management.

## Repository Layout

- `docker-compose.yml`: Primary configuration for all containers (`llama-server`, `llama-server-mini`, `llm-mobile`, `comfyui`).
- `models/`: GGUF model weights (git-ignored).
- `models/models.ini`: Model preset config for primary server.
- `models/modelg.ini`: Model preset config for secondary (mini) server.
- `source/`: llama.cpp upstream source (git-ignored).
- `compose-backup/`: Archived and experimental configurations.

## Quick Start

### Deploy
```bash
docker compose up -d
```

### Manage
Access the **llm-mobile** UI at `http://localhost:8000` to control both LLM servers and interface with ComfyUI.

### Build `llama-server`
If the image needs updating from `source/`:
```bash
cd source && docker build -f .devops/cuda.Dockerfile --target server -t llama-server:latest .
```

## Configuration Note

- Primary server runtime parameters are in the `command:` section of the `llama-server` service in `docker-compose.yml`. Model presets are in `models/models.ini`.
- Secondary server runtime parameters are in the `command:` section of the `llama-server-mini` service. Model presets are in `models/modelg.ini`.
- Both servers support **Router Mode** via their respective INI files.

## Model INI Files

### Primary (`models/models.ini`)
Used by `llama-server` on GPU 0 (Tesla P100).

### Secondary (`models/modelg.ini`)
Used by `llama-server-mini` on GPU 1 (GTX 1060).
Both follow the same INI format:
```ini
[ModelName.gguf]
model = /models/ModelName.gguf
n-gpu-layers = -1
ctx-size = 4096
```
