# TODO — TheTom/llama-cpp-turboquant Experiment

> ## ✅ STATUS (2026-08-05): PROMOTED — TheTom is the new workhorse
> The stack is LIVE on `llama-server:latest` (= TheTom `218fa988d87d`, formerly `:thetom`).
> `docker-compose.override.yml` removed; both servers healthy (200/200).
> Benchmark: net +1.9% avg; LOW 27B split @ 64K = 21.85 t/s (+154% vs spill baseline).
> Snapshots kept: `stable-2026-08-05` (TheTom) + `stable-2026-07-26` (old baseline, rollback path).
> Quick verify: `curl localhost:8080/health` + `curl localhost:8081/health` → 200.

**Goal:** Clone `TheTom/llama-cpp-turboquant` into a sister folder next to `./source/`,
build a new `llama-server` binary/image with the needed CUDA flags, swap the primary
+ secondary containers to it for testing, keep it if good, roll back instantly if not.

**Strategy:** Docker image with a distinct tag (`llama-server:thetom`) + auto-merged
`docker-compose.override.yml` swap. `latest` is never touched, so rollback is a
one-command delete of the override file.

**Baseline reference:** update.md — current branch `turboquant-merged-2026-07-06`
(commit `797cf14a2`), image `llama-server:latest` (7.04 GB).
**Update after Phase 0 recon:** TheTom is NOT an old drop-in — it is actively
maintained (`d0e2a8b64`, ~Aug 2026) and supports Gemma 4, qwen35moe, MTP,
router mode, and the same turbo2/3/4 cache types as the current stack.

---

## Phase 0 — Recon (zero risk, stack untouched) ✅ DONE

- [x] Tag current image as stable snapshot
      `llama-server:stable-2026-07-26` (same ID 631b56ff03c4 as latest)
- [x] Clone TheTom fork into sister folder
      `source-thetom/` @ `d0e2a8b64` on `feature/turboquant-kv-cache` (active)
- [x] Add `source-thetom/` to `.gitignore`
- [x] Compatibility greps — see findings log below
- [x] Verify cache-type names: `turbo2` / `turbo3` / `turbo4` accepted
      (kv_cache_types[] in common/arg.cpp; type_traits in ggml.c L767-790)
- [x] Pick test model(s): `gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf` (primary, gemma4),
      `agents-a1-IQ4_XS-MTP-graft-headQ6.gguf` (secondary, qwen35moe)
- [x] **Decision gate: GO** — all model families supported; abort if build/smoke fails

## Phase 1 — Build + smoke test (zero risk, stack untouched) ✅ DONE

- [x] Build image from sister folder → `llama-server:thetom` (7.04 GB, ~9 min build)
- [x] Check binary flags — all match current stack spellings:
      `--flash-attn on|off|auto`, `--cache-type-k/v`, `--models-preset` (router),
      `--spec-type draft-mtp`, `--n-gpu-layers`, `--alias`, draft cache types
- [x] Smoke test primary model `gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf` @ ctx=4096
      → HTTP 200 + real chat completion (reasoning model, content in reasoning_content)
- [x] Smoke test secondary model `agents-a1-IQ4_XS-MTP-graft-headQ6.gguf` @ ctx=4096
      → HTTP 200, model loaded cleanly
- [x] **Decision gate: GO** — both models load with turbo4/turbo2; stack untouched
      (live stack still `latest`, healthy 4h)

## Phase 2 — Swap + full VRAM test ✅ DONE

- [x] Write `/home/nui/llmaCPP/docker-compose.override.yml` (image-only swap; command unchanged
      because TheTom has router mode + all same flags)
- [x] `docker compose up -d --force-recreate llama-server llama-server-mini`
      → both healthy (200/200), confirmed on `llama-server:thetom`
- [x] Full VRAM test @ ctx=65536 (turbo4/turbo2) — see findings log for table
- [x] Functional test: chat completion through router API works (E4B served, reasoning_content)
- [ ] Quick benchmark (optional): tokens/s + stability over a longer session

## Phase 3 — Keep or rollback ✅ PROMOTED (2026-08-05)

- [x] **DECISION (2026-08-05): PROMOTE** — TheTom is the new workhorse; override removed
- [x] Revisit stability/perf (benchmark via llm-mobile + multi-GPU split tests) → PASS
- [x] **Keep:** tag release, promote, clean up
      ```bash
      docker tag llama-server:thetom llama-server:stable-2026-08-05   # done
      docker tag llama-server:thetom llama-server:latest               # done (path A)
      rm docker-compose.override.yml                                   # done
      docker compose up -d --force-recreate llama-server llama-server-mini  # done, healthy
      ```
      - [x] update `update.md` (new baseline section 2026-08-05) + this TODO marked complete
      - [x] decide fate of `source-thetom/` → **KEEP as reference** (binary built from it; `stable-2026-07-26` retained for rollback)
- [ ] **Rollback (instant):**
      ```bash
      rm /home/nui/llmaCPP/docker-compose.override.yml
      cd ~/llmaCPP
      docker compose up -d --force-recreate llama-server llama-server-mini
      sleep 15
      curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/health
      curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/health
      # `latest` was never touched → this restores the exact previous state
      ```
- [ ] If experiment failed: delete `llama-server:thetom` image + `source-thetom/` folder

---

## Findings log (fill in as you go)

