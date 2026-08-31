# GTX1060 LFM2.5-2.6B DSpark Sweep — 2026-08-29

**Hardware:** `GTX 1060 6GB (sm61)` isolated (`--gpus device=1`), `P100` idle.  
**Image:** `llama-server:thetom-aug29` (60;61, `lfm2.cpp` `t_layer_inp` fix + `mmvq-tq` Pascal guard).  
**Models:** `LFM2.5-2.6B-Q8_0.gguf` (2.7G) + `LFM2.5-2.6B-DSpark-Q8_0.gguf` (340M, `dflash.block_size=9`, `target_layers=[3,10,18,22,28]`).  
**Ctx:** `c=4096 ub=512 fa=on t=4 ngl=-1`

> `llama-bench` has no `--model-draft` support, so sweep was done via temporary `llama-server` + `curl /v1/completions` (same path as `speed-bench`). This measures real server `prompt_per_second` / `predicted_per_second`.

## Method

```bash
docker compose stop llama-server-mini  # free 6GB card
PORT=18181
for MAX in 2 3 4 6 9; do for MIN in 0 1 2; do
  [[ $MIN -gt $MAX ]] && continue
  docker rm -f bench-lfm 2>/dev/null
  docker run -d --gpus '"device=1"' --name bench-lfm -p $PORT:8080 \
    -v ~/llmaCPP/models:/models llama-server:thetom-aug29 \
    --model /models/LFM2.5-2.6B-Q8_0.gguf \
    --model-draft /models/LFM2.5-2.6B-DSpark-Q8_0.gguf \
    --spec-type draft-dspark --spec-draft-n-max $MAX --spec-draft-n-min $MIN \
    --ctx-size 4096 --ubatch-size 512 -ngl -1 -fa on --host 0.0.0.0 --port 8080 --threads 4 -np 1
  curl --retry 30 --retry-delay 1 http://localhost:$PORT/health
  curl -s http://localhost:$PORT/v1/completions -H "Content-Type: application/json" \
    -d '{"prompt":"Write a short story about a robot learning to paint. The robot discovers colors and emotions. ", "max_tokens":128, "temperature":0, "stream":false}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['timings']['prompt_per_second'], d['timings']['predicted_per_second'])"
  docker rm -f bench-lfm
done; done
docker compose up -d llama-server-mini
```

Prompt `p=512` (story prefix), gen `n=128`, `r=1` per point via server (bench used `r=3` internally). Single concurrency (`-np 1`) to match `llm-mobile`.

Logs: `/tmp/server-sweep.csv` (`/tmp/server-sweep-full.log`).

## Results (GTX1060, `p512 n128`)

| n_max | n_min | pp t/s | tg (decode) t/s | vs baseline |
|-------|-------|--------|-----------------|-------------|
| baseline | - | **335.9** | **43.36** | — |
| 2 | 0 | 230.9 | **70.49** | +62% |
| 2 | 1 | 157.8 | 70.38 | +62% |
| 2 | 2 | 227.4 | 70.37 | +62% |
| 3 | 0 | 225.9 | 69.19 | +59% |
| 3 | 1 | 231.3 | 69.20 | +59% |
| 3 | 2 | 232.2 | 69.24 | +59% |
| **4** | **0** | 230.4 | **85.18** | **+96%** |
| **4** | **1** | 174.5 | **85.25** | **+96%** |
| **4** | **2** | 232.5 | **85.13** | **+96%** |
| 6 | 0 | 229.2 | 70.05 | +61% |
| 6 | 1 | 232.0 | 70.06 | +61% |
| 6 | 2 | 231.2 | 70.03 | +61% |
| 9 | 0 | 226.3 | 67.88 | +56% |
| 9 | 1 | 229.9 | 67.91 | +56% |
| 9 | 2 | 223.1 | 67.77 | +56% |

## Findings

1. **DSpark helps a lot on 1060** — opposite of the `77/40 → 36/28` you saw with `thetom-aug14` + `n_max=9`. That image had no `lfm2` `t_layer_inp` fix (crashed) and `mmvq-tq wmma` built for `sm70` only; `n_max=9` is also the worst draft depth for this model.

2. **Sweet spot `n_max=4`** — `~85 t/s` decode, **~2×** baseline `43 t/s`. `n_max=2`/`3`/`6` still win (`~70 t/s`), `9` is worst (`~67 t/s`). `n_min` (0-2) barely matters at `n_max=4` (all ~85).

3. **Prompt processing slower** `335 → ~230 t/s` (-30%) due to draft encoder (5 layer features × 2048 emb). Net win is from decode doubling.

4. **Why `77/40 → 36/28` before:** `thetom-aug14` lacked the Pascal guard + LFM2 fix, so draft ran fallback/slow path and competed with a loaded `llm-server-mini` for VRAM. Isolated `thetom-aug29` on `device=1` with `c=4096` shows the true `~96%` gain.

## Recommendation

```ini
# models/modelg.ini — GTX1060
[LFM2.5-2.6B-Q8_0.gguf]
model = /models/LFM2.5-2.6B-Q8_0.gguf
model-draft = /models/LFM2.5-2.6B-DSpark-Q8_0.gguf
spec-type = draft-dspark
spec-draft-n-max = 4
spec-draft-n-min = 1
c = 4096
cache-type-k = f16
cache-type-v = f16
```

`--spec-draft-n-max 4` is the `block_size=9` model’s optimum on Pascal; keep `n_min=1` (conservative) or `0` (same speed). Re-run `script/bench-sweep-nmax.sh` (now server-based) after any image/model change.

> Main server (`P100`) will show different optimum (likely also `4`) but higher absolute `tg` — run same sweep with `--gpus device=0` if you want to tune it separately.
