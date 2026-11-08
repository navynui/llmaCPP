# AGENTS.md — AI Agent Guidelines for llmaCPP

This file describes how AI coding agents (Copilot, Gemini, Claude, Cursor, etc.) should interact with this repository.

---

## What This Repository Is

`llmaCPP` is a **personal Docker deployment stack**. It orchestrates:

1. **`llama-server`** — Primary llama.cpp inference container on GPU 0 (Tesla P100, Port `8080`), image `llama-server:kmic-p100-nov6`.
2. **`llama-server-mini`** — Secondary llama.cpp inference container on GPU 1 (GTX 1060, Port `8081`), image `llama-server:thetom-nov8`.
3. **`llm-mobile`** — Web UI for server control, chat, benchmarking, and ComfyUI gateway (Port `8000`).
4. **`comfyUI`** — Image generation container (Port `8188`) integrated via `llm-mobile`.

The primary artifact is [`docker-compose.yml`](docker-compose.yml). Everything else (`source-kmic-68/`, `source-thetom/`, `models/`, `compose-backup/`, `script/`) is supporting material.

**Runtime builds (two forks):**
- **Primary — Kmic-68 P100 fork** (`source-kmic-68/` @ `p100-optimizations`, `83a7f0839`): P100/sm_60-tuned CUDA kernels, built **sm_60-only**. No TurboQuant; use `q4_0` KV. Router mode and MTP are supported. A/B on Swift-1.5-27B @ 64k: ~2.1x prefill and ~1.6x decode vs TheTom. The build patch disables the fused GDN path for `qwen35moe` (it faults on sm_60); other architectures keep the tuned path.
- **Secondary — TheTom fork** (`source-thetom/` @ `feature/turboquant-kv-cache`, `643956891`): TurboQuant KV (`turbo4/3/2`), MTP, router mode, per-preset GPU split. Kept for the 1060 and as the primary rollback.

---

## Repository Layout at a Glance

```
llmaCPP/
├── docker-compose.yml        # ← PRIMARY FILE. Edit this to change the running config.
├── models/
│   ├── models.ini            # Primary (Kmic) presets: q4_0 KV, no turbo
│   ├── modelg.ini            # Secondary (TheTom) presets: turbo4/turbo2 KV
│   └── *.gguf                # Binary model weights (git-ignored)
├── source-kmic-68/           # Kmic-68 P100 fork build source (git-ignored) — primary image
├── source-thetom/            # TheTom fork build source (git-ignored) — mini image / rollback
├── script/                   # build-kmic.sh, build-thetom.sh
├── llm_bench.db              # SQLite benchmark data (persisted via volume)
└── compose-backup/           # Archived compose configs, DO NOT delete, useful for reference
```

---

## Key Rules for Agents

### 1. `docker-compose.yml` is the source of truth
- All changes to container configs, runtime parameters, ports, or volumes happen **only** in `docker-compose.yml`.
- Do **not** hand-edit files inside `source-kmic-68/` or `source-thetom/`. Both are git-ignored build sources. The only sanctioned source edits are the `<algorithm>` include and the fused-GDN `qwen35moe` guard that `script/build-kmic.sh` applies to `source-kmic-68/src/llama-context.cpp`; everything else belongs in the INI or compose file.

### 2. Models directory is git-ignored
- `models/` contains large binary GGUF files. Never suggest committing them.
- When referencing model paths, always use `/models/<filename>.gguf` (as mounted inside the container).

### 3. Two llama-server instances
The stack runs **two** independent `llama-server` containers:

| Service | Container Name | Host Port | GPU | Image | INI Config | Role |
|---|---|---|---|---|---|---|
| `llama-server` | `llm-server` | 8080 | GPU 0 (Tesla P100) | `llama-server:kmic-p100-nov6` | `models.ini` (q4_0) | Primary inference |
| `llama-server-mini` | `llm-server-mini` | 8081 | GPU 1 (GTX 1060) | `llama-server:thetom-nov8` | `modelg.ini` (turbo) | Secondary inference |

Both share the `/models` volume. Each has its own `command:` section and model preset file.

### 4. llama-server command-line flags
Server-level flags live in the `command:` key; model-level flags (cache types, draft settings) live in the INI. Common flags:

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
| `--cache-type-k / --cache-type-v` | KV cache quantization. Kmic: `q4_0`, `q8_0`, `f16`. TheTom adds `turbo4/3/2/5/6` |
| `--ubatch-size <n>` | Physical micro-batch size |
| `--threads <n>` | CPU threads |
| `--load-mode mlock` | Load + lock model in RAM/VRAM (replaces deprecated `--no-mmap` + `--mlock`) |
| `--device <dev1,dev2,..>` | Comma-separated devices for offloading (e.g. `CUDA0,CUDA1`); override per preset in the INI |
| `--split-mode {none,layer,row,tensor}` | Layer/row/tensor split across multi-GPU (`none` = single GPU) |
| `--tensor-split N0,N1,N2` | Fraction of model per GPU (e.g. `5,1` for a ~5:1 split) |
| `--main-gpu INDEX` | Primary GPU for intermediates/KV (default `0`) |
| `--repeat-penalty <f>` | Repetition penalty |
| `-np <n>` | Number of parallel slots (concurrent requests) |
| `--spec-type draft-mtp` | Speculative decoding with a built-in or sidecar MTP head (`draft-dflash` also supported) |
| `--spec-draft-model / -md` | Sidecar draft/MTP/dflash model path |
| `--spec-draft-ngl / --spec-draft-ubatch-size` | Draft context GPU layers / ubatch |
| `--spec-draft-type-k / --spec-draft-type-v` | Draft context KV types |
| `--fit on` | Auto-adjust unset args to fit VRAM (Kmic default: on) |
| `--models-max <n>` | Router: max simultaneously loaded models |

