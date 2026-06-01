# llmaCPP — Local LLM Deployment Stack

A personal Docker-based deployment stack for running quantized large language models locally using [llama.cpp](https://github.com/ggml-org/llama.cpp), paired with a web management interface.

---

## Overview

This repository orchestrates two Docker services:

| Service | Container | Port | Description |
|---|---|---|---|
| `llama-server` | `llm-server` | `8080` | llama.cpp inference server (OpenAI-compatible API) |
| `llm-manager` | `llm-manager` | `8000` | Web UI & management layer for the LLM stack |

The `llm-manager` waits for `llama-server` to pass a health check before starting, ensuring the inference backend is ready.

---

## Directory Structure

```
llmaCPP/
├── docker-compose.yml        # Active deployment configuration
├── models/                   # GGUF model files (git-ignored)
│   ├── Qwen3.6-35B-A3B-UD-IQ3_S.gguf
│   ├── Qwen3.6-mmproj-F16.gguf       # Multimodal projector for Qwen3.6
│   ├── Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf
│   ├── Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf
│   ├── mmproj-Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-BF16.gguf
│   ├── gemma-4-E4B-it-Q4_K_M.gguf
│   └── mmproj-F16.gguf               # Multimodal projector for Gemma 4
├── source/                   # llama.cpp source code (git-ignored, cloned upstream)
│   ├── .devops/              # Dockerfiles for various backends (CUDA, ROCm, Vulkan…)
│   ├── examples/             # llama.cpp example binaries
│   ├── src/                  # Core C/C++ source
│   └── ...
└── compose-backup/           # Historical / experimental compose configurations
    ├── docker-compose-gemma4-E4B.yml
    ├── docker-compose-gemma4-E4B-MTP.yml
    ├── docker-compose-gemma4-26b.yml
    ├── docker-compose-gemma4-21b-REAP.yml
    ├── docker-compose-gemma4-26b-2.yml
    ├── docker-compose-gemma4-26b-MTP-notGood-7tps.yml
    ├── docker-compose-gemma4-uncen-65536-works.yml
    ├── docker-compose-combo-works.yml
    └── docker-compose-combo-works-before-move-folder.yml
```

> `models/` and `source/` are listed in `.gitignore` and are **not tracked** by git.

---

## Active Configuration (`docker-compose.yml`)

### `llama-server`

Runs the llama.cpp HTTP inference server with the following settings:

| Parameter | Value |
|---|---|
| Image | `llama-server:latest` (pre-built) |
| Model | `Qwen3.6-35B-A3B-UD-IQ3_S.gguf` |
| Multimodal projector | `Qwen3.6-mmproj-F16.gguf` |
| Model alias | `local-model` |
| Context size | 65,536 tokens |
| GPU layers | All (`-1`) |
| Flash attention | Enabled |
| KV cache type (K) | `turbo4` |
| KV cache type (V) | `turbo2` |
| µBatch size | 2048 |
| CPU threads | 7 |
| Memory | `mlock` + `no-mmap` (memory-locked, no memory mapping) |
| Repeat penalty | 1.1 |

**Resource requirements:**
- 1× NVIDIA GPU (full VRAM, `n-gpu-layers -1`)
- Unlimited memlock (`IPC_LOCK` capability, `ulimits.memlock: -1`)

**Health check:** `curl -f http://localhost:8080/health` every 10 s, 5 retries.

### `llm-manager`

A web management application (built from `/home/nui/dev/llmWEB`) that provides:

- A UI and API layer on top of the inference server
- Docker socket access for container management
- ComfyUI integration (image generation output at `/comfyui-output`)
- Prompt template management (`PROMPTS/` volume)
- UV Python environment cache shared read-only

**Environment variables:**

| Variable | Value |
|---|---|
| `LLM_COMPOSE_DIR` | `/llm-server` (maps to `/home/nui/llmaCPP`) |
| `LLM_PROJECT_NAME` | `llmacpp` |
| `COMFYUI_HOST` | `host.docker.internal:8188` |

---

## Usage

### Start the stack

```bash
docker compose up -d
```

### Stop the stack

```bash
docker compose down
```

### View logs

```bash
docker compose logs -f
```

### Check server health

```bash
curl http://localhost:8080/health
```

### OpenAI-compatible API

The inference server exposes an OpenAI-compatible API at `http://localhost:8080`. Example:

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local-model",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

---

## Building the llama-server Image

The `llama-server:latest` image is built from the llama.cpp source in `source/` using the CUDA Dockerfile:

```bash
cd source
docker build \
  -f .devops/cuda.Dockerfile \
  --target server \
  --build-arg CUDA_DOCKER_ARCH=all \
  -t llama-server:latest \
  .
```

> The compose-backup files show `CUDA_DOCKER_ARCH=60` was used for a Tesla P100. Adjust for your GPU architecture.

---

## Model Archive

All GGUF model files are stored in `models/` (not tracked by git). Currently present:

| File | Size | Notes |
|---|---|---|
| `Qwen3.6-35B-A3B-UD-IQ3_S.gguf` | ~12.7 GB | **Active** — IQ3_S quant |
| `Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf` | ~16 GB | Q4_K_M quant |
| `Qwen3.6-mmproj-F16.gguf` | ~858 MB | Multimodal projector for Qwen3.6 |
| `Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf` | ~5.2 GB | |
| `mmproj-Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-BF16.gguf` | ~879 MB | Projector |
| `gemma-4-E4B-it-Q4_K_M.gguf` | ~4.6 GB | |
| `mmproj-F16.gguf` | ~1 GB | Projector for Gemma 4 |

---

## Experimental Configurations (`compose-backup/`)

A history of tested configurations for reference and rollback:

| File | Model | Notes |
|---|---|---|
| `docker-compose-gemma4-E4B.yml` | Gemma 4 E4B Q4_K_M | Basic, ctx 32768 |
| `docker-compose-gemma4-E4B-MTP.yml` | Gemma 4 E4B + MTP head | Speculative decoding, ~+30-50% throughput |
| `docker-compose-gemma4-26b.yml` | Gemma 4 26B Q4_K_M | 27 GPU layers, ctx 16384 (16 GB VRAM) |
| `docker-compose-gemma4-26b-MTP-notGood-7tps.yml` | Gemma 4 26B MTP | Marked as low performance (7 t/s) |
| `docker-compose-gemma4-21b-REAP.yml` | Gemma 4 21B REAP | Non-thinking mode, ctx 32768 |
| `docker-compose-gemma4-uncen-65536-works.yml` | Uncensored variant | ctx 65536 |
| `docker-compose-combo-works.yml` | Gemma 4 E4B + llm-manager | First working combo |
| `docker-compose-combo-works-before-move-folder.yml` | Qwen3.5 9B + llm-manager | Pre-refactor layout |

---

## Requirements

- Docker with Compose plugin
- NVIDIA GPU with CUDA support
- NVIDIA Container Toolkit (`nvidia-docker2`)
- Sufficient VRAM for the chosen model
- `llama-server:latest` image built locally (see above)
- llmWEB project at `/home/nui/dev/llmWEB` (for `llm-manager`)
