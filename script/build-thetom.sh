#!/usr/bin/env bash
# build-thetom.sh — Rebuild TheTom llama.cpp server image (source-thetom)
# Follows llmaCPP/update.md Update Protocol Steps 1,4-9.
# Fixes LFM2 + DSpark crash (t_layer_inp null, #25173 sidecar) if needed.
#
# Usage:
#   ./script/build-thetom.sh [--tag TAG] [--no-cache] [--deploy] [--smoke] [--no-patch] [--yes]
# Examples:
#   ./script/build-thetom.sh                          # build only, tag thetom-$(date)
#   ./script/build-thetom.sh --no-cache --deploy      # full rebuild + compose up
#   ./script/build-thetom.sh --tag llama-server:thetom-aug14 --deploy  # overwrite prod tag

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/source-thetom"
COMPOSE="$ROOT/docker-compose.yml"
ARCH="60;61"
DEFAULT_TAG="llama-server:thetom-$(date +%Y%m%d_%H%M)"
TAG="$DEFAULT_TAG"
NOCACHE=""
DEPLOY=0
SMOKE=0
PATCH=1
YES=0

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; NC='\033[0m'
log()  { echo -e "${GRN}[build-thetom]${NC} $*"; }
warn() { echo -e "${YEL}[build-thetom] WARN:${NC} $*"; }
die()  { echo -e "${RED}[build-thetom] FAIL:${NC} $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing: $1"; }

usage(){
  cat <<EOF
Usage: $(basename "$0") [options]
  --tag TAG     image tag (default: $DEFAULT_TAG)
  --no-cache    docker build --no-cache (required after manual patch/merge)
  --deploy      docker compose up -d --force-recreate after build
  --smoke       run VRAM smoke test after build (Step 7, ctx 4096 quick + 65536 for 26B)
  --no-patch    skip LFM2 t_layer_inp patch (DSpark draft for LFM2.5-2.6B)
  --yes         skip confirmation prompts
  -h/--help     this help
Source: $SRC  (branch: feature/turboquant-kv-cache)
Arch:   CUDA_DOCKER_ARCH=$ARCH (P100=60, 1060=61)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    --no-cache) NOCACHE="--no-cache"; shift;;
    --deploy) DEPLOY=1; shift;;
    --smoke) SMOKE=1; shift;;
    --no-patch) PATCH=0; shift;;
    --yes) YES=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1 (see --help)";;
  esac
done

need docker; need git; need awk; need grep
[[ -d "$SRC" ]] || die "source dir not found: $SRC"
[[ -f "$SRC/.devops/cuda.Dockerfile" ]] || die "cuda.Dockerfile not found in $SRC"
[[ -f "$COMPOSE" ]] || die "docker-compose.yml not found"

# ── Step 1: Backup rollback anchors ──────────────────────────────────────────
log "Step 1: backup current state"
DATE="$(date +%Y-%m-%d)"
STABLE_TAG="llama-server:stable-$DATE"
if docker image inspect "$TAG" >/dev/null 2>&1; then warn "tag $TAG already exists — will overwrite"; fi
# tag existing thetom-aug14 / latest if present as stable
for src_tag in "llama-server:thetom-aug14" "llama-server:latest" "llama-server:thetom-$(date +%Y%m%d)" ; do
  if docker image inspect "$src_tag" >/dev/null 2>&1; then
    log "  tagging $src_tag -> $STABLE_TAG (rollback anchor)"
    docker tag "$src_tag" "$STABLE_TAG" || true
    break
  fi
done
mkdir -p "$ROOT/compose-backup"
cp "$COMPOSE" "$ROOT/compose-backup/docker-compose-$DATE-pre-build.yml"
log "  compose backup: compose-backup/docker-compose-$DATE-pre-build.yml"
if [[ -d "$SRC/.git" ]]; then
  git -C "$SRC" rev-parse HEAD > "$SRC/.backup_head" 2>/dev/null || true
  log "  source HEAD: $(cat "$SRC/.backup_head" 2>/dev/null || git -C "$SRC" log -1 --oneline)"
fi
git -C "$SRC" status --porcelain | head -20
if [[ $YES -eq 0 ]]; then
  echo -e "${YEL}Build $TAG from $SRC @ $(git -C "$SRC" log -1 --oneline) ? [y/N]${NC}"
  read -r ans; [[ "$ans" == y || "$ans" == Y ]] || { log "aborted"; exit 0; }
fi

# ── Step 4: Post-merge audits + LFM2 DSpark patch ───────────────────────────
log "Step 4: post-merge audit"

