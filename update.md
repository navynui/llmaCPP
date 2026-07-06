# llmaCPP Source Update Log

## Latest Update — 2026-07-06

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

---

## How to Do Future Updates

### Quick method (if little divergence)

If you're close to `origin/master` (0-50 commits behind), just repeat Option C:

```bash
cd ~/llmaCPP/source
git checkout turboquant-merged-2026-07-06
git fetch origin --tags --force
git merge origin/master
# resolve conflicts, then rebuild
cd ~/llmaCPP
docker compose build llama-server llama-server-mini
docker compose up -d --force-recreate llama-server llama-server-mini
```

### Full method (if far behind again)

If the fork has drifted again, use the same approach as this update:

```bash
cd ~/llmaCPP/source

# 1. Backup current HEAD
echo "Current HEAD: $(git rev-parse HEAD)" > .backup_head

# 2. Fetch everything
git fetch origin --tags --force
git fetch atomic --tags --force

# 3. Create a test branch from the local working branch
git checkout -b test-merge-$(date +%F) turboquant-merged-2026-07-06

# 4. Merge upstream
git merge origin/master

# 5. Fix conflicts (see patterns below)

# 6. Build and deploy
cd ~/llmaCPP
docker compose build llama-server llama-server-mini
docker compose up -d --force-recreate llama-server llama-server-mini
```

### Common conflict patterns

| Area | Typical fix |
|---|---|
| `fattn.cu` / `fattn-*.cuh` | Keep TQ optimization branches, add upstream fallback |
| `llama-kv-cache.cpp` | Combine arch checks, keep TQ indexer condition |
| `llama-model-loader.cpp` | Take upstream refactor, re-add `TQ3_1S`/`TQ4_1S` cases |
| `tests/test-backend-ops.cpp` | Keep both — TQ test cases + upstream test cases |
| `tools/server/*` | Take upstream version (server refactors change API frequently) |
| `docs/speculative.md` | Keep both — TQ MTP/NextN + upstream EAGLE/DFlash |

### Performance tip: faster Docker builds

Limit CUDA architectures to just what your GPUs need (P100 = sm_60, GTX 1060 = sm_61):

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
| Active branch | `source` → `turboquant-merged-2026-07-06` |
| Old HEAD backup | `source/.backup_head` |
| Compose config | `docker-compose.yml` |
| Backup compose configs | `compose-backup/` |
| Server health | `http://localhost:8080/health` |
| Mini server health | `http://localhost:8081/health` |
