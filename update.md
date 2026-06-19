# History & Cleanup Guide for llmaCPP

## Timeline
- **May 8‑9, 2026** – Clone llama.cpp into `/source/`; add `origin` (official) and `atomic` (turboquant fork). First commit includes a full compose with build step.  
- **June 1, 2026** – Moved compose out of `source/`. Removed the `build:` target, copied the new file to repo root, and archived the old version in `compose-backup/`.  
- **June 12, 2026** – Switched frontend from `llmWEB` to `llmMobile`.

## Updating Source Code & Rebuilding Server
```bash
cd /home/nui/llmaCPP/source
git checkout atomic/feature/turboquant-kv-cache   # or another branch
docker build --no-cache -t llama-server:latest \
  --target server \
  -f .devops/cuda.Dockerfile .
```
Redeploy:
```bash
cd /home/nui/llmaCPP
docker compose up -d --force-recreate llama-server
docker compose logs -f llama-server
```

## Redeploying the Container
1. Edit `/home/nui/llmaCPP/docker-compose.yml` if you change model paths, GPU layers, etc.  
2. Verify new model files are in `/models/`.  
3. Restart services: `docker compose up -d --force-recreate llama-server`.  
4. Check logs: `docker compose logs -f llama-server`.

Keep archived configs in `compose-backup/` and name them descriptively (e.g., `docker-compose-<model>-vX.yml`).