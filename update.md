# llmaCPP Source Update Log

## Current State — 2026-10-29

| Item | Value |
|---|---|
| Source | `source-thetom/` @ `feature/turboquant-kv-cache`, commit `643956891` |
| Image in use | `llama-server:thetom-oct29` (both services) |
| Previous image | `llama-server:thetom-oct18` (rollback anchor) |
| Primary | `llama-server` → `llm-server`, port 8080, GPUs 0+1 |
| Secondary | `llama-server-mini` → `llm-server-mini`, port 8081, GPU 1 |
| GPUs | 0 = Tesla P100 16 GB (sm_60), 1 = GTX 1060 6 GB (sm_61) |
| Build arch | `CUDA_DOCKER_ARCH="60;61"` — Pascal only |

> `source/` no longer exists. Never build from `source-atomic/` (test only).
> `source-thetom/` is the only build source.

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

## Current Config

Both servers run router mode with `--models-preset`, `--flash-attn on`,
`--load-mode mlock`, `-np 1`, `--models-max 1`, `--tools all`.
Model-level flags live in the INI files, not `command:`.

`models.ini` / `modelg.ini` `[*]` defaults:

```ini
c = 65536
n-gpu-layers = -1
ubatch-size = 2048
cache-type-k = turbo4
cache-type-v = turbo2
device = CUDA0        # models.ini only
split-mode = none     # models.ini only
main-gpu = 0
```

- No preset currently splits across GPUs. To split, override
  `device = CUDA0,CUDA1` + `split-mode = layer` + `tensor-split` in that preset.
- 27B split on the 1060 (~4.8 GiB) conflicts with mini E4B (~5.5 GiB): keep mini idle.
- KV types: `turbo6/5/4/3/2` (best compression), `q4_0`…`f16` also available.

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
7. **Never lose TURBO code in merges.** After any merge verify:
   `type_traits[]` TURBO entries, `ggml_turbo_wht()`, `"TURBO_WHT"` in
   `GGML_OP_NAME[]`, CPU dispatch + `ops.cpp` impl, and brace balance in
   `ggml/src/ggml-cuda/fattn.cu`. Missing traits = SIGSEGV on model load.
8. **Check `GGML_OP_COUNT` / `RPC_PROTO_PATCH_VERSION`** after merges that add ops.
9. **Verify arch:** `docker run --rm --entrypoint /app/llama-server IMG --version`.
   Builds with `60;61` will not run on newer cards (and vice versa).

---

## Update Protocol (condensed)

0. **Decide:** does it fix a problem you have? Is the diff small in
   `ggml-alloc.c`, `ggml-cuda/`, `llama-kv-cache.cpp`, `arg.cpp`, `server.cpp`?
   Has the fork re-anchored upstream? If not, skip.
1. **Backup:** tag the running image, copy compose to `compose-backup/`,
   record `git log -1 --oneline` to `.backup_head`.
2. **Fetch + diff** before merging; flag TURBO removals and OP_COUNT changes.
3. **Pull/merge** in `source-thetom/`; resolve server files → theirs, TQ core → ours.
4. **Audit symbols/braces** (see rule 7).
5. **Build** with `--build-arg CUDA_DOCKER_ARCH="60;61"` (add `--no-cache` after merges).
6. **Smoke test on both GPUs** at small ctx, then the tightest model at full ctx.
7. **Deploy:** update `image:` in both services, `docker compose up -d --force-recreate`,
   check `/health` on 8080 and 8081, then `nvidia-smi`.
8. **Rollback:** retag the stable image, restore compose backup, restart.

```bash
# Rollback
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
