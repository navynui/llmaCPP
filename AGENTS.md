# AGENTS.md — AI Agent Guidelines for llmaCPP

This file describes how AI coding agents (Copilot, Gemini, Claude, Cursor, etc.) should interact with this repository.

---

## What This Repository Is

`llmaCPP` is a **personal Docker deployment stack**. It orchestrates:

1. **`llama-server`** — Primary llama.cpp inference container on GPU 0 (Tesla P100, Port `8080`).
2. **`llama-server-mini`** — Secondary llama.cpp inference container on GPU 1 (GTX 1060, Port `8081`).
3. **`llm-mobile`** — Web UI for server control, chat, benchmarking, and ComfyUI gateway (Port `8000`).
4. **`comfyUI`** — Image generation container (Port `8188`) integrated via `llm-mobile`.

The primary artifact is [`docker-compose.yml`](docker-compose.yml). Everything else (`source-thetom/`, `source/`, `models/`, `compose-backup/`) is supporting material.

**Runtime fork:** The image `llama-server:latest` is built from the **TheTom fork** (`source-thetom/` @ `feature/turboquant-kv-cache`, `d0e2a8b64`) — not upstream. It adds TurboQuant KV cache (`turbo4/3/2`), MTP speculative decoding, router mode, and per-preset multi-GPU split.

---

## Repository Layout at a Glance

```
llmaCPP/
├── docker-compose.yml        # ← PRIMARY FILE. Edit this to change the running config.
├── models/
│   ├── models.ini            # Primary server model presets (llama-server), incl. per-preset GPU split
│   ├── modelg.ini            # Secondary server model presets (llama-server-mini)
│   └── *.gguf                # Binary model weights (git-ignored)
├── source-thetom/            # TheTom fork build source (git-ignored, read-only reference) — image is built from here
├── source/                   # Legacy llama.cpp upstream clone (git-ignored, read-only, NO LONGER built)
├── llm_bench.db              # SQLite benchmark data (persisted via volume)
└── compose-backup/           # Archived compose configs, DO NOT delete, useful for reference
```

---

## Key Rules for Agents

### 1. `docker-compose.yml` is the source of truth
- All changes to container configs, runtime parameters, ports, or volumes happen **only** in `docker-compose.yml`.
- Do **not** modify files inside `source-thetom/` or `source/` — `source-thetom/` is the fork the built image comes from; `source/` is a legacy clone. Both are git-ignored and read-only references.

### 2. Models directory is git-ignored
- `models/` contains large binary GGUF files. Never suggest committing them.
- When referencing model paths, always use `/models/<filename>.gguf` (as mounted inside the container).

### 3. Two llama-server instances
The stack runs **two** independent `llama-server` containers:

| Service | Container Name | Host Port | GPU | INI Config | Role |
|---|---|---|---|---|---|
| `llama-server` | `llm-server` | 8080 | GPU 0 (Tesla P100) | `models.ini` | Primary inference |
| `llama-server-mini` | `llm-server-mini` | 8081 | GPU 1 (GTX 1060) | `modelg.ini` | Secondary inference |

Both share the `/models` volume. Each has its own `command:` section and model preset file.

### 4. llama-server command-line flags
Both servers are configured entirely via command-line flags in the `command:` key. Common flags:

| Flag | Purpose |
|---|---|
| `--models-preset <path>` | Path to the model preset INI file (e.g., `/models/models.ini`) |
| `-m <path>` | Model file path (overridden by INI presets) |
| `--mmproj <path>` | Multimodal vision projector |
| `--alias <name>` | Model alias for API calls |
| `--host 0.0.0.0` | Bind to all interfaces |
| `--port 8080` | Listening port (inside container) |
| `--n-gpu-layers -1` | Offload all layers to GPU |
| `--ctx-size <n>` | Context window size in tokens |
| `--flash-attn on` | Enable flash attention |
| `--cache-type-k / --cache-type-v` | KV cache quantization (`turbo4`, `turbo3`, `turbo2`, `q4_0`, `f16`, …) |
| `--ubatch-size <n>` | Physical micro-batch size |
| `--threads <n>` | CPU threads |
| `--load-mode mlock` | Load + lock model in RAM/VRAM (replaces deprecated `--no-mmap` + `--mlock`) |
| `--device <dev1,dev2,..>` | Comma-separated devices for offloading (e.g. `CUDA0,CUDA1`); override per preset in the INI |
| `--split-mode {none,layer,row,tensor}` | Layer/row/tensor split across multi-GPU (`none` = single GPU) |
| `--tensor-split N0,N1,N2` | Fraction of model per GPU (e.g. `5,1` for a ~5:1 split) |
| `--main-gpu INDEX` | Primary GPU for intermediates/KV (default `0`) |
| `--repeat-penalty <f>` | Repetition penalty |
| `-np <n>` | Number of parallel slots (concurrent requests) |
| `--n-gpu-layers-draft -1` | For MTP/speculative decoding: offload draft head layers |
| `--mtp-head <path>` | MTP speculative decoding drafter head |
| `--spec-type mtp` | Speculative decoding strategy |