| Date | Phase | Finding / decision |
|---|---|---|
|  | 0 | Stable image tagged `llama-server:stable-2026-07-26` |
|  | 0 | Cloned `source-thetom/` @ `d0e2a8b64` (feature/turboquant-kv-cache, active) |
|  | 0 | Gemma 4 SUPPORTED: `LLM_ARCH_GEMMA4` + `GEMMA4_ASSISTANT` |
|  | 0 | agents-a1 (qwen35moe) SUPPORTED: `LLM_ARCH_QWEN35MOE` (llama-arch.cpp L42) |
|  | 0 | Turbo cache types `turbo2/3/4` + type_traits present (ggml.c L767-790); TURBO_WHT op present |
|  | 0 | MTP + `--models-preset` (router) + `--mmproj` all supported |
|  | 0 | `.devops/cuda.Dockerfile` byte-identical to current pipeline |
|  | 0 | Model decode: gemma4 ftype=2 (Q4_0, "Q4_K_XL" is quantizer label); agents-a1 = qwen35moe |
|  | 0 | **DECISION: GO** — all model families supported; abort if build/smoke fails |
|  | 1 | Built `llama-server:thetom` (~9 min, 7.04 GB); all CLI flags match current stack |
|  | 1 | Smoke E4B: HTTP 200 + working completion; Smoke agents-a1: HTTP 200, clean load |
|  | 1 | **DECISION: GO** — proceed to Phase 2 swap |
|  | 2 | Swapped via image-only override; both servers healthy on thetom |
|  | 2 | VRAM @ctx=65536 P100: E4B 4,959 | 12B 7,911 | agents-a1 14,799 | 26B 15,249 MiB (all fit; 26B tight) |
|  | 2 | VRAM @ctx=65536 1060: E4B 5,241 | E2B 4,295 MiB (both fit 6GB) |
|  | 2 | TheTom VRAM ≤ atomic baseline across all models (e.g. 26B 15,249 vs 15,695) |
|  | 2 | Router mode fully functional; chat completion served (build b10281-d0e2a8b64) |
|  | 3 | **2026-08-03: KEEP TESTING** — override stays; revisit ~2026-08-05/06 for PROMOTE vs ROLL BACK |
|  | 3 | **2026-08-05: BENCHMARK done (llm-mobile)** — see table.txt: net speed +1.9% avg (10 models) |
|  | 3 | Bench gains: agents-a1 +12.47%, gemma-4-e4b +11.03%, gemma-4-12b +3.57%, nemotron-30b +2.35% |
|  | 3 | Bench neutral: gemma-4-e2b 0.00%, gemma-4-26b-mtp +0.49%, qwen3.5-9b +0.54% |
|  | 3 | Bench regressions: gemma-4-26b-UD −9.34% (MTP variant available @91.0), nemotron-12b −1.16%, ornith −0.89% |
|  | 3 | Scores unchanged (speed-only diffs); VRAM still ≤ baseline. Leaning PROMOTE; user keeps testing |
|  | 3 | **2026-08-05: Multi-GPU split experiment (Option A)** — mini parked; primary on P100+1060 |
|  | 3 | Config: `--device CUDA0,CUDA1 --split-mode layer --tensor-split 5,1 --main-gpu 0` (compose-backup/docker-compose-multigpu-split.yml) |
|  | 3 | 27B presets: `c = 32768` + `ubatch-size = 512` (64K ctx + ubatch 2048 OOM'd the 1060; 5:1 needed) |
|  | 3 | Split loads + serves Qwen3.6-27B IQ4_XS: 11.4 t/s (no MTP) vs 8.6 t/s single-P100 spill = **+33%**; 14.3 t/s with MTP |
|  | 3 | Caveats: 1060 at 6013/6065 MiB (tight, no 64K ctx headroom); PCIe (PHB, no P2P) bottlenecks → low util (39/56%) |
|  | 3 | **LOW variant offers more room**: same 27.3B params, compact 15.13GB IQ4_XS file (non-LOW 17.04GB) |
|  | 3 | LOW loads @ 65536 ctx on 5:1 split; 1060 headroom 1.4GB (vs 54MiB); bench **21.85 t/s gen w/ MTP** |
|  | 3 | 8.6 (base spill) → 11.4 (split 32K) → 21.85 t/s (LOW split 64K) = **+154%** end-to-end |
|  | 3 | Non-LOW 27B presets keep c=32768 (can't do 64K on 6GB card); LOW preset at c=65536 |
|  | 3 | Split made PER-PRESET (not global): single-GPU default lives in INI [*] (device=CUDA0, split-mode=none); 27B presets override to CUDA0,CUDA1 + layer + tensor-split 5,1 → small models run unsplit, no PCIe tax |
|  | 3 | Key lesson: CLI command args BEAT INI presets; only [*] INI section is overridable per-model → defaults belong in [*], not the compose command |
|  | 3 | Verified: LOW splits (P+1060), gemma-4-E4B stays single-P100 |
|  | 3 | **Coexistence rule (verified):** primary single-GPU + mini E4B on 1060 works (P100 5.8GB / 1060 5.5GB, both 200). Primary 27B split (4.8GB on 1060) + mini = CONFLICT (6GB card) → park mini for 27B sessions |
|  | 3 | Routers don't coordinate; loading 27B split while mini serves → primary 500. Mini left RUNNING (2026-08-05) |
|  | 3 | |
