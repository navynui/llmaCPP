# llmaCPP — Local LLM Control Center

A personal Docker-based stack for managing local LLM inference, a web-based manager, and image generation.

## Architecture

The system consists of four main components:

| Component | Role | Details |
|---|---|---|
| **`llama-server`** (Primary) | Core LLM Server | llama.cpp inference backend on GPU 0 (Tesla P100), Port `8080`. Configured via `models.ini`. Can split large models across both GPUs (see below). |
| **`llama-server-mini`** (Secondary) | Secondary LLM Server | llama.cpp inference backend on GPU 1 (GTX 1060), Port `8081`. Configured via `modelg.ini`. |
| **`llm-mobile`** | Web Control Panel | UI for server control, chat, benchmarking, model management, and ComfyUI gateway (Port `8000`). |
| **`comfyUI`** | Image Generation | Third-party container for single/batch image generation (Port `8188`). |

Both `llama-server` instances share the same `/models` volume but maintain separate model preset configurations and can run different models simultaneously on separate GPUs.

The primary runs the **Kmic-68 P100 fork** (`llama-server:kmic-nov9`, source in `source-kmic-68/`), which is tuned for sm_60 and supports MTP, router mode, and per-model GPU splitting. The mini runs **upstream ggml-org/llama.cpp** (`llama-server:ggml-nov16`, source in `source-ggml/`), built for sm_60 + sm_61 with MTP and router mode. The **TheTom fork** (`source-thetom/`, TurboQuant KV `turbo4/3/2`) is kept as the rollback image.

## Key Features

- **Dual LLM Inference**: Run two independent `llama-server` instances on separate GPUs (Tesla P100 + GTX 1060), each with its own model preset config.
- **Multi-GPU Split (per-preset)**: Large models (e.g. the 27B trio) can be split across the P100 + 1060 via `device`/`split-mode layer`/`tensor-split` in `models.ini`; small models run unsplit on the P100 with no PCIe overhead. Defaults live in the `[*]` INI section.
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
- `models/models.ini`: Model preset config for primary server (includes per-preset GPU split for 27B family).
- `models/modelg.ini`: Model preset config for secondary (mini) server.
- `source-kmic-68/`: Kmic-68 P100 fork build source (git-ignored) — primary image.
- `source-ggml/`: Upstream ggml-org llama.cpp build source (git-ignored) — mini image.
- `source-thetom/`: TheTom fork build source (git-ignored) — rollback image.
- `script/`: Build scripts (`build-kmic.sh`, `build-ggml.sh`, `build-thetom.sh`) and `bench-image-ab.sh`.
- `compose-backup/`: Archived and experimental configurations.

## Quick Start

### Deploy
```bash
docker compose up -d
```

### Manage
Access the **llm-mobile** UI at `http://localhost:8000` to control both LLM servers and interface with ComfyUI.

### Build the images
```bash
./script/build-kmic.sh --tag llama-server:kmic-nov9      # primary, sm_60 only
./script/build-ggml.sh --tag llama-server:ggml-nov16    # mini, sm_60 + sm_61
./script/build-thetom.sh                                # rollback image
```
The ggml script builds `source-ggml/` with `CUDA_DOCKER_ARCH="60;61"` and tags the image `llama-server:ggml-nov16`. The Kmic script builds sm_60 only so the P100 tuning stays enabled.

## Configuration Note

- Primary server runtime parameters are in the `command:` section of the `llama-server` service in `docker-compose.yml`. Model presets are in `models/models.ini`.
- Secondary server runtime parameters are in the `command:` section of the `llama-server-mini` service. Model presets are in `models/modelg.ini`.
- Both servers support **Router Mode** via their respective INI files.
- **Multi-GPU defaults belong in the INI `[*]` section, not the compose `command:`** — per-model presets then override them (CLI command args beat INI values, so the single-GPU default lives in `[*]`).

## Model INI Files

### Primary (`models/models.ini`)
Used by `llama-server` on GPU 0 (Tesla P100). Use `q4_0` KV (Kmic has no TurboQuant).

### Secondary (`models/modelg.ini`)
Used by `llama-server-mini` on GPU 1 (GTX 1060). Use `q4_0` KV (upstream ggml has no TurboQuant; `turbo*` only exists in the TheTom rollback).
Both follow the same INI format:
```ini
[ModelName.gguf]
model = /models/ModelName.gguf
n-gpu-layers = -1
ctx-size = 4096
```