`llama-server-mini` uses identical flags but targets GPU 1 via `device_ids: ['1']` in the `deploy.resources` section.

### Multi-GPU split (primary only, per-preset)
- The primary exposes both GPUs (`device_ids: ['0', '1']`). Whether a model splits is decided **per preset in `models.ini`**, not in the compose `command:`.
- `models.ini` `[*]` sets the single-GPU default (`device = CUDA0`, `split-mode = none`). The 27B presets override to `device = CUDA0,CUDA1`, `split-mode = layer`, `tensor-split = 5,1`, `main-gpu = 0`.
- **Gotcha:** CLI command args BEAT INI preset values. Only the INI `[*]` section is overridable per-model — put multi-GPU defaults in `[*]`, never set `--device`/`--split-mode` in the compose `command:`.
- Coexistence rule: primary single-GPU + mini E4B on the 1060 works; primary 27B split (≈4.8 GiB on the 1060) + mini conflict on the 6 GB card — keep the mini idle for 27B sessions.

### 5. KV cache type guidance
The `turbo*` types are TurboQuant WHT-rotated low-bit formats available in this build:

| Type | Approx compression | Notes |
|---|---|---|
| `turbo4` | ~4-bit | Good for K cache |
| `turbo3` | ~3-bit | Balanced |
| `turbo2` | ~2-bit | Aggressive, best for V cache |
| `q4_0` | ~4-bit | Standard, broader compatibility |
| `f16` | 16-bit | No compression, highest quality |

### 6. GPU device allocation
- **`llama-server`** exposes `device_ids: ['0','1']` → Tesla P100 (16 GB) + GTX 1060 (6 GB). Small models run on the P100 alone; large 27B-family models split across both (per-preset).
- **`llama-server-mini`** uses `device_ids: ['1']` → GTX 1060 (6 GB).
- Always verify VRAM budget fits the model + KV cache before changing parameters. The 1060 is the tight resource: it hosts the mini's E4B (≈5.5 GiB) *or* the primary's 27B split (≈4.8 GiB), not both.

### 7. `llm-mobile` environment variables
When editing the `llm-mobile` service:

| Variable | Meaning |
|---|---|
| `LLM_COMPOSE_DIR` | Path **inside the container** to the llmaCPP directory (mapped via volume) |
| `LLM_PROJECT_NAME` | Docker Compose project name used to control containers |
| `COMFYUI_HOST` | Host:port for the ComfyUI image generation service |

### 8. `compose-backup/` is read-only reference
- Do **not** delete or overwrite files in `compose-backup/`.
- When experimenting with a new configuration, copy the active `docker-compose.yml` to `compose-backup/` with a descriptive name **before** modifying it.
- Naming convention: `docker-compose-<model-shortname>[-variant].yml`

---

## How to Switch Models

### Primary Server
1. Copy current `docker-compose.yml` to `compose-backup/docker-compose-<description>.yml`
2. Edit `models/models.ini` to add/change model presets
3. Use the llm-mobile UI to reload the INI and load the new model

### Secondary Server
1. Edit `models/modelg.ini` to add/change model presets
2. Use the llm-mobile UI to reload the INI and load the new model on the secondary GPU

To change server-level parameters (threads, cache types, etc.), edit the `command:` section of the respective service in `docker-compose.yml`, then restart:
```bash
docker compose up -d --force-recreate llama-server     # Restart primary only
docker compose up -d --force-recreate llama-server-mini # Restart secondary only
```

---

## Checklist Before Editing `docker-compose.yml`

- [ ] The target model file exists in `models/`
- [ ] VRAM is sufficient for the target GPU (`--n-gpu-layers -1` requires full model VRAM + KV cache)
- [ ] If using a vision model, `--mmproj` points to the correct projector file
- [ ] Use `--load-mode mlock` (NOT the deprecated `--no-mmap`/`--mlock`)
- [ ] If a model should split across both GPUs, set `device`/`split-mode`/`tensor-split` in its `models.ini` preset (defaults live in `[*]`), not in the compose `command:`
- [ ] Context size is within GPU memory budget (larger ctx = more VRAM cache)
- [ ] `LLM_PROJECT_NAME` in `llm-mobile` matches the Compose project name used when deploying
- [ ] If adding a new GPU-heavy service, verify `device_ids` doesn't conflict with existing allocations
- [ ] `source-thetom/` and `source/` are read-only references — never edit or build from anything but `source-thetom/`

---

## Do Not Touch

| Path | Reason |
|---|---|
| `source-thetom/` | TheTom fork clone the image is built from (git-ignored, rebuilt via Docker) |
| `source/` | Legacy llama.cpp upstream clone, git-ignored, no longer built |
| `models/*.gguf` | Binary model weights, git-ignored |
| `.git/` | Version control internals |
