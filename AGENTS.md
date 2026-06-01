# AGENTS.md — AI Agent Guidelines for llmaCPP

This file describes how AI coding agents (Copilot, Gemini, Claude, Cursor, etc.) should interact with this repository.

---

## What This Repository Is

`llmaCPP` is a **personal Docker deployment stack** — not a library or application codebase. It orchestrates two services:

1. **`llama-server`** — a llama.cpp inference container exposing an OpenAI-compatible HTTP API on port `8080`
2. **`llm-manager`** — a web management UI/API built from a separate project (`~/dev/llmWEB`), running on port `8000`

The primary artifact is [`docker-compose.yml`](docker-compose.yml). Everything else (`source/`, `models/`, `compose-backup/`) is supporting material.

---

## Repository Layout at a Glance

```
llmaCPP/
├── docker-compose.yml        # ← PRIMARY FILE. Edit this to change the running config.
├── models/                   # GGUF model weights (git-ignored, do NOT commit)
├── source/                   # llama.cpp upstream source (git-ignored, read-only reference)
└── compose-backup/           # Archived compose configs, DO NOT delete, useful for reference
```

---

## Key Rules for Agents

### 1. `docker-compose.yml` is the source of truth
- All changes to which model is loaded, runtime parameters, ports, or volumes happen **only** in `docker-compose.yml`.
- Do **not** modify files inside `source/` — it is an upstream clone and is git-ignored.

### 2. Models directory is git-ignored
- `models/` contains large binary GGUF files. Never suggest committing them.
- When referencing model paths, always use `/models/<filename>.gguf` (as mounted inside the container).

### 3. llama-server command-line flags
The server is configured entirely via command-line flags in the `command:` key. Common flags:

| Flag | Purpose |
|---|---|
| `-m <path>` | Model file path |
| `--mmproj <path>` | Multimodal vision projector |
| `--alias <name>` | Model alias for API calls |
| `--host 0.0.0.0` | Bind to all interfaces |
| `--port 8080` | Listening port |
| `--n-gpu-layers -1` | Offload all layers to GPU |
| `--ctx-size <n>` | Context window size in tokens |
| `--flash-attn on` | Enable flash attention |
| `--cache-type-k / --cache-type-v` | KV cache quantization (`turbo4`, `turbo3`, `turbo2`, `q4_0`, `f16`, …) |
| `--ubatch-size <n>` | Physical micro-batch size |
| `--threads <n>` | CPU threads |
| `--no-mmap` | Disable memory-mapped I/O (needed with `--mlock`) |
| `--mlock` | Lock model weights in RAM/VRAM |
| `--repeat-penalty <f>` | Repetition penalty |
| `--flash-attn on` | Flash attention |
| `-np <n>` | Number of parallel slots (concurrent requests) |
| `--n-gpu-layers-draft -1` | For MTP/speculative decoding: offload draft head layers |
| `--mtp-head <path>` | MTP speculative decoding drafter head |
| `--spec-type mtp` | Speculative decoding strategy |

### 4. KV cache type guidance
The `turbo*` types are TurboQuant WHT-rotated low-bit formats available in this build:

| Type | Approx compression | Notes |
|---|---|---|
| `turbo4` | ~4-bit | Good for K cache |
| `turbo3` | ~3-bit | Balanced |
| `turbo2` | ~2-bit | Aggressive, best for V cache |
| `q4_0` | ~4-bit | Standard, broader compatibility |
| `f16` | 16-bit | No compression, highest quality |

### 5. GPU layer tuning
- `-1` = all layers on GPU (requires enough VRAM for the full model + KV cache)
- Partial offload (e.g., `--n-gpu-layers 27`) for large models on 16 GB VRAM

### 6. MTP / Speculative Decoding (Gemma 4)
The `compose-backup/docker-compose-gemma4-E4B-MTP.yml` shows a working MTP setup:
- Requires a matching `assistant` GGUF head loaded via `--mtp-head`
- Use `--spec-type mtp`, `--draft-block-size`, and `--draft-max` to tune
- Yields ~+30–50% throughput on short prompts

### 7. `llm-manager` environment variables
When editing the `llm-manager` service:

| Variable | Meaning |
|---|---|
| `LLM_COMPOSE_DIR` | Path **inside the container** to the llmaCPP directory (mapped via volume) |
| `LLM_PROJECT_NAME` | Docker Compose project name used to control the `llama-server` container |
| `COMFYUI_HOST` | Host:port for the ComfyUI image generation service |

### 8. `compose-backup/` is read-only reference
- Do **not** delete or overwrite files in `compose-backup/`.
- When experimenting with a new configuration, copy the active `docker-compose.yml` to `compose-backup/` with a descriptive name **before** modifying it.
- Naming convention: `docker-compose-<model-shortname>[-variant].yml`

---

## How to Switch Models

1. Copy the current `docker-compose.yml` to `compose-backup/docker-compose-<description>.yml`
2. Edit the `command:` key in `docker-compose.yml`:
   - Change `-m /models/<new-model>.gguf`
   - Update `--mmproj` if the model family changed
   - Tune `--n-gpu-layers`, `--ctx-size`, `--cache-type-k/v` for the new model's size
3. Restart: `docker compose up -d --force-recreate llama-server`

---

## Checklist Before Editing `docker-compose.yml`

- [ ] The target model file exists in `models/`
- [ ] VRAM is sufficient (`--n-gpu-layers -1` requires full model VRAM + KV cache)
- [ ] If using a vision model, `--mmproj` points to the correct projector file
- [ ] `--mlock` is only used alongside `--no-mmap`
- [ ] Context size is within GPU memory budget (larger ctx = more KV cache VRAM)
- [ ] `LLM_PROJECT_NAME` in `llm-manager` matches the Compose project name used when deploying

---

## Do Not Touch

| Path | Reason |
|---|---|
| `source/` | Upstream llama.cpp clone, git-ignored, rebuilt via Docker |
| `models/*.gguf` | Binary model weights, git-ignored |
| `.git/` | Version control internals |
