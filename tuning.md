# llmaCPP Tuning Notes

A running record of performance tuning decisions for the llmaCPP stack.
Each section documents the model, the hardware context, the numbers used, and the reasoning.

---

## 2026-08-15 — Qwen3.8-27B-IQ4_XS (primary server, port 8080)

**Goal:** Maximum decode tokens/sec and prompt processing speed for single-user inference with context size 65 536.  
**Files changed:** `models/models.ini`, `docker-compose.yml`  
**Backup:** `compose-backup/docker-compose-qwen38-27b-iq4xs-pre-tensorsplit.yml`

### Hardware snapshot

| Component | Specification |
|---|---|
| **GPU 0** | Tesla P100-PCIE 16 GB (**732 GB/s** HBM2, compute capability 6.0) |
| **GPU 1** | GeForce GTX 1060 6 GB (**192 GB/s** GDDR5, compute capability 6.1) |
| **Interconnect** | PCIe Host Bridge (PHB via CPU root complex) |
| **CPU** | Intel Core i7-9700K @ 3.60 GHz (8 physical cores, 8 threads, no HT) |
| **System RAM** | 32 GB DDR4 (~26 GB free) |

### Model & Draft Assets on Disk

| Asset | File | Size |
|---|---|---|
| Base Model | `Qwen3.8-27B-IQ4_XS.gguf` | **15.0 GB** |
| MTP Draft Head | `mtp-Qwen3.8-27B-Q4_0.gguf` | **1.6 GB** |
| KV Cache (c=65536, turbo4+turbo2) | Allocated on GPU 0 (main-gpu) | **2.16 GB** |

---

## Empirical Benchmark & Tuning Progression

Benchmarked on identical 350-token technical generation prompts (`/no_think`):

| Configuration Phase | Prompt Speed | Decode Speed | Wall Time (350 tok) | Draft Acceptance | Notes |
|---|---|---|---|---|---|
| **Baseline** (`n-max=3`, shared draft dev, no p-min) | 35.74 t/s | 12.52 t/s | 38.95s | 183 / 492 (37.2%) | Draft model shared across PCIe |
| **Phase 1:** + `spec-draft-device = CUDA0` | **38.53 t/s** | 12.52 t/s | 38.23s | 178 / 507 (35.1%) | Prompt speed +7.8%; 0 PCIe draft hops |
| **Phase 2:** + `spec-draft-n-max = 4` | 36.05 t/s | 10.25 t/s | 45.04s | 179 / 675 (26.5%) | ❌ 4th draft token wasted compute |
| **Phase 3:** + `spec-draft-n-max = 2` | 38.49 t/s | 13.29 t/s | 36.56s | 150 / 395 (38.0%) | ✅ Reduced draft latency & overhead |
| **Phase 4:** + `spec-draft-p-min = 0.5` | 38.35 t/s | 14.61 t/s | 34.26s | 152 / 267 (56.9%) | ✅ Pruned low-confidence drafting |
| **Phase 5 (Optimal):** `spec-draft-p-min = 0.6` | **38.56 t/s** | **15.50 t/s** | **32.75s** | **164 / 251 (65.3%)** | 🏆 **+23.8% faster decode, -15.9% wall time** |
| **Phase 6:** + `cache-type-k = turbo3` | 38.53 t/s | 14.74 t/s | 33.93s | 149 / 242 (61.6%) | ❌ turbo4 has faster dequant kernels on sm_60 |

---

## Key Optimizations Explained

### 1. Dedicated Draft Device (`spec-draft-device = CUDA0`)
- **Mechanism:** In MTP speculative decoding, the draft model generates draft tokens sequentially before the base model verifies them in one forward pass.
- **Why it matters:** The system's GPUs communicate over standard CPU PCIe (PHB), which has latency overhead. Placing the entire 1.6 GB draft model on `CUDA0` (Tesla P100) ensures that all iterative draft steps run purely on 732 GB/s HBM2 memory with **zero inter-GPU PCIe hops during drafting**.
- **Bonus:** Frees ~910 MB of VRAM on the GTX 1060, allowing `fit = 1` to distribute base model layers cleanly without VRAM contention.

### 2. Speculative Draft Length & Confidence Gate (`spec-draft-n-max = 2`, `spec-draft-p-min = 0.6`)
- **Mechanism:** Standard speculative decoding blindly drafts $N$ tokens regardless of confidence.
- **Why `n-max = 2` beats `n-max = 3` and `4`:** With $N=4$, acceptance drops to 26.5%, wasting GPU compute drafting tokens that will be thrown away. With $N=2$, draft overhead is halved while maintaining high throughput.
- **Why `spec-draft-p-min = 0.6` is critical:** If the draft model's probability for token 1 or 2 is below 60%, drafting terminates immediately. This cut wasted draft generations from **507 down to 251** while keeping accepted tokens virtually unchanged (164 accepted), driving draft acceptance from **35% up to 65.3%** and boosting decode speed from **12.52 to 15.50 t/s**.

### 3. Layer Split Auto-Allocation (`fit = 1`, `split-mode = layer`, `main-gpu = 0`)
- **Mechanism:** `fit = 1` calculates the layer partition based on available VRAM at runtime.
- **Memory distribution under load:**
  - **Tesla P100 (16 GB):** Holds ~14.9 GB (Base model layers + 2.16 GB KV cache + 1.6 GB draft head).
  - **GTX 1060 (6 GB):** Holds ~4.9 GB (Base model layers). Leaves ~1.2 GB headroom for compute buffers and CUDA context.

### 4. KV Cache Quantization (`cache-type-k = turbo4`, `cache-type-v = turbo2`)
- Preserves full 65 536 context size within a compact **2.16 GB** footprint on the primary GPU.
- Benchmarks confirmed `turbo4` K-cache outperforms `turbo3` on Pascal SM 6.0/6.1 due to optimized 4-bit dequantization routines.

### 5. CPU Thread Allocation (`--threads 8`)
- Uses all 8 physical cores of the i7-9700K (8C/8T, no Hyper-Threading) to minimize host-side draft verification, sampling, and PCIe dispatch latency.

---

## Active Configuration Reference

### `models/models.ini`
```ini
[Qwen3.8-27B-IQ4_XS.gguf]
model = /models/Qwen3.8-27B-IQ4_XS.gguf
md = /models/mtp-Qwen3.8-27B-Q4_0.gguf
spec-type = draft-mtp
spec-draft-device = CUDA0
spec-draft-n-max = 2
spec-draft-p-min = 0.6
cache-type-k = turbo4
cache-type-v = turbo2
fit = 1
device = CUDA0,CUDA1
split-mode = layer
main-gpu = 0
ubatch-size = 512
c = 65536
```

### `docker-compose.yml` (`llama-server` service)
```yaml
    command: >
      --models-preset /models/models.ini
      --host 0.0.0.0
      --port 8080
      -np 1
      --flash-attn on
      --threads 8
      --load-mode mlock
      --repeat-penalty 1.1
      --models-max 1
      --tools all
```
