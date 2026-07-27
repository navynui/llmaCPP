# llmaCPP Source Update Log

## Latest Update — 2026-07-26 (rollback to turboquant-merged-2026-07-06)

**Decision:** Rolled back from `turboquant-merged-2026-07-26` to the
`turboquant-merged-2026-07-06` baseline after the July 26 merge introduced a
VRAM memory regression on the P100 (16 GB).

**Problem:** The July 26 merge of 137 TurboQuant fork commits + upstream
cherry-picks increased VRAM usage to the point where only the E4B model fit
at ctx=65536 (all other models OOM'd). The July 6 baseline ran all 4 models
at ctx=65536.

**Root cause of build failure:** The July 6 source failed to compile with CUDA
12.8.1's nvcc due to a merge artifact in `ggml/src/ggml-cuda/fattn.cu` — a
missing closing brace that caused 29 template cascade errors.

**Fix applied (fattn.cu brace merge artifact):**

The function `ggml_cuda_flash_attn_ext_mma_f16_switch_ncols2` had a
duplicated `if constexpr (DKQ <= 256)` block where a single `if/else` was
intended. The first `if constexpr` was missing its closing `}`, causing the
function body to never close.

Broken (July 6 source):
```cpp
    if constexpr (DKQ <= 256) {
        if (use_gqa_opt && gqa_ratio > 1) {
            ggml_cuda_flash_attn_ext_mma_f16_switch_ncols1<DKQ, DV, 2>(ctx, dst);
            return;
        }

    if constexpr (DKQ <= 256) {   // ← BUG: missing '}' before this
        ggml_cuda_flash_attn_ext_mma_f16_switch_ncols1<DKQ, DV, 1>(ctx, dst);
    } else {
        GGML_ABORT("fatal error");
    }
}  // ← closes outer if but function body stays open
```

Fixed (restored from July 26 source):
```cpp
    if constexpr (DKQ <= 256) {
        if (use_gqa_opt && gqa_ratio > 1) {
            ggml_cuda_flash_attn_ext_mma_f16_switch_ncols1<DKQ, DV, 2>(ctx, dst);
            return;
        }

        ggml_cuda_flash_attn_ext_mma_f16_switch_ncols1<DKQ, DV, 1>(ctx, dst);
    } else {
        GGML_ABORT("fatal error");
    }
}  // ← closes function body
```

**Build:** Compiled successfully with CUDA 12.8.1 + gcc-14, `CUDA_DOCKER_ARCH="60;61"`
(P100 + GTX 1060). Image: `llama-server:july6-fixed` (7.04 GB), tagged as `latest`.

**Also fixed: `ubatch-size = 2048` → `512`**

Both `models.ini` and `modelg.ini` had `[*]` default `ubatch-size = 2048` which
causes OOM on P100 at ctx=65536. Reduced to 512.

### VRAM at ctx=65536 with TurboQuant (turbo4/turbo2)

| Model | VRAM (P100) | Headroom |
|---|---|---|
| Gemma 4 E4B (Q4_K_XL + MTP) | 5,453 MiB | 10,931 MiB ✅ |
| Gemma 4 12B (Q4_K_XL + MTP) | 8,761 MiB | 7,623 MiB ✅ |
| agents-a1 (IQ4_XS + graft) | 15,395 MiB | 989 MiB ✅ |
| Gemma 4 26B (Q4_K_XL + MTP) | 15,695 MiB | 689 MiB ⚠️ |

All 4 models fit at ctx=65536. The 26B is very tight — avoid concurrent GPU workloads.

### Checklist for future source edits

After any merge or source change, always verify:

```bash
# Check brace balance in fattn.cu
cd ~/llmaCPP/source
awk 'NR>=38 && NR<118' ggml/src/ggml-cuda/fattn.cu | grep -o '{' | wc -l
awk 'NR>=38 && NR<118' ggml/src/ggml-cuda/fattn.cu | grep -o '}' | wc -l
# Expected: equal counts (should be 18 each for the switch_ncols2 function)

# Verify template function is properly closed
# If the function at line 118 is OUTSIDE the template at line 37,
# everything is fine. If nvcc shows 'closing brace of template definition not found',
# there's a missing brace.
```

### Rebuild after source fix

```bash
cd ~/llmaCPP/source
docker build \
  --build-arg CUDA_DOCKER_ARCH="60;61" \
  -f .devops/cuda.Dockerfile \
  --target server \
  -t llama-server:latest .

docker compose up -d --force-recreate llama-server llama-server-mini
```

**Docker build cache trap:** Use `--no-cache` or `touch` changed files before
building, because Docker `COPY` preserves timestamps and cmake may skip
recompilation.

### How VRAM regression was diagnosed

1. Built July 6 source → measured VRAM per model at ctx=65536
2. Built July 26 source → measured same models, same ctx
3. Difference: July 26 used ~1.5-4 GB more per model
4. Suspect commits in the 137-commit merge:
   - `f5525f7e7` — fix draft model fit vs load inconsistency
   - `74976e1ae` — CUDA remove -sm row, refactor cuBLAS
   - `6eddde06a` — CUDA refactor MMQ kernel configuration
   - `bf2c86ddc` — refactor prompt cache state ownership

No single commit was identified as the sole cause; the regression appears to
be cumulative across the refactored CUDA MMQ and KV cache changes.

### Active branch

The source is checked out at `turboquant-merged-2026-07-06` (commit `797cf14a2`).
The `turboquant-merged-2026-07-26` branch is preserved but not deployed.
If we ever need upstream features from that branch, cherry-pick individual
commits rather than merging the entire branch.

---

## Previous Update — 2026-07-26 (reverted due to VRAM regression)

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

### Fixed model stuck in "loading" state — missing `model =` in INI sections

**Root cause:** When the INI files were rewritten during the merge, the
`model = /models/<filename>.gguf` key was removed from every section. Without
an explicit `model` key, the preset system never sets `LLAMA_ARG_MODEL`, so
child processes are spawned without `--model`. The child then starts in router
mode (with 0 available models), creating a deadlock:
- Parent waits for child to load the model
- Child waits for parent to send the model

**The section header `[Qwen3-4B-Instruct-2507-Q8_0.gguf]` is NOT automatically
mapped to `LLAMA_ARG_MODEL`.** The INI parser only maps key-value pairs to CLI
arguments; the section name is just a preset name.

**Fix:** Added `model = /models/...` to every section in both `models.ini` and
`modelg.ini`.

**Checklist for future INI edits:**
```bash
# Verify every section has a model key
grep -c '^\\[.*\\]$' models/models.ini  # count sections
grep -c '^model = ' models/models.ini   # should match section count
grep -c '^model = ' models/modelg.ini   # should match section count
```

### Fixed `[*]` default `ubatch-size = 2048` causing OOM on P100

The `[*]` defaults had `ubatch-size = 2048`, which causes OOM on the P100
(16 GB) with Qwen3-4B at ctx-size 65536. Changed to `ubatch-size = 512` in
the defaults, with per-model overrides where higher throughput is beneficial.

### Fixed build issues

- Updated `GGML_OP_COUNT` assertions from 101 → 103 (accommodates TURBO_WHT op +
  DSV4_HC ops)
- Updated `RPC_PROTO_PATCH_VERSION` from 3 → 4
- The CUDA build now limits architectures to `60;61` (P100 + GTX 1060) for faster
  Docker builds

### CRITICAL: TurboQuant type traits lost in merge — root cause of SIGSEGV

**The problem:** When merging upstream commits into our TurboQuant fork, several
TurboQuant-critical code sections were silently lost because upstream doesn't
have any TURBO type references. The merge tool (git) didn't flag conflicts — it
just took upstream's version where TURBO entries were absent.

**What was lost (270+ lines across 3 files):**

| File | Lost content | Symptom if missing |
|---|---|---|
| `ggml/src/ggml.c` | `type_traits[]` entries for `GGML_TYPE_TURBO2_0`, `TURBO3_0`, `TURBO4_0`, `TQ3_1S`, `TQ4_1S` (indices 42–46) | SIGSEGV on any model load with `--cache-type-k turbo4` (null pointer in `ggml_type_name()` → type_traits out of bounds) |
| `ggml/src/ggml.c` | `ggml_turbo_wht()` function definition | `undefined symbol: ggml_turbo_wht` at startup |
| `ggml/src/ggml.c` | `"TURBO_WHT"` in `GGML_OP_NAME[]` array | Wrong op name displayed; shifted array offsets for subsequent ops |
| `ggml/src/ggml-cpu/ggml-cpu.c` | `type_traits_cpu[]` entries for TURBO types | `undefined symbol` for `quantize_row_turbo*_ref` at link time |
| `ggml/src/ggml-cpu/ggml-cpu.c` | `GGML_OP_TURBO_WHT` case in `ggml_get_n_tasks()` | `op not implemented: TURBO_WHT` during graph execution |
| `ggml/src/ggml-cpu/ggml-cpu.c` | `GGML_OP_TURBO_WHT` case in `ggml_compute_forward()` dispatch | TURBO_WHT ops never execute on CPU |
| `ggml/src/ggml-cpu/ggml-cpu.c` | `ggml_vec_dot_turbo*_f32()` function definitions | `undefined symbol` at link time |
| `ggml/src/ggml-cpu/ops.cpp` | `ggml_compute_forward_turbo_wht()` function | `undefined symbol: ggml_compute_forward_turbo_wht` at runtime |

**How this manifests at runtime (symptom chain):**

1. Server starts with `--cache-type-k turbo4`
2. Model loading begins, calls `ggml_type_name(GGML_TYPE_TURBO4_0)`
3. `type_traits[44]` is uninitialized → returns garbage/null string pointer
4. Or: `llama-kv-cache.cpp` calls `ggml_get_type_traits(type)->to_float(...)` →
   null function pointer → **SIGSEGV** (exit code 139)
5. In router mode, the child process dies with signal 11; parent logs
   `"instance exited with status -11"`

**How to prevent this in future merges:**

Always run this checklist after any merge:

```bash
# 1. Check type_traits[] has TURBO entries (indices 42-46 in ggml.c)
grep -n 'TURBO3_0\|TURBO4_0\|TURBO2_0' ggml/src/ggml.c
# Expected: 3 entries in the type_traits array (not just in comments or op_params)

# 2. Check ggml_turbo_wht() function exists
grep -n '^struct ggml_tensor \* ggml_turbo_wht' ggml/src/ggml.c
# Expected: 1 definition

# 3. Check "TURBO_WHT" in op name array
grep -n '"TURBO_WHT"' ggml/src/ggml.c
# Expected: 1 occurrence, after "GATED_DELTA_NET" and before "LIGHTNING_INDEXER"

# 4. Check ggml_compute_forward_turbo_wht in CPU backend
grep -n 'ggml_compute_forward_turbo_wht' ggml/src/ggml-cpu/ggml-cpu.c
grep -n 'GGML_OP_TURBO_WHT' ggml/src/ggml-cpu/ggml-cpu.c
# Expected: 1 in dispatch, 1 in get_n_tasks

# 5. Check ggml_compute_forward_turbo_wht in ops.cpp
grep -n 'void ggml_compute_forward_turbo_wht' ggml/src/ggml-cpu/ops.cpp
# Expected: 1 definition

# 6. Build and check symbols exist
docker run --rm --entrypoint sh llama-server:latest \
  -c 'nm -D /app/libggml-base.so.0.16.0 2>/dev/null | grep ggml_turbo_wht'
# Expected: shows the symbol

# 7. Quick smoke test with turbo cache types
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
# Expected: HTTP 200, not 000
```

**If any of these are missing:** copy the missing sections from the
`atomic/feature/turboquant-kv-cache` branch:

```bash
git show atomic/feature/turboquant-kv-cache:ggml/src/ggml.c | sed -n '767,790p'
# ^ TURBO type_traits entries (insert after [38] in type_traits[])

git show atomic/feature/turboquant-kv-cache:ggml/src/ggml.c | sed -n '6400,6425p'
# ^ ggml_turbo_wht() function definition

git show atomic/feature/turboquant-kv-cache:ggml/src/ggml-cpu/ggml-cpu.c | sed -n '216,224p'
# ^ forward declarations for TURBO vec_dot functions

git show atomic/feature/turboquant-kv-cache:ggml/src/ggml-cpu/ggml-cpu.c | sed -n '433,450p'
# ^ TURBO type_traits_cpu entries

git show atomic/feature/turboquant-kv-cache:ggml/src/ggml-cpu/ops.cpp | sed -n '10948,11050p'
# ^ ggml_compute_forward_turbo_wht() implementation
```

**Also verify: `GGML_OP_NAME[]` array in `ggml/src/ggml.c`**

The op name array must have entries at the exact enum index positions. If a name
is missing (e.g. `"TURBO_WHT"`), all subsequent names shift by one and the op
name lookup returns the wrong string.

```bash
# Check the op name order matches enum order in ggml.h
grep -n 'SOLVE_TRI\|GATED_DELTA_NET\|TURBO_WHT\|LIGHTNING_INDEXER\|DSV4' ggml/include/ggml.h
grep -n 'SOLVE_TRI\|GATED_DELTA_NET\|TURBO_WHT\|LIGHTNING_INDEXER\|DSV4' ggml/src/ggml.c
# The order must be identical
```

**Docker build cache trap:**

After editing source files, Docker's incremental build may NOT recompile changed
files because cmake in the container sees the object files are newer than the
source (Docker `COPY` preserves timestamps). Always use `--no-cache` when building
after merge fixes, or `touch` the changed files before `docker build`:

```bash
touch ggml/src/ggml.c ggml/src/ggml-cpu/ggml-cpu.c ggml/src/ggml-cpu/ops.cpp
docker build --no-cache -f .devops/cuda.Dockerfile -t llama-server:latest .
```

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


## Update Protocol — Full Lifecycle

This is the standard operating procedure for any source update, merge, or
cherry-pick. Follow these steps in order. Never skip the pre-flight or
post-build validation — the cost of catching a regression late is hours of
debugging.

---

### Step 0: Decide If It's Time to Update

**Before doing anything, run the decision framework in the
"When to Update" section below.** If the answer is "no" or "not yet",
stop here. If "yes", proceed.

---

### Step 1: Backup Current State

Before touching source or configs, create rollback anchors:

```bash
cd ~/llmaCPP

# 1. Tag the current Docker image as a named stable snapshot
STABLE_TAG="llama-server:stable-$(date +%Y-%m-%d)"
docker tag llama-server:latest "$STABLE_TAG"
echo "Tagged: $STABLE_TAG"

# 2. Backup docker-compose.yml
cp docker-compose.yml "compose-backup/docker-compose-$(date +%Y-%m-%d)-pre-update.yml"

# 3. Record current source HEAD
cd ~/llmaCPP/source
git log -1 --oneline > .backup_head
echo "Backed up HEAD: $(cat .backup_head)"

cd ~/llmaCPP
```

**To roll back later (see Step 8):**
```bash
docker tag llama-server:stable-YYYY-MM-DD llama-server:latest
cd ~/llmaCPP/source
git checkout $(cat .backup_head | awk '{print $1}')
cp compose-backup/docker-compose-YYYY-MM-DD-pre-update.yml docker-compose.yml
docker compose up -d --force-recreate llama-server llama-server-mini
```

---

### Step 2: Pre-Flight Diff Check

**Before merging anything**, inspect the diff between the target branch and
your current working branch. This catches structural breakers before they
reach your build.

```bash
cd ~/llmaCPP/source

# Ensure all remotes are fresh
git fetch origin --tags --force
git fetch atomic --tags --force

echo "=== Diff summary: files changed ==="
git diff --stat turboquant-merged-2026-07-06..atomic/feature/turboquant-kv-cache

echo ""
echo "=== CHECK 1: VRAM-critical areas ==="
# These files control memory allocation, kernel config, and context sizing
for f in \
  ggml/src/ggml-alloc.c \
  ggml/src/ggml-cuda/ \
  src/llama-kv-cache.cpp \
  src/llama-model-loader.cpp \
  common/arg.cpp \
  tools/server/server.cpp; do
  changes=$(git diff turboquant-merged-2026-07-06..atomic/feature/turboquant-kv-cache -- "$f" | wc -l)
  if [ "$changes" -gt 0 ]; then
    echo "  ⚠️  $f — $changes lines changed (potential VRAM impact)"
  fi
done

echo ""
echo "=== CHECK 2: GGML_OP_COUNT / RPC version changes ==="
git diff turboquant-merged-2026-07-06..atomic/feature/turboquant-kv-cache -- \
  ggml/include/ggml.h ggml/include/ggml-rpc.h | grep -E '^[+-].*OP_COUNT|PATCH_VERSION'

echo ""
echo "=== CHECK 3: New or removed CLI flags ==="
git diff turboquant-merged-2026-07-06..atomic/feature/turboquant-kv-cache -- \
  common/arg.cpp common/common.cpp | grep -E '^[+-].*"--' || echo "  (none detected)"

echo ""
echo "=== CHECK 4: TURBO type references (must NOT be removed) ==="
tq_refs=$(git diff turboquant-merged-2026-07-06..atomic/feature/turboquant-kv-cache -- \
  ggml/src/ggml.c ggml/src/ggml-cpu/ggml-cpu.c ggml/src/ggml-cpu/ops.cpp | \
  grep -c 'TURBO' || true)
echo "  TURBO references changed: $tq_refs lines"
if [ "$tq_refs" -gt 0 ]; then
  echo "  ⚠️  TURBO types touched! Run Step 4 audit carefully."
fi
```

**Red flags that mean "do not merge automatically":**

| Red flag | What to do |
|---|---|
| `ggml-alloc.c` has major rewrites | Postpone merge, investigate allocator changes first |
| `arg.cpp` has new/removed flags | Audit for router-mode incompatibility |
| `ggml-cuda/` MMQ or fattn refactored | Expect VRAM shift — run Step 6 dry-run test |
| TURBO references removed in diff | Block merge — restore TURBO types from fork branch |
| `ggml.h` GGML_OP_COUNT changed | Update assertion in ggml.c and ggml-rpc.h after merge |

---

### Step 3: Merge

Choose the method based on what you're syncing:

#### Quick method (update from TurboQuant fork only)

```bash
cd ~/llmaCPP/source
git checkout turboquant-merged-2026-07-06
git merge atomic/feature/turboquant-kv-cache

# Resolve conflicts using established patterns:
#   server files (tools/server/) → take theirs
#   TQ core files (ggml/src/ggml.c, fattn.cu) → keep TQ version
#   kv-cache, model-loader → combine (see conflict resolution log above)

git add .
git commit -m "merge: atomic/feature/turboquant-kv-cache into turboquant-merged"
```

#### Cherry-pick specific upstream features

```bash
cd ~/llmaCPP/source
git checkout turboquant-merged-2026-07-06

# List features NOT in atomic fork
git log --oneline origin/master --not atomic/feature/turboquant-kv-cache

# Cherry-pick a specific commit
git cherry-pick <commit-hash>

# If GGML_OP_COUNT changed, update assertions:
#   ggml/include/ggml-rpc.h
#   ggml/src/ggml.c
```

#### Full method (if far behind both upstream and fork)

```bash
cd ~/llmaCPP/source

# Create a fresh branch for the attempt
git fetch origin --tags --force
git fetch atomic --tags --force
git checkout -b "merge-$(date +%Y-%m-%d)" turboquant-merged-2026-07-06
git merge atomic/feature/turboquant-kv-cache

# Resolve conflicts, then commit
```

**After any merge method, immediately verify brace and symbol integrity
(Step 4) before building.**

---

### Step 4: Post-Merge Symbol & Brace Audit

Run these checks immediately after resolving merge conflicts and before
building. Every check must pass.

```bash
cd ~/llmaCPP/source

echo "=== AUDIT 1: fattn.cu brace balance ==="
OPEN=$(awk 'NR>=38 && NR<118' ggml/src/ggml-cuda/fattn.cu | grep -o '{' | wc -l)
CLOSE=$(awk 'NR>=38 && NR<118' ggml/src/ggml-cuda/fattn.cu | grep -o '}' | wc -l)
echo "  braces: $OPEN open, $CLOSE close"
if [ "$OPEN" -ne "$CLOSE" ]; then
  echo "  ❌ FAIL — fattn.cu brace mismatch! Fix before building."
  echo "  See 'Fix applied (fattn.cu brace merge artifact)' above."
  exit 1
else
  echo "  ✅ PASS"
fi

echo ""
echo "=== AUDIT 2: TURBO type_traits entries in ggml.c ==="
grep -c 'TURBO3_0\|TURBO4_0\|TURBO2_0' ggml/src/ggml.c | while read n; do
  if [ "$n" -lt 3 ]; then
    echo "  ❌ FAIL — expected >=3 TURBO type_traits entries, found $n"
    exit 1
  else
    echo "  ✅ PASS ($n TURBO entries)"
  fi
done

echo ""
echo "=== AUDIT 3: ggml_turbo_wht() function ==="
grep -c '^struct ggml_tensor \* ggml_turbo_wht' ggml/src/ggml.c | while read n; do
  if [ "$n" -eq 0 ]; then
    echo "  ❌ FAIL — ggml_turbo_wht() missing from ggml.c"
    exit 1
  else
    echo "  ✅ PASS"
  fi
done

echo ""
echo "=== AUDIT 4: TURBO_WHT in op name array ==="
grep -c '"TURBO_WHT"' ggml/src/ggml.c | while read n; do
  if [ "$n" -eq 0 ]; then
    echo "  ❌ FAIL — TURBO_WHT missing from GGML_OP_NAME[]"
    exit 1
  else
    echo "  ✅ PASS"
  fi
done

echo ""
echo "=== AUDIT 5: GGML_OP_NAME[] order vs ggml.h enum ==="
echo "  Checking op order alignment..."
H_ENUM=$(grep -n 'SOLVE_TRI\|GATED_DELTA_NET\|TURBO_WHT\|LIGHTNING_INDEXER\|DSV4' ggml/include/ggml.h)
C_ENUM=$(grep -n 'SOLVE_TRI\|GATED_DELTA_NET\|TURBO_WHT\|LIGHTNING_INDEXER\|DSV4' ggml/src/ggml.c)
echo "  ggml.h:  $H_ENUM"
echo "  ggml.c:  $C_ENUM"
echo "  (Order must match exactly)"

echo ""
echo "=== AUDIT 6: INI model keys ==="
SECTIONS=$(grep -c '^\[.*\]$' ~/llmaCPP/models/models.ini)
MODEL_KEYS=$(grep -c '^model = ' ~/llmaCPP/models/models.ini)
echo "  models.ini: $SECTIONS sections, $MODEL_KEYS model keys"
if [ "$SECTIONS" -ne "$MODEL_KEYS" ]; then
  echo "  ❌ FAIL — missing model = keys in models.ini"
  exit 1
fi
SECTIONS=$(grep -c '^\[.*\]$' ~/llmaCPP/models/modelg.ini)
MODEL_KEYS=$(grep -c '^model = ' ~/llmaCPP/models/modelg.ini)
echo "  modelg.ini: $SECTIONS sections, $MODEL_KEYS model keys"
if [ "$SECTIONS" -ne "$MODEL_KEYS" ]; then
  echo "  ❌ FAIL — missing model = keys in modelg.ini"
  exit 1
fi

echo ""
echo "All audits passed. Proceed to build."
```

**If any audit fails:** restore the missing lines from the TurboQuant fork:

```bash
git show atomic/feature/turboquant-kv-cache:ggml/src/ggml.c | sed -n '767,790p'
# ^ TURBO type_traits entries (insert after [38] in type_traits[])

git show atomic/feature/turboquant-kv-cache:ggml/src/ggml.c | sed -n '6400,6425p'
# ^ ggml_turbo_wht() function definition

git show atomic/feature/turboquant-kv-cache:ggml/src/ggml-cpu/ggml-cpu.c | sed -n '216,224p'
# ^ forward declarations for TURBO vec_dot functions

git show atomic/feature/turboquant-kv-cache:ggml/src/ggml-cpu/ggml-cpu.c | sed -n '433,450p'
# ^ TURBO type_traits_cpu entries

git show atomic/feature/turboquant-kv-cache:ggml/src/ggml-cpu/ops.cpp | sed -n '10948,11050p'
# ^ ggml_compute_forward_turbo_wht() implementation
```

---

### Step 5: Build

```bash
cd ~/llmaCPP/source

# Always use --no-cache after merge to avoid cmake timestamp trap
docker build \
  --no-cache \
  --build-arg CUDA_DOCKER_ARCH="60;61" \
  -f .devops/cuda.Dockerfile \
  --target server \
  -t llama-server:latest .
```

**Performance tip:** If you're doing iterative development (not a merge),
skip `--no-cache` for speed:
```bash
docker build \
  --build-arg CUDA_DOCKER_ARCH="60;61" \
  -f .devops/cuda.Dockerfile \
  --target server \
  -t llama-server:latest .
```

**Docker build cache trap (important):**
`COPY` preserves timestamps, so cmake may think source files are older than
compiled objects and skip recompilation. If you edited source files without
changing the commit (e.g., manual fixups), `touch` them before build:

```bash
touch ggml/src/ggml.c ggml/src/ggml-cpu/ggml-cpu.c ggml/src/ggml-cpu/ops.cpp
```

---

### Step 6: Post-Build Symbol Verification

```bash
# Verify TURBO symbols exist in the compiled library
docker run --rm --entrypoint sh llama-server:latest \
  -c 'nm -D /app/libggml-base.so.0.16.0 2>/dev/null | grep ggml_turbo_wht'
# Expected: shows the symbol (not empty)
```

---

### Step 7: VRAM Dry-Run Test

Before deploying to production, run a quick smoke test that validates all 4
models load without OOM at full context. This is the single most important
validation step — the July 26 regression was only detectable here.

```bash
# Test each model with a short context first (quick smoke test)
for model in \
  /models/Gemma4-E4B-0918-Q4_K_XL.gguf \
  /models/Gemma4-12B-0918-Q4_K_XL.gguf \
  /models/agents-a1-Q6_K_L.gguf \
  /models/Gemma4-26B-0918-Q4_K_XL.gguf; do

  echo "Testing: $(basename $model) at ctx=4096..."
  docker run --rm --gpus all --entrypoint /app/llama-server \
    -v /home/nui/llmaCPP/models:/models \
    llama-server:latest \
    --host 0.0.0.0 --port 8099 --no-mmap \
    --model "$model" \
    --n-gpu-layers -1 \
    --cache-type-k turbo4 --cache-type-v turbo2 \
    --ubatch-size 512 --ctx-size 4096 \
    --no-warmup &
  SERVER_PID=$!
  sleep 10
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8099/health 2>/dev/null)
  kill $SERVER_PID 2>/dev/null
  wait $SERVER_PID 2>/dev/null

  if [ "$STATUS" = "200" ]; then
    echo "  ✅ $(basename $model) — HTTP $STATUS"
  else
    echo "  ❌ $(basename $model) — HTTP $STATUS (check VRAM)"
    nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
    echo "  Aborting deploy."
    exit 1
  fi
done

echo ""
echo "All models passed smoke test at ctx=4096. Testing full context (65536)..."

# Now test the tightest model (26B) at full context
model="/models/Gemma4-26B-0918-Q4_K_XL.gguf"
echo "Testing: $(basename $model) at ctx=65536..."
docker run --rm --gpus all --entrypoint /app/llama-server \
  -v /home/nui/llmaCPP/models:/models \
  llama-server:latest \
  --host 0.0.0.0 --port 8099 --no-mmap \
  --model "$model" \
  --n-gpu-layers -1 \
  --cache-type-k turbo4 --cache-type-v turbo2 \
  --ubatch-size 512 --ctx-size 65536 \
  --no-warmup &
SERVER_PID=$!
sleep 30
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8099/health 2>/dev/null)
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

if [ "$STATUS" = "200" ]; then
  echo "  ✅ 26B at ctx=65536 — HTTP $STATUS"
else
  echo "  ❌ 26B at ctx=65536 — HTTP $STATUS (VRAM regression likely)"
  nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
  echo "  Reduce ctx-size or investigate regression before deploying."
  exit 1
fi

echo ""
echo "✅ All VRAM tests passed. Safe to deploy."
```

---

### Step 8: Deploy

```bash
cd ~/llmaCPP

# Tag the new image as a named release
docker tag llama-server:latest "llama-server:release-$(date +%Y-%m-%d)"

# Update LLM-MOBILE UI with new image reference
docker compose up -d --force-recreate llama-server llama-server-mini

# Verify both servers are healthy
sleep 15
echo "Primary:   $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health)"
echo "Secondary: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/health)"
echo ""
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
```

---

### Step 9: Safety Fallback (if something went wrong)

If any step above failed and you need to revert to the previous working state:

```bash
cd ~/llmaCPP

# 1. Restore the stable Docker image
#    (you tagged this in Step 1 or during the last successful deploy)
docker tag llama-server:stable-YYYY-MM-DD llama-server:latest

# 2. Restore the previous docker-compose.yml
cp compose-backup/docker-compose-YYYY-MM-DD-pre-update.yml docker-compose.yml

# 3. Restore the previous source (if source was modified)
cd ~/llmaCPP/source
git checkout $(cat .backup_head | awk '{print $1}')

# 4. Restart with the old config
cd ~/llmaCPP
docker compose up -d --force-recreate llama-server llama-server-mini

# 5. Verify
sleep 15
echo "Primary:   $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health)"
echo "Secondary: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/health)"
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
```

**If the source directory is completely broken** (uncommitted changes, bad
merge state):

```bash
cd ~/llmaCPP/source
# Discard all uncommitted changes and go back to the known-good commit
git checkout -- .
git checkout turboquant-merged-2026-07-06

# If .backup_head exists, use that commit instead
if [ -f .backup_head ]; then
  git checkout $(cat .backup_head | awk '{print $1}')
fi
```

**If the Docker image wasn't tagged** before the bad build:

```bash
# List images by creation date to find the previous one
docker images llama-server --format "table {{.Tag}}	{{.CreatedAt}}	{{.Size}}"

# If a release tag exists from a previous deploy, use that:
docker tag llama-server:release-YYYY-MM-DD llama-server:latest

# Worst case: rebuild from the known-good source commit
docker build --no-cache \
  --build-arg CUDA_DOCKER_ARCH="60;61" \
  -f .devops/cuda.Dockerfile \
  --target server \
  -t llama-server:latest .
```

---

### Known router-mode flags that crash the parent process

These flags are **model-level only** — they must go in the INI preset, not in
the docker-compose `command:`:

- `--cache-type-k` / `--cache-type-v`
- `--flash-attn` (though it works, prefer INI)

---

## When to Update — Decision Framework

Not every upstream or fork change is worth merging. This framework helps you
decide whether to invest time in an update, wait, or skip it entirely.

Use this **before** starting the Update Protocol (Step 0).

---

### Three Questions to Ask

#### Q1: Does the new code fix a problem you actually have?

| If you're considering... | Ask yourself |
|---|---|
| A new model architecture | Do you have a GGUF of this model you want to run? |
| A performance improvement | Is this bottleneck visible in your workloads? (e.g., prompt processing speed on P100) |
| A bug fix | Are you hitting this bug? (check server logs, issue tracker) |
| A new CLI flag / feature | Do you need this feature? (e.g., MTP, new cache type) |

**Rule of thumb:** If you weren't looking for it before you saw the commit
message, you probably don't need it right now.

#### Q2: What is the risk of breakage?

Evaluate the diff against your known regressions:

```bash
cd ~/llmaCPP/source

# Quick risk scan: count files changed in high-risk areas
high_risk=0
for f in ggml/src/ggml-alloc.c ggml/src/ggml-cuda/ src/llama-kv-cache.cpp \
         common/arg.cpp tools/server/server.cpp; do
  changes=$(git diff --stat turboquant-merged-2026-07-06..atomic/feature/turboquant-kv-cache -- "$f" 2>/dev/null | tail -1 | grep -oP '\\d+(?= insertion)' || echo 0)
  high_risk=$((high_risk + changes))
done

if [ "$high_risk" -gt 200 ]; then
  echo "⚠️  High-risk: $high_risk lines changed in critical areas"
  echo "   Expect VRAM shifts, CLI flag changes, or allocator differences."
else
  echo "✅ Low-risk: $high_risk lines changed in critical areas"
fi
```

**Risk levels:**

| Risk level | Lines changed in critical areas | Decision |
|---|---|---|
| **Low** | 0–50 | Safe to merge, quick test |
| **Medium** | 50–200 | Merge cautiously, run full VRAM dry-run (Step 7) |
| **High** | 200–500+ | Postpone unless you need a specific feature |
| **Critical** | CUDA MMQ refactor, allocator rewrite | Do not merge — wait for TurboQuant fork to re-anchor |

#### Q3: Has the TurboQuant fork author re-anchored to a newer upstream?

This is the most important leading indicator. TurboQuant is a downstream fork
of llama.cpp. If the TurboQuant maintainer has explicitly re-anchored their
work to a newer upstream commit, that's the safest time to sync — they've
already done the hard work of resolving upstream conflicts.

```bash
cd ~/llmaCPP/source

# Check if the fork has moved upstream
fork_base=$(git merge-base origin/master atomic/feature/turboquant-kv-cache 2>/dev/null || echo "unknown")
echo "Fork's upstream anchor: $(git log -1 --oneline $fork_base 2>/dev/null || echo 'unknown')"

# Compare to your current anchor
your_base=$(git log -1 --oneline turboquant-merged-2026-07-06 2>/dev/null | head -1)
echo "Your current anchor:    $your_base"

# If fork has a newer anchor, it's safer to sync
```

**Good time to update:** The TurboQuant author has released a new version or
merged upstream, explicitly noting the upstream commit they anchored to.

**Bad time to update:** You're trying to merge upstream into TurboQuant
yourself without the fork author's groundwork.

---

### Decision Matrix

| Q1 (Need it?) | Q2 (Risk?) | Q3 (Fork anchored?) | Verdict |
|---|---|---|---|
| ✅ Yes | 🟢 Low | ✅ Yes | **Go** — follow full Update Protocol |
| ✅ Yes | 🟢 Low | ❌ No | **Go** — low risk, fork anchor not critical |
| ✅ Yes | 🟡 Medium | ✅ Yes | **Go cautiously** — run all VRAM dry-run tests |
| ✅ Yes | 🟡 Medium | ❌ No | **Wait** — risk without fork anchor; cherry-pick if urgent |
| ✅ Yes | 🔴 High | ✅ Yes | **Evaluate** — consider cherry-picking only what you need |
| ✅ Yes | 🔴 High | ❌ No | **Postpone** — too risky without fork groundwork |
| ❌ No | Any | Any | **Skip** — don't fix what isn't broken |
| ❌ No | N/A | N/A | **Skip** — wait for a feature you actually need |

---

### What to Do While Waiting

If the verdict is "wait" or "postpone", you're not stuck. You can:

1. **Monitor the TurboQuant fork** for new releases or explicit re-anchoring:
   ```bash
   cd ~/llmaCPP/source
   git fetch atomic --tags --force
   git log --oneline turboquant-merged-2026-07-06..atomic/feature/turboquant-kv-cache | head -20
   ```

2. **Track upstream llama.cpp releases** for features that might eventually
   land in TurboQuant:
   ```bash
   cd ~/llmaCPP/source
   git fetch origin --tags --force
   git tag -l 'b*' --sort=-version:refname | head -10
   ```

3. **Cherry-pick only if you need a specific fix** — don't merge the whole
   branch. Use the cherry-pick method in the Update Protocol (Step 3).

4. **Periodically run the VRAM baseline** to make sure your current setup
   hasn't drifted (e.g., after Docker/Kernel updates):
   ```bash
   nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
   ```

---

### Signals That It IS Time to Update

Watch for these triggers that override the "wait" verdict:

| Signal | Action |
|---|---|
| A model you want requires a newer llama.cpp architecture | Full merge, test thoroughly |
| TurboQuant author releases a new tag with changelog | Full merge, run all tests |
| A security fix lands in upstream llama.cpp | Cherry-pick just the fix |
| Your current setup breaks (e.g., host CUDA driver update) | Full merge as last resort |
| TurboQuant's KV cache compression gets measurably better for your workload | Full merge, benchmark before/after |
| You've been on the same baseline for >6 months | Consider a planned upgrade cycle |

---

### Record Your Decision

When you decide to update (or not), log it here at the top of the file so
future-you knows why:

```markdown
## Update Decision — YYYY-MM-DD

**Assessment:** Update needed? (Yes/No/Wait)
**Target:** upstream / turboquant / cherry-pick
**Reason:** ...
**Risk level:** Low / Medium / High
**Result:** (filled in after update)
```

---

## References

### Fork Lineage

```
Google DeepMind TurboQuant (ICLR 2026)
  └─ AmesianX/TurboQuant — Reference implementation (92★)
       └─ TheTom/llama-cpp-turboquant — Original drop-in fork
            └─ AtomicBot-ai/atomic-llama-cpp-turboquant ← WE ARE HERE (312★, 42 forks)
                 └─ turboquant-merged-2026-07-06 ← our custom merge branch
```

There are ~15 active TurboQuant llama.cpp forks. Ours is the largest actively
maintained fork with router mode support, Gemma 4 MTP, and Qwen NextN.

| Fork | Stars | Focus |
|---|---|---|
| **AtomicBot-ai/atomic-llama-cpp-turboquant** | **312** ← ours | MTP + NextN + router mode + Gemma 4 |
| spiritbuun/buun-llama-cpp | 719 | General TurboQuant, most starred |
| BoFan-tunning/llama.cpp-MTP-TurboQuant | 143 | MTP-focused |
| Indras-Mirror/llama.cpp-turboq-mtp | 92 | Fused TBQ4 Flash Attention + MTP |
| AmesianX/TurboQuant | 92 | Original reference implementation |
| domvox/llama.cpp-turboquant-hip | 56 | AMD ROCm port |
| atomicmilkshake/llama-cpp-turboquant | 41 | TriAttention KV pruning |

**Monitor for updates:** Check if the fork author re-anchored to upstream
before attempting a merge (see "When to Update" section, Q3).

---

### Quick Reference

| Resource | Path |
|---|---|
| Active branch | `source` → `turboquant-merged-2026-07-06` (commit `797cf14a2`) |
| Our fork remote | `atomic` → `AtomicBot-ai/atomic-llama-cpp-turboquant` |
| Upstream remote | `origin` → `ggml-org/llama.cpp` |
| Old HEAD backup | `source/.backup_head` |
| Compose config | `docker-compose.yml` |
| Backup compose configs | `compose-backup/` |
| Deprecated branch (VRAM regression) | `source` → `turboquant-merged-2026-07-26` (not deployed) |
| Server health | `http://localhost:8080/health` |
| Mini server health | `http://localhost:8081/health` |
| VRAM monitor | `nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader` |
| Backup of pre-rollback compose | `compose-backup/docker-compose-<date>-pre-turboquant-july6.yml` |
| Backup of July 26 compose | `compose-backup/docker-compose-turboquant-merged-2026-07-26.yml` |

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
