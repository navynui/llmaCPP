# llmaCPP Source Update Log

## Latest Update — 2026-07-26

Merged the TurboQuant fork (`atomic/feature/turboquant-kv-cache`) onto our
`turboquant-merged-2026-07-06` branch to bring the source fully up to date with
the fork, then cherry-picked upstream DeepSeek V4 fused hyper-connection ops and
DFlash K/V rotation for quantized caches.

**Strategic decision: We are staying with the TurboQuant fork** — upstream has not
adopted TurboQuant and has no WHT-based KV cache compression roadmap. TurboQuant's
3.8x–6.4x KV cache compression is essential for large context on our P100 (16 GB)
and GTX 1060 (6 GB).

### Before / After

| Property | Before | After |
|---|---|---|
| Base commit | `797cf14a2` | `0f8018b2a` |
| Branch | `turboquant-merged-2026-07-06` | `turboquant-merged-2026-07-26` |
| Behind `origin/master` | 246 commits | **114 commits** |
| Ahead of `origin/master` | ~331 commits | **342 commits** |
| Docker image | `llama-server:latest` (7.04 GB) | `llama-server:latest` (7.03 GB) |

### What was merged from the TurboQuant fork (137 commits)

- **TML Inkling** architecture support (new model)
- **Hy3 (hy_v3)** with MTP speculative decoding
- **DeepSeek V4 fixes**: seq_rm fix, cache clear fix, Lightning Indexer support
- **Major CUDA MMQ refactor** — upstream's refactored matrix multiply kernels with
  per-architecture configs (Ampere, Blackwell, CDNA, Pascal, RDNA2, RDNA4)
- **CUDA banded flash attention** (`fattn-banded.*`)
- Server improvements: MCP stdio support, CORS options, router refactoring,
  prompt cache state ownership, structured error propagation
- UI updates: context usage gauge, reasoning effort control, MCP UX improvements
- Many backend improvements: Metal Q2_0, OpenCL int8 DP4A, Vulkan f16 SET_ROWS,
  SYCL flash attention via oneDNN, Hexagon optimizations

### Cherry-picked from upstream (not yet in atomic fork)

| Commit | Feature | Files changed |
|---|---|---|
| `571d0d540` | **DFlash K/V rotation** for quantized KV cache | 1 file, +17 lines |
| `0dc74e332` | **DeepSeek V4 fused hyper-connection ops** (`GGML_OP_DSV4_HC_*`) | 16 files, +1062 lines |

### Router server changes

**Important:** The server now runs in **router mode** (multi-process architecture).
Model-level flags `--cache-type-k`/`--cache-type-v` have been moved from the
`docker-compose.yml` command line into the INI preset files (`models.ini`,
`modelg.ini` `[*]` default section) because the router parent process doesn't
accept them.

If you add new presets, they will inherit:
```ini
[*]
cache-type-k = turbo4
cache-type-v = turbo2
```

### Fixed build issues

- Updated `GGML_OP_COUNT` assertions from 101 → 103 (accommodates TURBO_WHT op +
  DSV4_HC ops)
- Updated `RPC_PROTO_PATCH_VERSION` from 3 → 4
- The CUDA build now limits architectures to `60;61` (P100 + GTX 1060) for faster
  Docker builds

### Files that needed merge conflict resolution

| File | Resolution |
|---|---|
| `src/llama-kv-cache.cpp` | Took atomic version (refactored attn_rot_k for DeepSeek) |
| `src/llama-model-loader.cpp` | Took atomic version (minor formatting) |
| `tests/test-backend-ops.cpp` | Took atomic version (cleaner formatting) |
| `tools/server/server-context.cpp` | Took atomic/upstream version (3-way conflict) |
| `tools/server/server-models.cpp` | Took atomic/upstream version (4 conflicts) |
| `tools/server/server-models.h` | Took atomic/upstream version (CMD macros, error callback) |
| `tools/server/server.cpp` | Took atomic/upstream version (refactored into llama_server()) |
| `ggml/include/ggml-rpc.h` | Updated GGML_OP_COUNT assertion + RPC version |
| `ggml/src/ggml.c` | Updated GGML_OP_COUNT assertion |
| `ggml/src/ggml-cpu/ggml-cpu.c` | Took theirs (DSV4 HC ops registration) |
| `ggml/src/ggml-cpu/ops.cpp` | Took theirs (DSV4 HC CPU implementation) |

---

## How to Do Future Updates

### Quick method (update from TurboQuant fork)

