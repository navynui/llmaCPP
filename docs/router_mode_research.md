# llama.cpp Router Mode: Dynamic Model Switching via INI Presets

## Summary

llama.cpp's `llama-server` supports a **router mode** that lets you define multiple models in an `.ini` preset file and switch between them **on-the-fly without restarting the container**. Requests are routed automatically based on the `"model"` field sent by the client.

---

## How It Works (High Level)

1. **INI Preset File** — Lists all available models + their per-model configs (context size, GPU layers, etc.)
2. **`--models-preset <file.ini>` Flag** — Tells llama-server to run in router mode
3. **Automatic Routing** — The server loads the model matching whatever `"model"` name the client requests, unloads it when idle (optional), and swaps on the next request

---

## 1. INI Preset File Format (`models.ini`)

```ini
version = 1

; Global defaults (applied to ALL models unless overridden)
[*]
c = 8192                  ; context size
n-gpu-layers = -1         ; offload all layers to GPU

; ── Pre-existing model on the server ──────────────────────
; If the section name matches a model already known, its settings override globals.
[Qwen3.6-35B-A3B:IQ3_S]
chat-template = chatml
c = 8192
n-gpu-layers = -1

; ── Models that DON'T exist yet (must specify at least model path or HF repo) ────
[Qwen3.5-9B-Uncensored]
model = /models/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf

[Gemma3-12B-QAT]
model = /models/gemma-3-12b-it-qat-Q4_K_M.gguf

[Gemini-MTP-E4B]
model = /models/gemma-4-E4B-it-Q4_K_M.gguf

[Granite-4.1-8B]
model = /models/granite-4.1-8b-Q4_K_M.gguf
c = 32768                 ; smaller model can handle bigger context

; ── Optional: auto-load on startup ────────────────────────
[DeepSeek-R1-Distill]
model = /models/DeepSeek-R1-Distill-Qwen-32B-IQ3_M.gguf
load-on-startup = false   ; don't preload — save VRAM

; ── Optional: stop-timeout (seconds to wait before killing) ─
[Granite-4.1-8B]
stop-timeout = 60         ; wait 60s after last request before unload
```

### Key Preset-Exclusive Flags

| Flag | Type | Description | Default |
|---|---|---|---|
| `load-on-startup` | boolean | Auto-load this model when server starts | false (depends on build) |
| `stop-timeout` | int (seconds) | Seconds to wait after last request before unloading | 10 |

### Precedence Order

1. CLI args passed to `llama-server` (highest — overrides everything)
2. Model-specific sections in the INI file
3. Global section `[*]` (lowest)

---

## 2. How Routing Works

### For POST endpoints (`/v1/chat/completions`, `/infill`, etc.)

The server reads `"model"` from the JSON body:

```json
{
  "model": "Qwen3.6-35B-A3B:IQ3_S",
  "messages": [{"role": "user", "content": "Hello"}]
}
```

If that model isn't loaded, it loads automatically (default). The response uses whatever model was requested — **no restart needed**.

### For GET endpoints (`/props`, `/metrics`)

Uses the `model` query parameter:
```
GET /props?model=Gemini-MTP-E4B
```

---

## 3. API Endpoints for Manual Control

You can explicitly load/unload models via REST calls:

### List available models
```bash
curl http://localhost:8080/models | jq '.data[] | {id, status}'
```

### Manually load a model
```bash
curl -X POST http://localhost:8080/models/load \
  -H "Content-Type: application/json" \
  -d '{"model": "Granite-4.1-8B"}'
```

### Unload a specific model (free VRAM)
```bash
curl -X POST http://http://localhost:8080/models/unload \
  -H "Content-Type: application/json" \
  -d '{"model": "Granite-4.1-8B"}'
```

### Control autoload per-request
Append `?autoload=true` or `?autoload=false` to the model query param on GET endpoints, or set `"autoload": true/false` in the body of POST requests (depending on build).

---

## 4. Docker Compose Changes Required