`llama-server-mini` uses identical flags but targets GPU 1 via `device_ids: ['1']` in the `deploy.resources` section.

### Multi-GPU split (primary only, per-preset)
- The primary exposes both GPUs (`device_ids: ['0', '1']`). Whether a model splits is decided **per preset in `models.ini`**, not in the compose `command:`.
- Current `models.ini` `[*]` sets `device = CUDA0`, `split-mode = none`, so every preset runs on the P100 alone. Swift-1.5-27B at 64k with q4_0 KV fits (~14.1 GiB).
- To split, override in that preset: `device = CUDA0,CUDA1`, `split-mode = layer` (or `tensor`), `tensor-split = 5,1`, `main-gpu = 0`.
- **Gotcha:** CLI command args BEAT INI preset values. Only the INI `[*]` section is overridable per-model — put multi-GPU defaults in `[*]`, never set `--device`/`--split-mode` in the compose `command:`.
- The Kmic image is sm_60-tuned. Splitting onto the sm_61 1060 works (minor-version binary compatibility) but is not tuned; keep the mini on TheTom.
- Coexistence rule: primary single-GPU + mini E4B on the 1060 works; a primary 27B split (≈4.8 GiB on the 1060) + mini conflict on the 6 GB card — keep the mini idle for 27B sessions.

### 5. KV cache type guidance
The primary (Kmic) build has **no TurboQuant**. Its cache types are `f32`, `f16`, `bf16`, `q8_0`, `q4_0`, `q4_1`, `iq4_nl`, `q5_0`, `q5_1`; use `q4_0` for both K and V (the fork's tuned config). `turbo*` exists only in the TheTom image (mini/rollback).

| Type | Approx compression | Notes |
|---|---|---|
| `q4_0` | ~4-bit | Primary default; fastest tuned path on the P100 |
| `q8_0` | ~8-bit | Better quality, more VRAM; Kmic also compiles FA for it |
| `f16` | 16-bit | No compression, highest quality |
| `turbo4` | ~4-bit | TheTom only |
| `turbo3` | ~3-bit | TheTom only |
| `turbo2` | ~2-bit | TheTom only, aggressive |

### 6. GPU device allocation
- **`llama-server`** exposes `device_ids: ['0','1']` → Tesla P100 (16 GB) + GTX 1060 (6 GB). It runs the sm_60 Kmic image; current presets stay on the P100.
- **`llama-server-mini`** uses `device_ids: ['1']` → GTX 1060 (6 GB), TheTom image.
- Always verify VRAM budget fits the model + KV cache before changing parameters. The 1060 is the tight resource: it hosts the mini's E4B (≈5.5 GiB) *or* a primary 27B split (≈4.8 GiB), not both.
- The Kmic image must be built with `CUDA_DOCKER_ARCH=60` only; adding `61` silently disables the P100 tuning (`__CUDA_ARCH_LIST__ == 600`).

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

### Primary Server (Kmic / P100)
1. Copy current `docker-compose.yml` to `compose-backup/docker-compose-<description>.yml`
2. Edit `models/models.ini` (use `q4_0` KV; `turbo*` is invalid on the Kmic image)
3. Use the llm-mobile UI to reload the INI and load the new model
4. Rebuild with `./script/build-kmic.sh --deploy` if the source image changed

### Secondary Server (TheTom / 1060)
1. Edit `models/modelg.ini` (turbo KV is available here)
2. Use the llm-mobile UI to reload the INI and load the new model on the secondary GPU
3. Rebuild with `./script/build-thetom.sh` if the source image changed

To change server-level parameters (threads, slots, etc.), edit the `command:` section of the respective service in `docker-compose.yml`. Cache types and other model-level flags belong in the INI. Then restart:
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
- [ ] If a model should split across both GPUs, set `device`/`split-mode`/`tensor-split` in the matching INI preset (defaults live in `[*]`), not in the compose `command:`
- [ ] Context size is within GPU memory budget (larger ctx = more VRAM cache)
- [ ] `LLM_PROJECT_NAME` in `llm-mobile` matches the Compose project name used when deploying
- [ ] If adding a new GPU-heavy service, verify `device_ids` doesn't conflict with existing allocations
- [ ] Primary uses the Kmic image with `q4_0` KV; `turbo*` is invalid there
- [ ] `qwen35moe` models need the fused-GDN guard (applied by `script/build-kmic.sh`); without it they fault in `ggml_cuda_op_gated_delta_net_fused_cache` on sm_60
- [ ] Primary image builds with `CUDA_DOCKER_ARCH=60` only (sm_60)
- [ ] `source-kmic-68/` and `source-thetom/` are build sources — only the documented `script/build-*.sh` patches are allowed

---

## Do Not Touch

| Path | Reason |
|---|---|
| `source-kmic-68/` | Kmic-68 P100 fork clone the primary image is built from (git-ignored, rebuilt via Docker) |
| `source-thetom/` | TheTom fork clone the mini image is built from (git-ignored, rebuilt via Docker) |
| `models/*.gguf` | Binary model weights, git-ignored |
| `.git/` | Version control internals |