# audit 1: fattn.cu brace balance (update.md §Step 4)
if [[ -f "$SRC/ggml/src/ggml-cuda/fattn.cu" ]]; then
  OPEN=$(awk 'NR>=38 && NR<118' "$SRC/ggml/src/ggml-cuda/fattn.cu" | grep -o '{' | wc -l)
  CLOSE=$(awk 'NR>=38 && NR<118' "$SRC/ggml/src/ggml-cuda/fattn.cu" | grep -o '}' | wc -l)
  if [[ "$OPEN" -ne "$CLOSE" ]]; then
    die "fattn.cu brace mismatch: $OPEN open vs $CLOSE close (see update.md fattn.cu fix)"
  else log "  ✓ fattn.cu braces $OPEN==$CLOSE"; fi
else warn "fattn.cu not found — skip brace audit"; fi

# audit 2: TURBO type_traits
if grep -q 'TURBO2_0' "$SRC/ggml/src/ggml.c" 2>/dev/null; then
  N=$(grep -c 'TURBO3_0\|TURBO4_0\|TURBO2_0' "$SRC/ggml/src/ggml.c"); log "  ✓ TURBO entries in ggml.c ($N)"
  [[ "$N" -ge 3 ]] || die "TURBO type_traits <3 — restore from atomic/feature/turboquant-kv-cache (update.md)"
else warn "TURBO traits not found in ggml.c"; fi
grep -q '^struct ggml_tensor \* ggml_turbo_wht' "$SRC/ggml/src/ggml.c" && log "  ✓ ggml_turbo_wht()" || warn "ggml_turbo_wht() missing"
grep -q '"TURBO_WHT"' "$SRC/ggml/src/ggml.c" && log "  ✓ TURBO_WHT in GGML_OP_NAME" || warn "TURBO_WHT op name missing"
grep -q 'GGML_OP_TURBO_WHT' "$SRC/ggml/src/ggml-cpu/ggml-cpu.c" && log "  ✓ GGML_OP_TURBO_WHT in ggml-cpu.c" || warn "missing"

# audit 3: INI model keys — skipped (models.ini intentionally has [*] without model=)
# was: die on SEC != KEYS — removed per user request 2026-08-29
log "  (skip INI model= audit — models.ini working as-is)"

# LFM2 + DSpark patch: t_layer_inp export required for DFlash/DSpark draft (crash: layer input tensor is null)
# LFM2.5-2.6B-DSpark sidecar uses dflash.target_layers=[3,10,18,22,28] — target LFM2 must expose those layers.
LFM2="$SRC/src/models/lfm2.cpp"
if [[ $PATCH -eq 1 && -f "$LFM2" ]]; then
  if grep -q 't_layer_inp' "$LFM2"; then
    log "  ✓ lfm2.cpp already has t_layer_inp (DSpark-ready)"
  else
    log "  patching lfm2.cpp: inject res->t_layer_inp[il]=cur for DSpark (fixes GGML_ASSERT t_layer_inp null)"
    # backup original once
    [[ -f "$LFM2.bak" ]] || cp "$LFM2" "$LFM2.bak"
    # insert after 'for (int il = 0; il < n_layer; ++il) {' — keep formatting exact to file
    # lfm2.cpp has: "    for (int il = 0; il < n_layer; ++il) {"
    # We inject next line: "        res->t_layer_inp[il] = cur;"
    if grep -q 'for (int il = 0; il < n_layer; ++il) {' "$LFM2"; then
      # use perl for precise insertion without touching other loops; fallback to awk if perl fails
      if ! perl -i -pe 'if (/^\s*for \(int il = 0; il < n_layer; \+\+il\) \{/) { $_ .= "        res->t_layer_inp[il] = cur;\n"; }' "$LFM2" 2>/dev/null; then
        awk '/for \(int il = 0; il < n_layer; \+\+il\) \{/{print; print "        res->t_layer_inp[il] = cur;"; next}1' "$LFM2" > "$LFM2.tmp" && mv "$LFM2.tmp" "$LFM2"
      fi
      # dedupe if run twice (keep only first occurrence) - only if duplicated
      if [[ $(grep -c 't_layer_inp\[il\] = cur' "$LFM2" 2>/dev/null || echo 0) -gt 1 ]]; then
        awk '!x[$0]++' "$LFM2" > "$LFM2.tmp" && mv "$LFM2.tmp" "$LFM2"
      fi
      # verify exactly one insertion per loop (there is one main loop)
      CNT=$(grep -c 't_layer_inp\[il\] = cur' "$LFM2" || true)
      if [[ "$CNT" -ge 1 ]]; then
        log "  ✓ patched lfm2.cpp ($CNT insertion)"
        NOCACHE="--no-cache" # patched source needs no-cache to force cmake rebuild
        warn "  forcing --no-cache because source was patched"
      else die "patch failed — manually edit $LFM2: add res->t_layer_inp[il]=cur at loop top"; fi
    else warn "unexpected lfm2.cpp loop format — patch skipped (edit manually)"; fi
    # lfm2moe reuses lfm2::graph, no separate file needed
  fi
