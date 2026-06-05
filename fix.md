# Specification: Fix Model Switching and Parsing Deadlocks in `main.py`

## Context & Objective
We are running an AI inference stack using `llama.cpp` server in experimental **multi-model router mode** alongside a custom frontend managed by a Python FastAPI backend (`llm-manager`). The host machine runs a single NVIDIA GPU with 16GB VRAM. 

To prevent out-of-memory errors and server deadlocks, `llama-server` is configured with `--models-max 1`. This forces it to evict the active model before loading a new one. 

Currently, when chatting through the web interface, the system unpredictably switches from our heavy default model (**Qwen3.6-35B**) to a smaller model (**Gemma-4-E4B**), causing a slow, unprompted VRAM eviction and reload cycle. 

You need to refactor the proxy router inside `main.py` to fix an underlying `.ini` configuration parsing bug, prevent file-system blocking operations, and stabilize the chat completion pipeline.

---

## Identified Bugs in Current Code

### 1. The `.ini` Assignment and Fallback Bug
In the current line-parsing logic inside `@app.post("/api/chat/completions")`:
* The keys are cleaned using `k.strip().lower()`, but the code loops through a dictionary map using default `"false"` string fallbacks. 
* If there are whitespaces around operators in `models.ini` (e.g., `load-on-startup = true`), the validation code fails to match the normalized flag.
* When the startup lookup fails, the fallback code runs: `if not default_model and sections_order: default_model = sections_order[0]`.
* Since `sections_order[0]` in our configuration happens to be the Gemma model, the proxy server mistakenly injects Gemma as the target model anytime the frontend payload passes an empty or missing `"model"` key.

### 2. Synchronous File I/O Blocking the Event Loop
The script currently executes `with open(ini_path, "r")` synchronously inside the asynchronous endpoint (`async def proxy_chat_completions`). Under concurrent chat requests, this creates severe disk I/O bottlenecks and freezes the FastAPI event loop.

### 3. Server-Sent Events (SSE) Protocol Mismatch
When streaming, the code proxies raw chunk bytes directly from `httpx.AsyncClient` via `response.aiter_bytes()`. However, inside the `except Exception as e:` block, it switches to yielding an explicit text-formatted SSE data string (`yield f"data: ..."`). This breaks frontend chunk stream parsers when upstream errors occur.

---

## Required Modifications

### Task A: Refactor `.ini` Parsing & Cache the Default Model
1. Move the `models.ini` parsing logic out of the hot path of the request endpoint.
2. Implement a global cache variable (e.g., `CACHED_DEFAULT_MODEL`) so the file system is only read once on startup or when the cache is cleared.
3. Fix the string cleaning/matching logic so that variations in spacing around `=` inside `models.ini` (e.g., `load-on-startup=true` vs `load-on-startup = true`) evaluate to a proper boolean value.
4. If a model explicitly defines `load-on-startup = true`, it must be prioritized as the `default_model`.

### Task B: Secure Chat Model Lock
1. Ensure that if the incoming request body does not contain a valid, non-empty `"model"` key, the system seamlessly injects the parsed `load-on-startup` model (Qwen) instead of defaulting blindly to index `0` of the config file.
2. Normalize the model string lookup to match the bracketed alias keys inside `models.ini`.

### Task C: Standardize Async Stream Processing
1. Retain the `StreamingResponse` using an `AsyncClient` loop.
2. Ensure that error handling matches the raw byte format expected by the frontend parser rather than injecting inconsistent `data:` SSE prose mid-stream.
3. Increase or lift the connection timeouts inside `httpx.Timeout` to prevent early drop-offs when loading heavy Mixture-of-Experts (MoE) layers into VRAM.

---

## Target Code Layout Reference

Implement the revised endpoint using this structured approach:

```python
import json
import os
import re
import httpx
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse

app = FastAPI()

# Global cache to protect disk I/O
CACHED_DEFAULT_MODEL = None

def get_fallback_model_from_ini() -> str:
    global CACHED_DEFAULT_MODEL
    if CACHED_DEFAULT_MODEL:
        return CACHED_DEFAULT_MODEL

    ini_path = "/models/models.ini"
    # Hardcoded fail-safe string matching our primary MoE profile
    fallback_anchor = "Qwen3.6-35B-A3B-UD-IQ3_S.gguf" 
    
    if not os.path.exists(ini_path):
        return fallback_anchor

    try:
        with open(ini_path, "r", encoding="utf-8") as f:
            raw_ini = f.read()

        sections_order = []
        sec_startup = {}
        cur_sec = None

        for line in raw_ini.splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith((";", "#")):
                continue

            m = re.match(r'^\[(.+)\]$', stripped)
            if m:
                cur_sec = m.group(1).strip()
                if cur_sec != "*":
                    sections_order.append(cur_sec)
                    sec_startup[cur_sec] = False
            elif "=" in stripped and cur_sec and cur_sec != "*":
                k, _, v = stripped.partition("=")
                if k.strip().lower() == "load-on-startup":
                    sec_startup[cur_sec] = v.strip().lower() in ("true", "1", "yes")

        # Prioritize the true startup model
        for sec in sections_order:
            if sec_startup.get(sec) is True:
                CACHED_DEFAULT_MODEL = sec
                return CACHED_DEFAULT_MODEL

        if sections_order:
            CACHED_DEFAULT_MODEL = sections_order[0]
            return CACHED_DEFAULT_MODEL

    except Exception:
        pass

    return fallback_anchor


@app.post("/api/chat/completions")
async def proxy_chat_completions(request: Request):
    body = await request.body()
    try:
        data = json.loads(body) if body else {}
    except Exception:
        data = {}

    # Strict check to stop accidental model mutations during chat
    if "model" not in data or not str(data.get("model", "")).strip():
        default_model = get_fallback_model_from_ini()
        data["model"] = default_model
        body = json.dumps(data).encode("utf-8")

    async def stream_response():
        # Infinity timeout allocation tailored for multi-gigabyte VRAM swap procedures
        timeout = httpx.Timeout(None, connect=10.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            try:
                async with client.stream(
                    "POST",
                    "http://llm-server:8080/v1/chat/completions",
                    content=body,
                    headers={"Content-Type": "application/json"},
                ) as response:
                    async for chunk in response.aiter_bytes():
                        yield chunk
            except Exception as e:
                error_payload = {"error": {"message": str(e), "type": "proxy_error"}}
                yield f"{json.dumps(error_payload)}\n".encode('utf-8')

    return StreamingResponse(stream_response(), media_type="text/event-stream")