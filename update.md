# llmaCPP Source Update Log

## Current State — 2026-10-31

| Item | Value |
|---|---|
| Primary source | `source-kmic-68/` @ `p100-optimizations`, commit `83a7f0839` |
| Secondary source | `source-thetom/` @ `feature/turboquant-kv-cache`, commit `643956891` |
| Primary image | `llama-server:kmic-p100-nov6` |
| Secondary image | `llama-server:thetom-oct29` |
| Rollback anchor | `llama-server:stable-2026-10-31` (TheTom `thetom-oct29`) |
| Primary | `llama-server` → `llm-server`, port 8080, GPU 0 (P100) |
| Secondary | `llama-server-mini` → `llm-server-mini`, port 8081, GPU 1 (1060) |
| GPUs | 0 = Tesla P100 16 GB (sm_60), 1 = GTX 1060 6 GB (sm_61) |
| Primary build arch | `CUDA_DOCKER_ARCH=60` (sm_60 only) |
| Secondary build arch | `CUDA_DOCKER_ARCH="60;61"` |
| Primary KV | `q4_0` / `q4_0` |
| Secondary KV | `turbo4` / `turbo2` |

> `source/` no longer exists. `source-kmic-68/` builds the primary (P100) image;
> `source-thetom/` builds the mini and is the primary rollback.

---

## Update — 2026-10-29 (pull + build `thetom-oct29`)

- Pulled `source-thetom`: `ca28b4bc0` → `643956891` (12 commits, 88 files).
- New: **turbo5/turbo6 KV cache types** (CUDA + HIP FA, SET_ROWS, CPY), **Spark 2.5** arch.
- Local uncommitted fix in `src/models/lfm2.cpp` (`res->t_layer_inp[il] = cur;`) preserved.
- Build: `CUDA_DOCKER_ARCH="60;61"`, image `llama-server:thetom-oct29` (7.12 GB).
- Verified `llama-server --version` → `10878 (643956891)`.
- Smoke test both GPUs (E4B Q4_K_XL, ctx 2048, turbo4/turbo2): health 200 in ~3 s,
  chat completion OK, 1060 used ~2.7 GiB.
- `docker-compose.yml` updated to `thetom-oct29` for both services.

```bash
# Exact build command (from source-thetom/)
docker build --build-arg CUDA_DOCKER_ARCH="60;61" \
  -f .devops/cuda.Dockerfile --target server -t llama-server:thetom-oct29 .
```

---

## Update — 2026-10-31 (Kmic-68 P100 fork → primary)

- Added `source-kmic-68/` (`Kmic-68/llama.cpp`, branch `p100-optimizations`,
  HEAD `7461904db`, upstream `d327bf1f0` from 2026-10-24).
- P100/sm_60-tuned CUDA kernels. **Build with `CUDA_DOCKER_ARCH=60` only**:
  adding `61` silently disables the tuning (`__CUDA_ARCH_LIST__ == 600`).
- No TurboQuant in this fork; `turbo*` cache types are invalid. `models.ini`
  switched to `q4_0`/`q4_0`; added `spec-draft-ngl`, `spec-draft-ubatch-size`,
  `spec-draft-type-k/v` to the MTP/dflash presets.
- Compile fix: `src/llama-context.cpp` uses `std::max<int64_t>({...})`; GCC 14
  no longer pulls `<algorithm>` in transitively. `script/build-kmic.sh` applies
  this one-line include patch automatically.
- Build (from `source-kmic-68/`), or just `./script/build-kmic.sh --deploy`:

  ```bash
  docker build --build-arg CUDA_DOCKER_ARCH=60 \
    -f .devops/cuda.Dockerfile --target server \
    -t llama-server:kmic-p100-2026-10-31 .
  ```

