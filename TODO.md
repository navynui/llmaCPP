# TODO — Current State & Lessons Learned

## Current Status (2026-07-26, after fix)

- **Source branch**: `turboquant-merged-2026-07-06` (July 6 baseline, TurboQuant fork)
- **Docker image**: `llama-server:july6-fixed` → tagged as `latest`
- **Fix applied**: Missing `}` in `ggml/src/ggml-cuda/fattn.cu` at the end of
  `ggml_cuda_flash_attn_ext_mma_f16_switch_ncols2` — a merge artifact where a
  duplicated `if constexpr (DKQ <= 256)` block was missing its closing brace.
  The correct single `if constexpr (DKQ <= 256) ... else` block was restored
  from the July 26 source.
- **Build**: Compiles with CUDA 12.8.1 + gcc-14, `CUDA_DOCKER_ARCH="60;61"`
- **Both servers**: Running healthy, all models at **ctx=65536**

### VRAM Usage (Tesla P100 16GB) at ctx=65536

| Model | VRAM | Free | Status |
|---|---|---|---|
| Gemma 4 E4B (Q4_K_XL + MTP) | 5,453 MiB | 10,931 MiB | ✅ Ample |
| Gemma 4 12B (Q4_K_XL + MTP) | 8,761 MiB | 7,623 MiB | ✅ Comfortable |
| agents-a1 (IQ4_XS + graft) | 15,395 MiB | 989 MiB | ✅ Tight |
| Gemma 4 26B (Q4_K_XL + MTP) | 15,695 MiB | 689 MiB | ✅ Very tight |

All models fit at ctx=65536 on P100 with TurboQuant KV cache (turbo4/turbo2).
The 26B is extremely tight (689 MiB headroom) — avoid running other GPU workloads
concurrently.

### GTX 1060 (6GB) — Secondary Server
- E4B loaded: 4,829 MiB / 6,144 MiB (~1.3 GB free)
- Only lightweight models (E4B, Qwen3-4B, E2B) should be loaded here

## What Was Fixed

### fattn.cu merge artifact
Source: `turboquant-merged-2026-07-06` branch, file `ggml/src/ggml-cuda/fattn.cu`

During the July 6 merge of upstream into TurboQuant, the function
`ggml_cuda_flash_attn_ext_mma_f16_switch_ncols2` got a duplicated
`if constexpr (DKQ <= 256)` block where a single `if/else` was intended.
The first `if constexpr` was missing its closing `}`, causing the template
function to never close. nvcc then parsed the next function
(`ggml_cuda_flash_attn_ext_mma_f16`) as part of the template body,
producing 29 cascading errors.

**Fix**: Replaced the broken double-block with the correct single
`if constexpr (DKQ <= 256) { ... } else { ... }` from the July 26 source.

### ubatch-size = 2048 → 512
Both `models.ini` and `modelg.ini` had `[*]` default `ubatch-size = 2048` which
causes OOM on P100 at ctx=65536. Changed to 512.

## What Was Confirmed

- ✅ TurboQuant `turbo4`/`turbo2` KV cache types work correctly
- ✅ All 4 models load and serve at ctx=65536
- ✅ MTP speculative decoding works on agents-a1, E4B, 12B, 26B
- ✅ Both servers (P100 + GTX 1060) healthy
- ✅ No zombie CUDA contexts (current VRAM is clean)

## Reminder: Monitor VRAM

Check regularly:
```bash
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
```

If VRAM gets stuck (zombie contexts from killed processes), the server needs
`sudo reboot`. Use graceful shutdown (SIGTERM) or `docker rm -f` instead of
`kill -9`.

## Remaining Notes

- The `compose-backup/docker-compose-turboquant-merged-2026-07-26.yml` contains
  the previous (VRAM-regressed) configuration for reference.
- The `turboquant-merged-2026-07-26` branch in source still exists if we ever
  need to cherry-pick upstream features.
- If upstream finally adopts WHT-based KV cache, we can consider switching back.