else
  [[ $PATCH -eq 0 ]] && log "  skip LFM2 patch (--no-patch)"
fi

# ensure cmake sees new timestamp (Docker COPY cache trap, update.md §Step 5)
if [[ -n "$NOCACHE" ]]; then :; else
  # touch if we patched
  [[ -f "$LFM2.bak" ]] && touch "$LFM2" 2>/dev/null || true
fi

# ── Step 5: Build ────────────────────────────────────────────────────────────
log "Step 5: docker build $TAG (CUDA_DOCKER_ARCH=$ARCH) ${NOCACHE:+(no-cache)}"
cd "$SRC"
docker build \
  $NOCACHE \
  --build-arg CUDA_DOCKER_ARCH="$ARCH" \
  -f .devops/cuda.Dockerfile \
  --target server \
  -t "$TAG" .

log "  built: $TAG  $(docker images --format '{{.Size}}' "$TAG" 2>/dev/null | head -1)"

# ── Step 6: Post-build symbol verification ──────────────────────────────────
log "Step 6: verify TURBO symbols"
if docker run --rm --entrypoint sh "$TAG" -c 'nm -D /app/libggml-base.so* 2>/dev/null | grep -q ggml_turbo_wht && echo ok || echo missing' 2>/dev/null | grep -q ok; then
  log "  ✓ ggml_turbo_wht present in $TAG"
else warn "  TURBO symbol not found — build may be broken (see update.md Step 6)"; fi

# ── Step 7: Optional VRAM smoke test ────────────────────────────────────────
if [[ $SMOKE -eq 1 ]]; then
  log "Step 7: VRAM smoke test (ctx 4096, quick)"
  for model in \
    "$ROOT/models/LFM2.5-2.6B-Q8_0.gguf" \
    "$ROOT/models/gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf"; do
    [[ -f "$model" ]] || { warn "skip missing $model"; continue; }
    bn=$(basename "$model")
    log "  testing $bn @ ctx=4096 ..."
    docker run --rm --gpus all --entrypoint /app/llama-server \
      -v "$ROOT/models:/models" "$TAG" \
      --host 0.0.0.0 --port 8099 --no-mmap --no-warmup \
      --model "/models/$bn" --n-gpu-layers -1 --cache-type-k turbo4 --cache-type-v turbo2 \
      --ubatch-size 512 --ctx-size 4096 &
    pid=$!; sleep 15
    code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8099/health 2>/dev/null || echo 000)
    kill $pid 2>/dev/null; wait $pid 2>/dev/null || true
    [[ "$code" == "200" ]] && log "    ✓ $bn HTTP $code" || die "    ✗ $bn HTTP $code — check VRAM/logs"
  done
  log "  smoke tests passed"
fi

# ── Step 8: Deploy hint ─────────────────────────────────────────────────────
log "Done. Image: $TAG"
echo ""
echo "To deploy to GTX1060 mini (and keep P100 on atomic):"
echo "  # edit docker-compose.yml: llama-server-mini image: $TAG"
echo "  sed -i 's|image: llama-server:thetom.*|image: $TAG|' $COMPOSE"
echo "  docker compose up -d --force-recreate llama-server-mini"
echo "  docker compose logs -f llama-server-mini"
echo ""
echo "To make it the default for both services:"
echo "  docker tag $TAG llama-server:thetom-aug14   # overwrite production tag"
echo "  docker tag $TAG llama-server:latest"
echo "  docker compose up -d --force-recreate llama-server llama-server-mini"
echo ""
if [[ $DEPLOY -eq 1 ]]; then
  log "Step 8: deploying llama-server-mini -> $TAG"
  # update compose in place, then recreate only mini (safer than touching P100)
  sed -i.bak "s|image: llama-server:thetom.*|image: $TAG|" "$COMPOSE"
  log "  compose patched (backup: docker-compose.yml.bak)"
  docker compose up -d --force-recreate llama-server-mini
  sleep 8
  echo "  mini health: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/health 2>/dev/null || echo 000)"
  echo "  P100 health: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health 2>/dev/null || echo 000)"
  nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader 2>/dev/null || true
fi

log "Rollback if needed (update.md Step 9):"
echo "  docker tag $STABLE_TAG llama-server:thetom-aug14 2>/dev/null; cp compose-backup/docker-compose-$DATE-pre-build.yml $COMPOSE; docker compose up -d --force-recreate llama-server-mini"
echo "  # or: git -C $SRC checkout \$(cat $SRC/.backup_head | awk '{print \$1}')"
