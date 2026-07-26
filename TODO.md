# TODO — TurboQuant merge & fixes

## Current Status (2026-07-26)

- **Source branch**: `turboquant-merged-2026-07-26` at `7ff9cc75e`
  - Merged `atomic/feature/turboquant-kv-cache` (137 commits)
  - Cherry-picked DFlash KV rotation + DeepSeek V4 fused HC ops
  - **Fixed**: Restored 270+ lines of TurboQuant code lost in merge (type_traits, ggml_turbo_wht, CPU backend)
- **Docker image**: `llama-server:latest` built with `--no-cache` (image `3a1582c21978`)
- **Compose stack**: Running with new image, both containers healthy
- **Parent repo**: Pushed to GitHub (`91f4bfb`)

## Remaining Work

### 1. Fix model stuck in "loading" state (HIGH PRIORITY)

The router child process spawns and starts, but the model stays stuck at "loading" and never transitions to "loaded". The child health-check endpoint responds (HTTP 200), but the parent never detects it as ready.

**Observation**: Child starts with `--cache-type-k turbo4 --cache-type-v turbo2` (from INI `[*]` defaults). Child process is alive (`ps aux` shows it), health endpoint responds on its internal port, but the router parent never receives the ready signal.

**Possible causes**:
- `is_router_server` is `true` for the child (since `params.model.path` is empty) — causes both parent and child to enter the router code path
- The child's `ctx_server.load_model(params)` may be failing silently
- Model loading may be blocking on GPU allocation with `--cache-type-k turbo4` in child mode
- The `LLAMA_APP_CMD` env var causing the child to run different binary dispatcher

**Debug**:
```bash
# Check child's full logs by looking at its stdout
docker exec llm-server sh -c 'cat /proc/91/fd/1 2>/dev/null | head -50'

# Or check if the child process is actually loading the model (watch GPU)
watch -n 1 nvidia-smi
```

**Potential fix**: Add `--model /models/Qwen3-4B-Instruct-2507-Q8_0.gguf` explicitly to the child args, or investigate why `LLAMA_APP_CMD` changes the binary dispatch.

**Test**:
```bash
# Check model status
curl -s http://localhost:8080/models | python3 -c "import sys,json; [print(f\"{m['id']}: {m['status'].get('value','?')}\") for m in json.load(sys.stdin)['data'] if m['status'].get('value','unloaded') != 'unloaded']"

# Try loading via direct model endpoint
curl -s -X POST http://localhost:8080/models/load -H 'Content-Type: application/json' -d '{"model":"Qwen3-4B-Instruct-2507-Q8_0.gguf"}'
```

### 2. DSV4_HC_COMB runtime error in direct (non-router) mode (MEDIUM)

When running with `--cache-type-k turbo4 --cache-type-v turbo2` and `--model`, the server hits:
```
ggml_get_n_tasks: op not implemented: DSV4_HC_COMB
```

**Root cause**: `cparams.fused_dsv4_hc_*` flags default to `true` in `llama-context.cpp:257-259`. For non-DeepSeek models (e.g. Qwen3), the probe doesn't detect DSV4 HC nodes, so flags stay `true`, and graph building incorrectly inserts DSV4_HC_COMB ops.

**Does NOT affect router mode** (child process uses `--models-preset` path which may bypass the default).

**Fix options**:
- Add `GGML_OP_DSV4_HC_COMB`/`DSV4_HC_PRE`/`DSV4_HC_POST` to `ggml_get_n_tasks` switch (check if Phase 3 cherry-pick actually placed them correctly)
- Or: Gate `fused_dsv4_hc_` flags behind a model architecture check
- Or: Default to `false` and only enable for known DeepSeek architectures

### 3. Fix `[*]` default `ubatch-size = 2048` causing OOM on P100 (LOW)

Currently `ubatch-size = 2048` in INI `[*]` defaults. The P100 (16GB) OOMs with Qwen3-4B at ctx-size 65536. Per-model overrides set `ubatch-size = 512`, but `[*]` should be a safe default:

- Change `[*]` default from `2048` → `512`
- Add per-model overrides only where higher ubatch is beneficial

### 4. Commits & pushes (MEDIUM)

- [x] Source changes committed at `7ff9cc75e`
- [x] Parent repo pushed (`91f4bfb`)
- [ ] Push source branch to origin (if remote is configured):
  ```bash
  cd /home/nui/llmaCPP/source && git push origin turboquant-merged-2026-07-26
  ```

### 5. Verify webapp model switching (MEDIUM)

After fixing #1:
- [ ] Test `POST /api/llm/models/load` from webapp
- [ ] Test `POST /api/llm/models/unload`
- [ ] Test `POST /api/chat/completions` through router
- [ ] Test secondary server (mini/modelg.ini)
- [ ] Test INI reload via webapp

### 6. Update `update.md` (LOW)

- [ ] Document the stuck-at-"loading" fix (once identified)
- [ ] Document DSV4_HC_COMB fix (once identified)

## Merge Checklist for Future

Always run after any merge:

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

# 6. Build and check symbols
docker run --rm --entrypoint sh llama-server:latest \
  -c 'nm -D /app/libggml-base.so.0.16.0 2>/dev/null | grep ggml_turbo_wht'

# 7. Quick smoke test
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

Always use `--no-cache` for Docker builds after merge fixes, or `touch` changed files before build to trigger recompilation:

```bash
touch ggml/src/ggml.c ggml/src/ggml-cpu/ggml-cpu.c ggml/src/ggml-cpu/ops.cpp
```
