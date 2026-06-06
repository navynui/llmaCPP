# llmaCPP — Local LLM Control Center

A personal Docker-based stack for managing local LLM inference, a web-based manager, and image generation.

## Architecture

The system consists of three main components:

| Component | Role | Details |
|---|---|---|
| **`llama-server`** | Core LLM Server | llama.cpp inference backend exposing OpenAI-compatible API (Port `8080`). |
| **`llm-manager`** | Web Control Panel | UI for managing the server (start/stop), chat interface, MD file reader, and ComfyUI gateway (Port `8000`). |
| **`comfyUI`** | Image Generation | Third-party container for single/batch image generation and gallery management (Port `8188`). |

## Repository Layout

- `docker-compose.yml`: Primary configuration for `llama-server` and `llm-manager`.
- `models/`: GGUF model weights (git-ignored).
- `source/`: llama.cpp upstream source (git-ignored).
- `compose-backup/`: Archived and experimental configurations.

## Quick Start

### Deploy
```bash
docker compose up -d
```

### Manage
Access the **llm-manager** at `http://localhost:8000` to control the LLM server and interface with ComfyUI.

### Build `llama-server`
If the image needs updating from `source/`:
```bash
cd source && docker build -f .devops/cuda.Dockerfile --target server -t llama-server:latest .
```

## Configuration Note
All server runtime parameters (model path, context size, GPU layers) are configured in the `command:` section of `docker-compose.yml`. 
The system also supports **Router Mode** via `models.ini`, allowing the manager to swap between multiple pre-configured models without recreating the container.
