# llama-bench — Quick Tuning for `spec-draft-n-max/min`

Offline throughput tester. Unlike `speed-bench` (needs running `llama-server`), `llama-bench` loads `target+draft` directly — best for sweeping `n_max/n_min` in 30s per point.

> Server image `llama-server:thetom-aug29` is `target server` only and has no `llama-bench` binary. Build it from `source-thetom`.

## 1. Build (once)

**Fish** needs `(nproc)` not `$(nproc)` and `cmake` must be installed. Easiest is Docker (no local CUDA/cmake):
```bash
# already built for you at source-thetom/build/bin/llama-bench (60;61) on 2026-08-29
ls -lh source-thetom/build/bin/llama-bench
```
Rebuild:
```bash
# bash (not fish) — GGML_NATIVE=OFF is required with BACKEND_DL
bash -c 'cd source-thetom && cmake -B build -DGGML_NATIVE=OFF -DGGML_CUDA=ON -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON -DCMAKE_CUDA_ARCHITECTURES="60;61" && cmake --build build --target llama-bench -j$(nproc)'
# fish:
# cd source-thetom; cmake -B build -DGGML_NATIVE=OFF -DGGML_CUDA=ON -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON -DCMAKE_CUDA_ARCHITECTURES="60;61"; cmake --build build --target llama-bench -j (nproc)
# docker (if cmake missing):
docker run --rm -v $PWD/source-thetom:/src -w /src nvidia/cuda:12.8.1-devel-ubuntu24.04 bash -c 'apt update -qq && apt install -y cmake build-essential -qq && cmake -B build -DGGML_NATIVE=OFF -DGGML_CUDA=ON -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON -DCMAKE_CUDA_ARCHITECTURES="60;61" && cmake --build build --target llama-bench -j$(nproc)'
```
`source-thetom/build` is git-ignored, `LD_LIBRARY_PATH=source-thetom/build/bin` is set by wrapper scripts.

## 2. Single Run

```bash
# baseline (no draft) — note your 77/40 t/s reference
./build/bin/llama-bench \
  -m /models/LFM2.5-2.6B-Q8_0.gguf -ngl -1 -t 4 -fa on \
  -p 512 -n 128 -r 5 -o md

# DSpark draft
./build/bin/llama-bench \
  -m /models/LFM2.5-2.6B-Q8_0.gguf \
  --model-draft /models/LFM2.5-2.6B-DSpark-Q8_0.gguf \
  --spec-type draft-dspark --spec-draft-n-max 4 --spec-draft-n-min 1 \
  -ngl -1 -t 4 -fa on -p 512 -n 128 -r 5 -o md
# pp = prompt processing t/s, tg = token generation (decode) t/s
```

For MTP (`gemma-4`) replace `--spec-type draft-mtp --spec-draft-n-max 4`.

All flags are same as `llama-server` docs (`--cache-type-k`, `--ubatch-size`, `--threads`, etc. are forwarded via `common_params`).

## 3. Sweep `n_max / n_min` Quickly

`llama-bench` has no native range for `spec-draft-n-max`, so loop it. This is the fastest way to find the knee for your P100/1060:

```bash
#!/usr/bin/env bash
# sweep.sh — test LFM2.5-DSpark n_max 2..9 on GTX1060 (mini) or P100
MODEL=/models/LFM2.5-2.6B-Q8_0.gguf
DRAFT=/models/LFM2.5-2.6B-DSpark-Q8_0.gguf
OUT=bench-dspark-$(date +%m%d-%H%M).csv

echo "n_max,n_min,tg_t/s,pp_t/s" | tee $OUT
for MAX in 2 4 6 9; do
  for MIN in 0 1 2; do
    [[ $MIN -gt $MAX ]] && continue
    echo "--- n_max=$MAX n_min=$MIN ---"
    ./build/bin/llama-bench \
      -m $MODEL --model-draft $DRAFT --spec-type draft-dspark \
      --spec-draft-n-max $MAX --spec-draft-n-min $MIN \
      -ngl -1 -t 4 -fa on -c 4096 -ub 512 \
      -p 512 -n 128 -r 3 -o csv 2>&1 | tee /tmp/b.csv
    TG=$(awk -F, '/tg128/{print $NF}' /tmp/b.csv | tail -1)
    PP=$(awk -F, '/pp512/{print $NF}' /tmp/b.csv | tail -1)
    echo "$MAX,$MIN,$TG,$PP" | tee -a $OUT
  done
done
cat $OUT | column -t -s,
# pick max tg_t/s row — that’s your best draft depth for this model/GPU
```

**One-liner for your current 36/28 vs 77/40 case:**

```bash
for N in 2 3 4 5 6 9; do echo "== $N =="; ./build/bin/llama-bench -m /models/LFM2.5-2.6B-Q8_0.gguf --model-draft /models/LFM2.5-2.6B-DSpark-Q8_0.gguf --spec-type draft-dspark --spec-draft-n-max $N --spec-draft-n-min 1 -p 512 -n 128 -r 3 -o md | grep -E "tg|pp"; done
```

> Tip: Your `modelg.ini` already has `spec-draft-n-max=2 spec-draft-n-min=1` after the last edit — that’s the current best for 2.6B on 1060. Sweep `2,3,4` only; `9` is slower (as you saw).

## 4. Output

* Default `-o md` — markdown table with `pp tg t/s ±`
* `-o csv/json/sql` — machine parsable; `sqlite3` import: `./build/bin/llama-bench -o sql | sqlite3 bench.sqlite`
* `llm_bench.db` (10575) is the project’s SQLite store — append via `-o sql` if you want history.

## 5. When to Use `speed-bench` Instead

`llama-bench` gives raw `tg`, not draft `accept_rate`. If `tg` is flat across `n_max`, check `accept_rate`:

```bash
# needs running server
python tools/server/bench/speed-bench/speed_bench.py --url localhost:8081 --bench qualitative --category coding --osl 128 --limit 8 --output /tmp/s.json
cat /tmp/s.json | grep accept_rate
```

`accept_rate = accepted/drafted`. If `<0.4` for `n=9` but `~0.7` for `n=2`, the smaller draft wins — matches your 77→36 slowdown.

## 6. Gotchas

* Keep `-c`/`--ubatch-size` same as `modelg.ini` (`4096`/`512` for 2.6B) or you’ll OOM the 6 GB card.
* Always `-ngl -1` (offload all) on P100/1060.
* Warmup: default 1 token; for short `n=128` keep it, for noisy runs add `-r 5 --delay 2`.
* Router mode flags (`--cache-type-k turbo4`) go in INI; `llama-bench` reads them via CLI too.
