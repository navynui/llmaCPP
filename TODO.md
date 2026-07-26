# TODO — TurboQuant merge & fixes

## Current Status (2026-07-26)

- **Source branch**: `turboquant-merged-2026-07-26` at `7ff9cc75e`
  - Merged `atomic/feature/turboquant-kv-cache` (137 commits)
  - Cherry-picked DFlash KV rotation + DeepSeek V4 fused HC ops
  - **Fixed**: Restored 270+ lines of TurboQuant code lost in merge (type_traits, ggml_turbo_wht, CPU backend)
- **Docker image**: `llama-server:latest` built with `--no-cache` (image `3a1582c21978`)
- **Compose stack**: Running with new image, all containers healthy
- **Parent repo**: Pushed to GitHub (`98bdd01`)
- **Models**: Both servers loading, inferencing, webapp switching works

## Fixed Items

### ✅ Model stuck in "loading" state

**Root cause**: Each `models.ini` / `modelg.ini` section had lost its `model = /models/...` key. The section name alone (e.g. `[Qwen3-4B-Instruct-2507-Q8_0.gguf]`) is NOT automatically mapped to `LLAMA_ARG_MODEL`. The preset system requires an explicit `model = /path/to/model.gguf` key-value pair.

This happened because:
1. The INI backups show that every section originally had `model =` pointing to the GGUF file
2. During INI cleanup, the `model` key was removed because the section header already contained the filename — but the INI parser doesn't use the section name as a model path
3. Children spawned without `--model` started in router mode with 0 models → deadlock with parent

**Fix**: Added `model = /models/...` to every section in both `models.ini` and `modelg.ini`.

### ✅ `[*]` default `ubatch-size = 2048` causing OOM on P100

Changed from `2048` → `512` in the `[*]` defaults. Per-model overrides are kept where higher ubatch is beneficial.

### ✅ SIGSEGV on model load with turbo4/turbo2 cache types

Fixed by restoring 270+ lines of TurboQuant code lost in merge. See `update.md` for full details.

## Remaining Work

### 1. DSV4_HC_COMB runtime error in direct mode (MEDIUM)

When running with `--cache-type-k turbo4 --cache-type-v turbo2` AND `--model` (non-router mode), the server hits:
```
ggml_get_n_tasks: op not implemented: DSV4_HC_COMB
```

**Root cause**: `cparams.fused_dsv4_hc_*` flags default to `true` in `llama-context.cpp:257-259`. For non-DeepSeek models (e.g. Qwen3), the probe doesn't detect DSV4 HC nodes, so flags stay `true`, and graph building incorrectly inserts DSV4_HC_COMB ops.

**Does NOT affect router mode** — child processes use `--models-preset` path which bypasses the default flags.

**Fix options**:
- [ ] Gate `fused_dsv4_hc_*` flags behind model architecture check
- [ ] Or: Default to `false` and only enable for known DeepSeek architectures
- [ ] Or: Verify `GGML_OP_DSV4_HC_COMB`/`DSV4_HC_PRE`/`DSV4_HC_POST` are properly registered in `ggml_get_n_tasks`

### 2. Verify agents-a1 + mmproj (LOW)

- [ ] Test loading agents-a1 with mmproj
- [ ] Verify gemma-4 models load correctly with their mmproj files
- [ ] Test with images

### 3. Update `update.md` (LOW)

- [ ] Document the `model =` key fix in the INI files
- [ ] Document ubatch-size reduction

## Merge Checklist for Future

Always run after any merge into the TurboQuant fork:

```bash
# 1. Check type_traits[] has TURBO entries (indices 42-46 in ggml.c)
grep -n 'TURBO3_0\|TURBO4_0\|TURBO2_0' ggml/src/ggml.c

# 2. Check ggml_turbo_wht() function exists
grep -n '^struct ggml_tensor \* ggml_turbo_wht' ggml/src/ggml.c

# 3. Check "TURBO_WHT" in op name array
grep -n '"TURBO_WHT"' ggml/src/ggml.c

# 4. Check ggml_compute_forward_turbo_wht in CPU backend
grep -n 'ggml_compute_forward_turbo_wht' ggml/src/ggml-cpu/ggml-cpu.c
grep -n 'GGML_OP_TURBO_WHT' ggml/src/ggml-cpu/ggml-cpu.c

# 5. Check ggml_compute_forward_turbo_wht in ops.cpp
grep -n 'void ggml_compute_forward_turbo_wht' ggml/src/ggml-cpu/ops.cpp

# 6. Check INI files have `model = /models/...` in every section
grep -c '^model = ' models/models.ini
grep -c '^model = ' models/modelg.ini

# 7. Build and check symbols
docker run --rm --entrypoint sh llama-server:latest \
  -c 'nm -D /app/libggml-base.so.0.16.0 2>/dev/null | grep ggml_turbo_wht'

# 8. Quick smoke test
docker run --rm --gpus all --entrypoint /app/llama-server \
  -v /home/nui/llmaCPP/models:/models \
  llama-server:latest \
  --host 0.0.0.0 --port 8099 --no-mmap --no-warmup \
  --model /models/Qwen3-4B-Instruct-2507-Q8_0.gguf \
  --n-gpu-layers -1 --cache-type-k turbo4 --cache-type-v turbo2 \
  --ubatch-size 512 --ctx-size 2048 &
sleep 20
curl -s -o /dev/null -w "%{http_code}" http://localhost:8099/health
kill %1 2>/dev/null
```

Always use `--no-cache` for Docker builds after merge fixes, or `touch` changed files before build:

```bash
touch ggml/src/ggml.c ggml/src/ggml-cpu/ggml-cpu.c ggml/src/ggml-cpu/ops.cpp
```
