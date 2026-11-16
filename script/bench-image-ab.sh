#!/usr/bin/env bash
# bench-image-ab.sh — A/B a llama-server image on one GPU using /completion timings.
#
# Starts a throwaway container, sends an identical cold-cache prompt set, and
# prints prompt/decode t/s per repetition. Results append to $OUT (TSV).
#
# Usage:
#   ./script/bench-image-ab.sh IMAGE GPU MODEL [extra llama-server args...]
#
# Env overrides:
#   PORT=8099 CTX=16384 UB=512 THREADS=8 CK=q4_0 CV=q4_0 REPS=3 PROMPT_TOKENS=3000
#   OUT=/tmp/bench-ab-results.tsv
#
# Example:
#   ./script/bench-image-ab.sh llama-server:kmic-nov9 0 /models/Swift-...gguf
#   CK=turbo4 CV=turbo2 ./script/bench-image-ab.sh llama-server:thetom-nov8 1 /models/gemma-...gguf \
#     -md /models/gemma-4-E4B-it-qat-mtp.gguf --spec-type draft-mtp --spec-draft-n-max 4

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${1:?image required}"; GPU="${2:?gpu index required}"; MODEL="${3:?model path required}"; shift 3

PORT="${PORT:-8099}"
CTX="${CTX:-16384}"
UB="${UB:-512}"
THREADS="${THREADS:-8}"
CK="${CK:-q4_0}"
CV="${CV:-q4_0}"
REPS="${REPS:-3}"
PROMPT_TOKENS="${PROMPT_TOKENS:-3000}"
OUT="${OUT:-/tmp/bench-ab-results.tsv}"
NAME="bench-ab-$$"
REQ="/tmp/bench-ab-req-$$.json"
SRVLOG="/tmp/bench-ab-$(basename "$IMAGE" | tr ':/' '__')-gpu$GPU.log"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -f "$REQ"; }
trap cleanup EXIT

echo "[bench] $IMAGE gpu=$GPU model=$(basename "$MODEL") ck=$CK cv=$CV extra: $*"

docker run -d --rm --name "$NAME" --gpus "device=$GPU" \
  -p "127.0.0.1:$PORT:8080" \
  -v "$ROOT/models:/models" \
  --entrypoint /app/llama-server \
  "$IMAGE" \
  --host 0.0.0.0 --port 8080 \
  -m "$MODEL" \
  -ngl 99 -c "$CTX" -ub "$UB" -t "$THREADS" \
  --flash-attn on -np 1 \
  --cache-type-k "$CK" --cache-type-v "$CV" \
  "$@" >/tmp/bench-ab-cid-$$ 2>&1

code=000
for _ in $(seq 1 300); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/health" || true)
  [[ "$code" == "200" ]] && break
  if ! docker inspect -f '{{.State.Running}}' "$NAME" >/dev/null 2>&1; then
    echo "[bench] container exited; log:"; docker logs "$NAME" 2>&1 | tail -40; exit 1
  fi
  sleep 1
done
if [[ "$code" != "200" ]]; then
  echo "[bench] health timeout (HTTP $code); log:"; docker logs "$NAME" 2>&1 | tail -60; exit 1
fi
echo "[bench] server healthy"

python3 - "$PROMPT_TOKENS" > "$REQ" <<'PY'
import json, sys
target_chars = int(sys.argv[1]) * 4
seed = ("The quick brown fox jumps over the lazy dog. "
        "In a distant valley, engineers measured memory bandwidth, "
        "kernel launch overhead, and cache reuse across many iterations. ")
text = (seed * (target_chars // len(seed) + 1))[:target_chars]
print(json.dumps({
    "prompt": text,
    "n_predict": 128,
    "temperature": 0.0,
    "top_k": 1,
    "ignore_eos": True,
    "cache_prompt": False,
    "stream": False,
}))
PY

# warmup
curl -s --max-time 300 -H 'Content-Type: application/json' \
  -d '{"prompt":"Hello","n_predict":8,"temperature":0,"cache_prompt":false}' \
  "http://127.0.0.1:$PORT/completion" >/dev/null || true

[[ -f "$OUT" ]] || printf 'image\tgpu\trep\tprompt_n\tprompt_tps\tgen_n\tgen_tps\n' > "$OUT"
for r in $(seq 1 "$REPS"); do
  resp=$(curl -s --max-time 900 -H 'Content-Type: application/json' \
    --data-binary "@$REQ" "http://127.0.0.1:$PORT/completion")
  line=$(jq -r --arg img "$IMAGE" --arg gpu "$GPU" --arg r "$r" \
    '[ $img, $gpu, $r,
       (.timings.prompt_n|tostring), (.timings.prompt_per_second|tostring),
       (.timings.predicted_n|tostring), (.timings.predicted_per_second|tostring) ] | @tsv' \
    <<<"$resp" 2>/dev/null || true)
  if [[ -z "$line" || "$line" == *"null"* ]]; then
    echo "[bench] rep $r bad response: $(head -c 300 <<<"$resp")" >&2
    continue
  fi
  echo "$line" | tee -a "$OUT"
done

docker logs "$NAME" > "$SRVLOG" 2>&1 || true
echo "[bench] server log: $SRVLOG"
python3 - "$OUT" <<'PY'
import csv, statistics, sys
rows = [r for r in csv.DictReader(open(sys.argv[1]), delimiter='\t')]
if not rows: sys.exit(0)
# summarize the last image/gpu group only
last = rows[-1]; key = (last['image'], last['gpu'])
grp = [r for r in rows if (r['image'], r['gpu']) == key]
for metric in ('prompt_tps', 'gen_tps'):
    vals = [float(r[metric]) for r in grp if r[metric]]
    if vals:
        print(f"[bench] {key[0]} gpu{key[1]} {metric}: median={statistics.median(vals):.2f} "
              f"min={min(vals):.2f} max={max(vals):.2f} n={len(vals)}")
PY