### Before (current setup — single model)
```yaml
command: -m /models/Qwen3.6-35B-A3B-UD-IQ3_S.gguf --host 0.0.0.0 --port 8080 ...
```

### After (router mode with INI preset)
```yaml
services:
  llama-server:
    image: llama-server:latest
    command: >
      --models-preset /models/models.ini
      --host 0.0.0.0
      --port 8080
      -np 1
      --flash-attn on
      --ctx-size 8192
      --ubatch-size 512
      --cache-type-k turbo4
      --cache-type-v turbo2
      --threads 7
      --no-mmap
      --mlock
      --models-max 4
    volumes:
      - ./models/models.ini:/models/models.ini:ro   # ← mount the INI file
```

### The `models.ini` file (put in `/home/nui/llmaCPP/models/`)
```ini
version = 1

[*]
c = 8192
n-gpu-layers = -1

; Default / always-available model
[Qwen3.6-35B-A3B]
model = /models/Qwen3.6-35B-A3B-UD-IQ3_S.gguf
load-on-startup = true
n-gpu-layers = -1

; Optional extras — only loaded on-demand when requested
[Gemini-MTP-E4B]
model = /models/gemma-4-E4B-it-Q4_K_M.gguf
stop-timeout = 60

[Granite-4.1-8B]
model = /models/granite-4.1-8b-Q4_K_M.gguf
c = 32768
stop-timeout = 120

[Qwen3.5-9B-Uncensored]
model = /models/Qwen3.5-9B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf
stop-timeout = 120

[Gemini-12B-QAT]
model = /models/gemma-3-12b-it-qat-Q4_K_M.gguf
c = 8192
stop-timeout = 60

[DeepSeek-Distill]
model = /models/DeepSeek-R1-Distill-Qwen-32B-IQ3_M.gguf
load-on-startup = false   ; too big to preload on P100!
```

---

## 5. How It Would Work In Practice (Our Case)

### Current situation:
- Only `Qwen3.6-35B-A3B` is loaded → ~8GB VRAM + KV cache
- To switch models, we edit `docker-compose.yml`, then restart the container (~30s downtime)

### With router mode:
1. **One-shot swap** — Just send a new `"model": "Granite-4.1-8B"` to `/v1/chat/completions`
2. The server unloads Qwen and loads Granite (no restart, no downtime)
3. You can even load multiple smaller models simultaneously (`--models-max 4`)

### Important VRAM caveat:
On a P100 with only **16 GB**:
- Only one model can be in memory at a time if it's large (>8 GB). Smaller models (Granite 8B ≈ 5GB) could coexist.
- `stop-timeout` ensures VRAM is reclaimed when a model goes idle.

---

## 6. Current Build Verification

✅ Our installed llama-server (`llama-server:latest`) **supports router mode**:
```
--models-dir PATH          directory containing models for the router server
--models-preset PATH       path to INI file containing model presets
--models-max N             max concurrent loaded models (default 4)
--models-autoload          auto-load on request (default: enabled)
```

⚠️ **But**: our current compose.yml does NOT use `--models-preset`, so we're running in standard single-model mode.

---

## 7. Pros & Cons for Our Use Case

| Aspect | Router Mode | Current Restart Method |
|---|---|---|
| Downtime during swap | ~3-10s (load time) | 30+ seconds |
| Configuration changes | Edit `.ini` → hot reload the container once | Edit compose → restart every model change |
| VRAM efficiency | Auto-unload idle models via `stop-timeout` | Manual — either keep or discard |
| Stability | Marked as "still a bit raw" in upstream docs | Battle-tested, stable |
| Per-model KV cache tuning | Yes (different ctx-size per model) | No (single --ctx-size for all) |

### Recommendation:
For our setup on the P100 (16GB), router mode is **worth trying** because:
- We frequently test models and switch between them
- Smaller models (Granite 8B, Qwen3.5-9B) could coexist with one larger model
- No more editing compose.yml every time we want to benchmark a new weight

The trade-off is that router mode is newer and less battle-tested than single-model mode. We should test it on a non-critical model first before relying on it for our main chat.