- Verified `--version` → `0.7.0-dev (build 12323, commit 7461904db)`.
- Smoke: gemma-4-E4B Q4_K_XL, ctx 4096, q4_0/q4_0 → health 200 in ~6 s.
- Swift-1.5-27B @ 64k on P100: 13.68 GiB; 4,016-token prompt →
  **214.5 t/s prompt, 31.0 t/s decode**, 14,121 MiB peak.
- A/B vs TheTom (`thetom-oct29`, turbo4/turbo2), same prompt/GPU:

  | Build | KV | Prompt t/s | Decode t/s | Peak MiB |
  |---|---|---|---|---|
  | Kmic `7461904db` | q4_0/q4_0 | 214.5 | 31.0 | 14,121 |
  | TheTom `643956891` | turbo4/turbo2 | 102.4 | 19.4 | 14,385 |

  → ~2.1x prefill, ~1.6x decode.
- Deployed primary only (`docker compose up -d --force-recreate llama-server`);
  mini stayed on `thetom-oct29`. Both healthy; router mode; GPUs idle after tests.
- Backups: `compose-backup/docker-compose-2026-10-31-pre-kmic.yml`,
  `models/models.ini.thetom-2026-10-31.bak`, rollback tag
  `llama-server:stable-2026-10-31`.
- The 1060 can run the sm_60 image via minor-version binary compatibility, but
  it would execute P100 paths; keep the mini on TheTom.

---

## Update — 2026-10-31 (Kmic fused-GDN fix → `kmic-p100-2026-10-31-gdnfix`)

- `agents-a1-IQ4_XS-MTP-graft-headQ6.gguf` (arch `qwen35moe`, 256 experts,
  SSM/Gated Delta Net, 19 GiB) crashed on the first Kmic image during the
  warmup decode: `CUDA error: an illegal memory access` in
  `ggml_cuda_op_gated_delta_net_fused_cache`.
- Cause: the P100 fork forces `cparams.fused_gdn_ar/ch = true` and sets
  `auto_fgdn = false`, so the resolver never disables the fused GDN. The
  fused-cache kernel is not valid on sm_60 for this model.
- Fix in `source-kmic-68/src/llama-context.cpp`: disable fused GDN only for
  `LLM_ARCH_QWEN35MOE`; `qwen35` (e.g. Qwen3.5-9B) and other arches keep the
  tuned path. `script/build-kmic.sh` applies this guard automatically.
- Rebuilt as `llama-server:kmic-p100-2026-10-31-gdnfix` (same commit
  `7461904db`, build 12323). Old Kmic image remains as
  `llama-server:kmic-p100-2026-10-31` for rollback.

  ```bash
  ./script/build-kmic.sh --tag llama-server:kmic-p100-2026-10-31-gdnfix --yes
  ```
- Verified on the P100: model loads with `-ngl -1 --fit on`, ctx 30208,
  mmproj, and MTP; peak VRAM ~15.3 GiB; 16-token reply in ~250 ms decode;
  MTP draft acceptance 1.00 (10/10, mean len 3.0).
- Qwen3.5-9B (dense `qwen35`) still loads and runs with fused GDN enabled.
- Pre-fix compose backup: `compose-backup/docker-compose-2026-10-31-pre-kmic-125951.yml`.

---

## Update — 2026-11-06 (Kmic-68 pull + rebuild → `kmic-p100-nov6`)

