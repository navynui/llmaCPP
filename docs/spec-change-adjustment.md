# Hardware Specification Change & Infrastructure Optimization Blueprint
**Target System:** Local AI Acceleration Server (CachyOS / Linux x86_64)
**Intended Reader:** DevOps Agents, System Automation Scripts, LLM Context Engineers
**Source Configurations:** `docker-compose.yml` (llama-server + llm-manager) & ComfyUI compose stack

---

## 1. Context & Hardware Baseline Delta

An infrastructure upgrade has been executed. Automation agents must parse the baseline differences below to dynamically recalculate compute parameters, thread allocations, and memory scheduling strategies.

| Component | Previous Baseline (Biostar TB250 Rig) | Upgraded Specification (Z390 Rig) | Operational Impact |
| :--- | :--- | :--- | :--- |
| **CPU Architecture** | Intel i7-7700 (4 Cores / 8 Threads) | Intel i7-9700K (8 Cores / 8 Threads) | +100% Physical Cores. Complete removal of Hyper-Threading contention. |
| **System Memory** | 24GiB Mixed DDR4 @ Non-XMP | 32GiB Matching Dual-Channel (XMP Enabled) | Increased throughput for memory-mapped models (`ggml`). Higher out-of-memory (OOM) headroom. |
| **GPU Pipeline** | 1x NVIDIA Tesla P100 PCIe 16GB | **Dual GPU Setup:**<br>• GPU 0: Tesla P100 16GB (Pascal)<br>• GPU 1: GTX 1060 6GB (Pascal) | Total VRAM footprint expanded to **22GB**. Peer-to-peer data layout required over split PCIe channels. |

---

## 2. Target State Architecture Map
           +-------------------------------------------------------+
           |              Intel i7-9700K Host CPU                  |
           |       (8 Physical Cores / No Hyper-Threading)         |
           +---------------------------+---------------------------+
                                       |
               +-----------------------+-----------------------+
               | (PCIe 3.0 x8)                                 | (PCIe 3.0 x8)
               v                                               v
 +---------------------------+                   +---------------------------+
 |   NVIDIA Tesla P100       |                   |   NVIDIA GTX 1060         |
 |   16GB VRAM (Primary)     |                   |   6GB VRAM (Secondary)    |
 +-------------+-------------+                   +-------------+-------------+
               |                                               |
               +-----------------------+-----------------------+
                                       |
                                       v
               +-----------------------------------------------+
               |           Total Pooled VRAM: 22GB             |
               |      Unified Runtime Target Engine Cluster    |
               +-----------------------------------------------+

To leverage the hardware upgrade without performance degradation, the following architecture must be maintained:
1. **Unified VRAM Pooling:** Compute pipelines must span across both Pascal-generation cards.
2. **Deterministic Threading:** Math engines must match physical cores (8) while avoiding OS scheduling overhead.
3. **Optimized Multi-Device Scheduling:** High-load diffusion and text-generation tasks must target the Tesla P100 while maintaining background offloading to the secondary GPU.

---

## 3. Automation Rules & Script Adjustments

AI Agents must alter execution variables inside the configuration scopes according to the instructions below.

### Rule 1: Multi-GPU Infrastructure Exposure
* **`docker-compose.yml` (llama-server)**: The legacy configuration restricted visibility with `count: 1`. 
  * *Action:* Change `count: 1` to `count: all` inside the `llama-server` deployment configuration to expose both the P100 and GTX 1060.
* **`llm-manager`**: Ensure `count: 1` is shifted to `count: all` to match capability monitoring needs.

### Rule 2: Optimal Thread Allocation for `llama.cpp`
The Intel i7-9700K possesses 8 physical cores and 8 threads. 
* **Critical Context:** Running compute tasks like GGML tensor math across virtual hyper-threaded threads degrades performance. Because the 9700K has **no** hyper-threading, the engine can safely claim nearly all physical cores without scheduling contention.
* **Action:** Maintain the thread count at `--threads 7` or lower it to `--threads 6`. This pins 6–7 physical cores completely for matrix multiplication, ensuring 1–2 cores remain perfectly uninhibited to coordinate heavy disk I/O, OS background daemons, socket events for `llm-manager`, and the ComfyUI backend processes without stalling the server engine loop.

### Rule 3: Tensor Split Strategy
Because your primary card (Tesla P100) has 16GB VRAM and your secondary card (GTX 1060) has 6GB VRAM, models must be split unevenly across them.
* **Ratio Calculation:** The proportion of memory is roughly 73% (P100) to 27% (GTX 1060).
* **Action:** Inject the tensor-split flag into the `llama-server` command string: `--tensor-split 7,3`.

---

## 4. Specific Container Configuration Directives

Agents must rewrite or patch the target configuration files to match these exact parameter blocks.

### A. Modifications for `docker-compose.yml` (llama-server & llm-manager)
* **VRAM Upgrades Added:** Changed `count: 1` to `count: all`. Added `--tensor-split 7,3`.
* **Note on `--mlock`:** Since your new setup has 32GB RAM and your model target is a heavily-quantized 35B model (`Qwen3.6-35B-A3B-UD-IQ3_S.gguf`), it may exceed available VRAM. Your legacy `--mlock` and `--no-mmap` settings are safely preserved below to enforce memory pinning when the weights spill over into your newly upgraded XMP-speed system memory.

```yaml
services:
  llama-server:
    image: llama-server:latest
    container_name: llm-server
    restart: unless-stopped
    cap_add:
    - IPC_LOCK
    ulimits:
      memlock:
        soft: -1
        hard: -1
    ports:
    - 8080:8080
    volumes:
    - /home/nui/llmaCPP/models:/models
    deploy:
      resources:
        reservations:
          devices:
          - driver: nvidia
            count: all # UPGRADED: Exposes both P100 and GTX 1060 to container
            capabilities:
            - gpu
    command: -m /models/Qwen3.6-35B-A3B-UD-IQ3_S.gguf --host 0.0.0.0 --port 8080 -np
      1 --flash-attn on --n-gpu-layers -1 --ctx-size 65536 --ubatch-size 512 --cache-type-k
      turbo4 --cache-type-v turbo2 --threads 7 --no-mmap --mlock --repeat-penalty
      1.1 --mmproj /models/Qwen3.6-mmproj-F16.gguf --tensor-split 7,3 # UPGRADED: Split ratio 16GB vs 6GB
    healthcheck:
      test:
      - CMD
      - curl
      - -f
      - http://localhost:8080/health
      interval: 10s
      timeout: 5s
      retries: 5

  llm-manager:
    build: /home/nui/dev/llmWEB
    container_name: llm-manager
    restart: unless-stopped
    ports:
    - 8000:8000
    volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - /home/nui/llmaCPP:/llm-server
    - /home/nui/llmaCPP/models:/models
    - /home/nui/.hermes:/mnt/hermes
    - /home/nui/.pi:/mnt/pi:rw
    - /home/nui/.local/share/uv:/home/nui/.local/share/uv:ro
    - /home/nui/dev/ComfyUI/output:/comfyui-output
    - /home/nui/dev/llmWEB/PROMPTS:/app/PROMPTS
    environment:
    - LLM_COMPOSE_DIR=/llm-server
    - LLM_PROJECT_NAME=llmacpp
    - COMFYUI_HOST=host.docker.internal:8188
    extra_hosts:
    - host.docker.internal:host-gateway
    deploy:
      resources:
        reservations:
          devices:
          - driver: nvidia
            count: all # UPGRADED: Allows manager utility monitoring scripts full visibility
            capabilities:
            - gpu
            - utility
    depends_on:
      llama-server:
        condition: service_healthy
