# History & Cleanup Guide for llmaCPP

## How It Started (Timeline)

### Phase 1 — Initial Setup (~May 8-9, 2026)
- Cloned llama.cpp source into `/home/nui/llmaCPP/source/`. This fork (turboquant) has **two remotes**: `origin` (upstream official llama.cpp) and `atomic` (your turboquant fork). Current commit is `6d7eb8c5a`.
- Created the first `docker-compose.yml` inside `source/`, with a **full build step** (`build:` context pointing to `.devops/cuda.Dockerfile`) for compiling llama.cpp from source, plus both `llama-server` and `llm-manager` services.

### Phase 2 — Moved Compose Out of Source (~June 1, 2026)
- Realized building from source takes too long. Removed the `build:` step for llama-server (it was always a pre-built image anyway).
- Copied docker-compose.yml out of `source/` into the repo root `/home/nui/llmaCPP/docker-compose.yml`.
- The old version with build steps was saved as `compose-backup/docker-compose-gemma4-26b.yml`.
- Created `compose-backup/` folder with archival copies of old configs.
- Made the first commit (`b242892`) — this only committed `docker-compose.yml` and backup files. **The `source/` directory was never committed** (it's always been git-ignored).

### Phase 3 — llm-manager → llm-mobile (~June 12, 2026)
- Developed the mobile frontend (`llmMobile`) as a replacement for `llmWEB`.
- Updated docker-compose to use `build: /home/nui/dev/llmMobile` instead of `/home/nui/dev/llmWEB`.

---

## What Happened with source/ — Clarification

**The `source/` directory itself was never committed.** The `.gitignore` has always excluded it. Your concern about "mistakenly committing docker-compose.yml when it was in the source folder" is understandable, but checking git history confirms:
- The first commit only added `docker-compose.yml` (in the root) and backup files — no files from inside `source/`.

**However**, your concern about the original docker-compose setup is valid — the `compose-backup/docker-compose-gemma4-26b.yml` file was originally **inside** `source/` as `docker-compose.yml`. At that time, it had a full **build step**: `build:` context pointing to `.devops/cuda.Dockerfile`, building llama.cpp from source on your machine. That's what you meant by mistakenly committing docker-compose when it was in source — the *concept* of building from source DID exist there first before being moved out and stripped.

---

## Current State of Things

### source/ folder is stale
The `llama.cpp` clone in `/home/nui/llmaCPP/source/` is at commit `6d7eb8c5a` (May 28, 2026). It has local modifications:
- Deleted files from a previous compose change (`docker-compose-gemma4-26b.yml`, `docker-compose.yml`) — these are the backup configs that got moved out of source/ into `compose-backup/`.

### docker-compose evolution
| Version | llama-server | llm-manager / llm-mobile | Notes |
|---|---|---|---|
| Oldest (in compose-backup) | pre-built image, single model (`-m`), build step for manager | `build: /home/nui/dev/llmWEB` | Both services active |
| First commit to repo | same as above | same as above | `source/docker-compose.yml` was moved out of source/ |
| Current (root docker-compose.yml) | pre-built image, models-preset (`--models-preset /models/models.ini`) | **commented out** — replaced by llm-mobile at `build: /home/nui/dev/llmMobile` | Only llama-server + llm-mobile active |

---

## How to Update llama.cpp Source & Rebuild Server Container

**Current state**: Your local `source/` is at commit `6d7eb8c5a`, which is **473 commits behind** `atomic/master` (your turboquant fork). That's a lot — not ~30 as you estimated.

### Step 1: Clean up local changes in source/
The old docker-compose files you moved out of source/ are showing as deleted. Let's restore them first so we have a clean slate:
```bash
cd /home/nui/llmaCPP/source

# Restore the deleted compose files (they were already moved out, just undo the git deletion)
git checkout -- docker-compose-gemma4-26b.yml docker-compose.yml

# Clean up untracked junk that shouldn't be there from source/
rm -rf .antigravitycli/
```

### Step 2: Fetch latest turboquant changes
Your repo has **two remotes** — `origin` (upstream official llama.cpp) and `atomic` (your turboquant fork). Since you want the latest turboquant features:
```bash
cd /home/nui/llmaCPP/source
git fetch atomic master
```
This pulls down all new commits from your turboquant fork without modifying anything yet.

### Step 3: Reset to the latest turboquant commit
Since you have no local C++ code modifications (just leftover docker-compose files), a hard reset is the safest approach:
```bash
cd /home/nui/llmaCPP/source
git reset --hard atomic/master
```
**Why `--hard`?** Because your only local changes are leftover docker-compose files from when you first moved them out of source/. There's no custom C++ code or other modifications to preserve. A hard reset puts you exactly at the same point as the turboquant fork.

### Step 4: Verify the update
```bash
cd /home/nui/llmaCPP/source
git log --oneline -5        # Confirm you're now on atomic/master HEAD
ls .devops/cuda.Dockerfile   # Make sure build files are still there
```

### Step 5: Rebuild the llama-server Docker image
Now that source is up to date, rebuild from source. The `cuda.Dockerfile` uses CUDA arch `60`, which targets Pascal architecture (GTX 10xx series) — make sure this matches your GPU:
```bash
cd /home/nui/llmaCPP/source

# Rebuild the llama-server image from source
docker build -t llama-server:latest \
  --target server \
  --build-arg CUDA_DOCKER_ARCH=60 \
  -f .devops/cuda.Dockerfile .
```
**Note**: This will take a while since it's compiling from source. The Dockerfile builds in stages:
1. **`build` stage**: Compiles llama.cpp with CUDA support, extracts `.so` libraries
2. **`server` stage**: Minimal runtime image with just `llama-server`

### Step 6: Redeploy the server
After the build finishes, your `docker-compose.yml` should already use `image: llama-server:latest` for llama-server (no build step), so it'll pick up the new image. Just restart:
```bash
cd /home/nui/llmaCPP
# Restart the server with the new binary:
docker compose stop llama-server
docker compose up -d --force-recreate llama-server
```

### Summary of what this does
| Step | Action | Why |
|---|---|---|
| 1 | Clean local changes | Remove stale docker-compose files and junk from source/ |
| 2 | Fetch latest from `atomic` remote | Get all new turboquant commits without changing anything yet |
| 3 | Hard reset to `atomic/master` | Jump to the latest turboquant commit (safe since no custom C++ code) |
| 4 | Verify | Confirm update succeeded and build files are intact |
| 5 | Rebuild Docker image | Build new llama-server binary from updated source with CUDA support |
| 6 | Redeploy server | Restart server with the new binary |

---

## Summary

- **No data was accidentally committed** — source/ has always been git-ignored.
- The only "mistake" was the *concept* of building from source when it lived inside `source/docker-compose.yml`. That's now gone since you use pre-built Docker images.
- The source/ folder is stale (473 commits behind turboquant fork) — follow the update steps above if you want to bring it current and rebuild.