- Pulled `source-kmic-68`: `7461904db` → `83a7f0839` (15 commits ahead, 20 files changed).
- Stashed local `src/llama-context.cpp` patches (`<algorithm>` include + fused-GDN `qwen35moe` guard); `<algorithm>` include was merged upstream (commit `be61e350a`) — redundant now; fused-GDN guard still local-only and re-applied by `script/build-kmic.sh`.
- Notable upstream changes: MTP stop-rule chat tables (`edffc3fa2`, +6.6% t/s at T 0.3), MTP stop-rule tables for thinking-on (`715e36256`, +2.9%), MTP draft stop rule from traced acceptance (`2700dfda8`, +4.7%), GDN state gather skip fix for Qwen3.6-35B-A3B decode crash (`72a97be54`), sm_60 IQ2/IQ3 sign flip + grid fixes (`00b52988c`), various MMQ/MoE/fattn CUDA optimizations.
- Built with `CUDA_DOCKER_ARCH=60` (sm_60 only), image `llama-server:kmic-p100-nov6`.
- Verified `--version` → `0.7.0-dev (build 12338, commit 83a7f0839)`.
- Deployed primary only (`docker compose up -d --force-recreate llama-server`); both services healthy (`/health` → 200). Mini stayed on `thetom-oct29`.
- Backup: `compose-backup/docker-compose-2026-11-06-pre-kmic-131603.yml`.
- Rollback anchor: `llama-server:stable-2026-11-06`.

---

## Current Config

Both servers run router mode with `--models-preset`, `--flash-attn on`,
`--load-mode mlock`, `-np 1`, `--models-max 1`, `--tools all`.
Model-level flags live in the INI files, not `command:`.

Primary (`models.ini`, Kmic) `[*]` defaults:

```ini
c = 65536
n-gpu-layers = -1
ubatch-size = 2048
cache-type-k = q4_0
cache-type-v = q4_0
device = CUDA0
split-mode = none
main-gpu = 0
```

Secondary (`modelg.ini`, TheTom) is the same except
`cache-type-k = turbo4`, `cache-type-v = turbo2`; no `device`/`split-mode`.

- No preset currently splits across GPUs. To split, override
  `device = CUDA0,CUDA1` + `split-mode = layer` + `tensor-split` in that preset.
- 27B split on the 1060 (~4.8 GiB) conflicts with mini E4B (~5.5 GiB): keep mini idle.
- Kmic KV: `q4_0`, `q8_0`, `f16` (no turbo). TheTom KV:
  `turbo6/5/4/3/2` (best compression), `q4_0`…`f16` also available.

---

## Hard-Won Rules

1. **CLI beats INI.** Only the `[*]` section is overridable per preset; put
   server-wide defaults in `[*]`, never `--device`/`--split-mode` in `command:`.
2. **Every INI section needs `model = /models/...`.** The section name is not
   mapped to `--model`; without it the child hangs "loading" forever.
3. **Router mode:** `--cache-type-k/v` and `--flash-attn` must stay in INI.
   Passing them on the compose command line crashes the parent.
4. **`ubatch-size` 2048 is current**, but 2048 + large ctx OOM'd the P100 before;
   drop to 512 if you see OOM.
5. **Use `--load-mode mlock`**, not deprecated `--no-mmap` + `--mlock`.
6. **Docker build cache trap:** `COPY` keeps timestamps; `touch` edited files
   or use `--no-cache` after manual source edits.
7. **Never lose TURBO code in merges (TheTom only).** After any merge verify:
   `type_traits[]` TURBO entries, `ggml_turbo_wht()`, `"TURBO_WHT"` in
   `GGML_OP_NAME[]`, CPU dispatch + `ops.cpp` impl, and brace balance in
   `ggml/src/ggml-cuda/fattn.cu`. Missing traits = SIGSEGV on model load.
8. **Check `GGML_OP_COUNT` / `RPC_PROTO_PATCH_VERSION`** after merges that add ops.
9. **Verify arch:** `docker run --rm --entrypoint /app/llama-server IMG --version`.
   The Kmic image is sm_60-only; TheTom is `60;61`.
10. **Kmic build arch is `60` only.** `CUDA_DOCKER_ARCH="60;61"` compiles but
    silently disables the P100 tuning (`__CUDA_ARCH_LIST__ == 600`).
11. **Kmic has no TurboQuant.** Use `q4_0`/`q8_0`/`f16`; `turbo*` throws.
12. **`<algorithm>` patch:** `source-kmic-68/src/llama-context.cpp` needs the
    include on GCC 14. `script/build-kmic.sh` adds it and forces `--no-cache`.
