#!/usr/bin/env bash
# bench-sweep-nmax.sh — sweep spec-draft-n-max/min for DSpark/MTP on P100/1060
# built from source-thetom/build/bin/llama-bench (CUDA 60;61)
# usage: ./script/bench-sweep-nmax.sh [--model MODEL] [--draft DRAFT] [--type TYPE] [--device 0|1]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH="$ROOT/source-thetom/build/bin/llama-bench"
[[ -x "$BENCH" ]] || { echo "missing $BENCH — run: docker build bench (see docs/llama-bench.md)"; exit 1; }

MODEL="${1:-/models/LFM2.5-2.6B-Q8_0.gguf}"
DRAFT="/models/LFM2.5-2.6B-DSpark-Q8_0.gguf"
TYPE="draft-dspark"
DEVICE=""  # auto (both GPUs). Use --device CUDA0 for P100, CUDA1 for 1060
N_PROMPT=512
N_GEN=128
REPS=3
THREADS=4

# parse opts
while [[ $# -gt 0 ]]; do case "$1" in
  --model) MODEL="$2"; shift 2;;
  --draft) DRAFT="$2"; shift 2;;
  --type) TYPE="$2"; shift 2;;
  --device) DEVICE="$2"; shift 2;;
  -p) N_PROMPT="$2"; shift 2;;
  -n) N_GEN="$2"; shift 2;;
  -r) REPS="$2"; shift 2;;
  *) shift;;
esac; done

# detect host device if running inside docker-wrapped bench
export LD_LIBRARY_PATH="$ROOT/source-thetom/build/bin:$LD_LIBRARY_PATH"

# build sweep list — keep short for quick (edit to taste)
N_MAX_LIST=(2 3 4 6 9)
N_MIN_LIST=(0 1 2)

OUT="$ROOT/bench-sweep-$(date +%m%d-%H%M).csv"
echo "n_max,n_min,model,draft,pp_tps,tg_tps" | tee "$OUT"

# baseline (no draft) for reference
echo "=== BASELINE (no draft) ===" | tee -a "$OUT"
BASE_TG=$($BENCH -m "$MODEL" -ngl -1 -t $THREADS -fa on -p $N_PROMPT -n $N_GEN -r $REPS -o csv 2>&1 | awk -F, '/tg/{print $NF}' | tail -1)
BASE_PP=$($BENCH -m "$MODEL" -ngl -1 -t $THREADS -fa on -p $N_PROMPT -n $N_GEN -r $REPS -o csv 2>&1 | awk -F, '/pp/{print $NF}' | tail -1)
echo "0,0,$MODEL,none,$BASE_PP,$BASE_TG" | tee -a "$OUT"

for MAX in "${N_MAX_LIST[@]}"; do
  for MIN in "${N_MIN_LIST[@]}"; do
    [[ $MIN -gt $MAX ]] && continue
    # DSpark block_size=9, so MAX>9 is clamped anyway
    echo "=== n_max=$MAX n_min=$MIN ===" | tee -a /tmp/bench.log
    DEV_ARGS=(); [[ -n "$DEVICE" ]] && DEV_ARGS=(--device "$DEVICE")
    # capture csv
    CSV=$($BENCH -m "$MODEL" --model-draft "$DRAFT" --spec-type "$TYPE" \
      --spec-draft-n-max "$MAX" --spec-draft-n-min "$MIN" \
      -ngl -1 -t $THREADS -fa on -c 4096 -ub 512 -p $N_PROMPT -n $N_GEN -r $REPS -o csv "${DEV_ARGS[@]}" 2>&1 | tee /tmp/b.csv; cat /tmp/b.csv)
    TG=$(awk -F, '/tg/ {print $NF}' /tmp/b.csv | tail -1)
    PP=$(awk -F, '/pp/ {print $NF}' /tmp/b.csv | tail -1)
    [[ -z "$TG" ]] && TG="ERR"
    [[ -z "$PP" ]] && PP="ERR"
    echo "$MAX,$MIN,$MODEL,$DRAFT,$PP,$TG" | tee -a "$OUT"
    # also pretty
    echo "  -> pp $PP tg $TG"
  done
done

echo ""
echo "Done. Results: $OUT"
column -t -s, "$OUT" 2>/dev/null || cat "$OUT"
BEST=$(sort -t, -k6 -nr "$OUT" | head -1)
echo ""
echo "Best tg: $BEST"
echo "Apply to models/modelg.ini:"
echo "[LFM2.5-2.6B-Q8_0.gguf]"
echo "spec-draft-n-max = $(echo $BEST | cut -d, -f1)"
echo "spec-draft-n-min = $(echo $BEST | cut -d, -f2)"