```bash
cd ~/llmaCPP/source
git fetch atomic --tags --force
git checkout turboquant-merged-2026-07-26
git merge atomic/feature/turboquant-kv-cache
# resolve conflicts (server files → take theirs, TQ files → take theirs)
git add .
git commit
cd ~/llmaCPP
docker compose up -d --force-recreate llama-server llama-server-mini
```

### Cherry-pick specific upstream features

```bash
cd ~/llmaCPP/source
# List features NOT in atomic fork
git log --oneline origin/master --not atomic/feature/turboquant-kv-cache
# Cherry-pick a specific commit
git cherry-pick <commit-hash>
# Fix GGML_OP_COUNT if needed, rebuild
docker build --build-arg CUDA_DOCKER_ARCH="60;61" \
  -f .devops/cuda.Dockerfile --target server -t llama-server:latest .
```

### Full method (if far behind)

```bash
cd ~/llmaCPP/source
echo "Current HEAD: $(git rev-parse HEAD)" > .backup_head
git fetch origin --tags --force
git fetch atomic --tags --force
git checkout -b test-merge-$(date +%F) turboquant-merged-2026-07-26
git merge atomic/feature/turboquant-kv-cache
# resolve conflicts, then:
cd ~/llmaCPP
docker build --build-arg CUDA_DOCKER_ARCH="60;61" \
  -f .devops/cuda.Dockerfile --target server -t llama-server:latest .
docker compose up -d --force-recreate llama-server llama-server-mini
```

### Known router-mode flags that crash the parent process

These flags are **model-level only** — they must go in the INI preset, not in
the docker-compose `command:`:

- `--cache-type-k` / `--cache-type-v`
- `--flash-attn` (though it works, prefer INI)

### Performance tip: faster Docker builds

```bash
cd ~/llmaCPP/source
docker build \
  --build-arg CUDA_DOCKER_ARCH="60;61" \
  -f .devops/cuda.Dockerfile \
  --target server \
  -t llama-server:latest .
```

---

## References

| Resource | Path |
|---|---|
| Active branch | `source` → `turboquant-merged-2026-07-26` |
| Old HEAD backup | `source/.backup_head` |
| Compose config | `docker-compose.yml` |
| Backup compose configs | `compose-backup/` |
| Server health | `http://localhost:8080/health` |
| Mini server health | `http://localhost:8081/health` |

## Previous Update — 2026-07-06

Merged upstream `origin/master` into the TurboQuant feature branch to bring the source
from **1,079 commits behind** upstream to **fully caught up** (0 behind).

### Before / After

| Property | Before | After |
|---|---|---|
| Source commit | `b0e900a28` | `797cf14a2` |
| Upstream behind | 1,079 commits | **0 commits** |
| TurboQuant KV cache | ✅ Preserved | ✅ Preserved |
| Docker image | `llama-server:latest` (5.73 GB) | `llama-server:latest` (7.04 GB) |
| Running branch | detached HEAD | `turboquant-merged-2026-07-06` |

### What was merged

- **253 new upstream commits** from `ggml-org/llama.cpp` master (up to `20a04b220`)
- New model architectures: EAGLE-3, DFlash, DeepSeek V4
- CUDA / OpenCL / Vulkan / Metal backend improvements
- Server refactoring (`common_models_handler` replaces the old routing system)
- UI updates, bug fixes, performance optimizations

### What was preserved from TurboQuant

- `TQ1_0` / `TQ2_0` / `TQ3_1S` / `TQ4_1S` weight quantization types
- TurboQuant KV cache compression (`turbo4`, `turbo3`, `turbo2`, `turbo_stable`)
- WHT-rotated low-bit formats and CUDA kernels
- Metal kernel templates for TurboQuant types
- Multi-Token Prediction (MTP) support for Gemma 4
- Qwen 3.x NextN speculative decoding

### Files that needed manual conflict resolution

| File | Resolution |
|---|---|
| `docs/speculative.md` | Kept both TQ MTP/NextN docs + upstream EAGLE-3/DFlash docs |
| `ggml/src/ggml-cuda/fattn.cu` | Kept TQ GQA optimizations; fixed duplicated `if constexpr` brace |
| `ggml/src/ggml-metal/ggml-metal.metal` | Kept both TQ kernel templates + upstream generic |
| `src/llama-kv-cache.cpp` | Combined upstream arch checks with TQ indexer logic |
| `src/llama-model-loader.cpp` | Upstream refactor + TQ type entries |
| `tests/test-backend-ops.cpp` | Kept both TQ tests + upstream tests |
| `tests/test-quantize-fns.cpp` | Added TQ3_1S to upstream format |
| `tools/server/*` | Took upstream version (full compat) |
| `tools/server/server.cpp` | Took upstream version (full compat) |