13. **Qwen3.5-MoE + fused GDN on sm_60:** the fused-cache kernel faults
    (`ggml_cuda_op_gated_delta_net_fused_cache`). `script/build-kmic.sh`
    disables fused GDN for `LLM_ARCH_QWEN35MOE` only. Do not remove that guard
    without testing `agents-a1-IQ4_XS-MTP-graft-headQ6.gguf`.

---

## Update Protocol (condensed)

0. **Decide which fork:** Kmic (`source-kmic-68/`, primary/P100) or TheTom
   (`source-thetom/`, mini/rollback). Does it fix a problem you have? Is the
   diff small in `ggml-alloc.c`, `ggml-cuda/`, `llama-kv-cache.cpp`, `arg.cpp`,
   `server.cpp`? Has the fork re-anchored upstream? If not, skip.
1. **Backup:** tag the running image, copy compose to `compose-backup/`,
   record `git log -1 --oneline` to `.backup_head`.
2. **Fetch + diff** before merging; flag TURBO removals (TheTom) and OP_COUNT changes.
3. **Pull/merge** in the matching source dir; TheTom: server files → theirs,
   TQ core → ours.
4. **Audit symbols/braces** (see rule 7, TheTom).
5. **Build** with the correct arch: Kmic `CUDA_DOCKER_ARCH=60`; TheTom
   `"60;61"` (add `--no-cache` after merges). Prefer `script/build-kmic.sh` /
   `script/build-thetom.sh`.
6. **Smoke test** at small ctx, then the tightest model at full ctx.
7. **Deploy only the affected service:** update its `image:` and
   `docker compose up -d --force-recreate <service>`, check `/health`, then
   `nvidia-smi`.
8. **Rollback:** restore compose backup and restart; anchors are
   `stable-2026-10-31` (TheTom) and the pre-Kmic compose backup.

```bash
# Primary (Kmic) rollback to TheTom
cp compose-backup/docker-compose-2026-10-31-pre-kmic.yml docker-compose.yml
docker compose up -d --force-recreate llama-server
# anchor: llama-server:stable-2026-10-31 (= thetom-oct29)

# Generic rollback
docker tag llama-server:stable-YYYY-MM-DD llama-server:latest
cp compose-backup/docker-compose-YYYY-MM-DD-pre-update.yml docker-compose.yml
docker compose up -d --force-recreate llama-server llama-server-mini
```

---

## History (brief)

| Date | Event |
|---|---|
| 2026-08-15 | Consolidated to `llama-server:thetom-aug14`; deleted older images |
| 2026-08-05 | Promoted TheTom fork: +1.9% avg; per-preset multi-GPU split |
| 2026-07-26 | July 26 merge caused P100 VRAM regression → rolled back to July 6 |
| 2026-07-06 | Merged upstream fully (0 behind); fixed `fattn.cu` brace bug, ubatch 2048→512 |
| 2026-10-18 | `thetom-oct18` from `ca28b4bc0` |
| 2026-10-29 | `thetom-oct29` from `643956891` (turbo5/6, Spark 2.5) |
| 2026-10-31 | Primary → Kmic-68 `7461904db` (`kmic-p100-2026-10-31`), q4_0 KV; ~2.1x prefill / ~1.6x decode vs TheTom on Swift-27B @ 64k |
| 2026-10-31 | Kmic fused-GDN guard → `kmic-p100-2026-10-31-gdnfix`; qwen35moe agents-a1 now runs on P100 |
| 2026-11-06 | Primary → Kmic-68 `83a7f0839` (`kmic-p100-nov6`); 15 upstream commits ahead of `7461904db`, MTP stop-rule tables +3–7% t/s, GDN crash fix, sm_60 IQ2/IQ3 grids; `<algorithm>` include merged upstream (fused-GDN guard still local-only) |
