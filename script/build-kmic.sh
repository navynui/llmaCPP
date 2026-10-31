#!/usr/bin/env bash
# build-kmic.sh - Build the Kmic-68 P100 llama.cpp server image (source-kmic-68)
#
# Primary (P100) only. The build must be sm_60-only: the Pascal tuning in mmvq.cu
# is gated on __CUDA_ARCH_LIST__ == 600, so adding 61 silently disables it.
# Keep llama-server-mini on the TheTom image.
#
# Usage:
#   ./script/build-kmic.sh [--tag TAG] [--no-cache] [--deploy] [--yes]
# Examples:
#   ./script/build-kmic.sh
#   ./script/build-kmic.sh --tag llama-server:kmic-p100-test --deploy --yes

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/source-kmic-68"
COMPOSE="$ROOT/docker-compose.yml"
ARCH="60"
DEFAULT_TAG="llama-server:kmic-p100-$(date +%Y%m%d)"
TAG="$DEFAULT_TAG"
NOCACHE=""
DEPLOY=0
YES=0

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; NC='\033[0m'
log()  { echo -e "${GRN}[build-kmic]${NC} $*"; }
warn() { echo -e "${YEL}[build-kmic] WARN:${NC} $*"; }
die()  { echo -e "${RED}[build-kmic] FAIL:${NC} $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing: $1"; }

usage(){
  cat <<EOF
Usage: $(basename "$0") [options]
  --tag TAG     image tag (default: $DEFAULT_TAG)
  --no-cache    docker build --no-cache
  --deploy      recreate the primary (llama-server) after a successful build
  --yes         skip confirmation prompt
  -h/--help     this help
Source: $SRC (branch p100-optimizations)
Arch:   CUDA_DOCKER_ARCH=$ARCH (sm_60 only)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2;;
    --no-cache) NOCACHE="--no-cache"; shift;;
    --deploy) DEPLOY=1; shift;;
    --yes) YES=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1 (see --help)";;
  esac
done

need docker; need git
[[ -d "$SRC" ]] || die "source dir not found: $SRC"
[[ -f "$SRC/.devops/cuda.Dockerfile" ]] || die "cuda.Dockerfile not found in $SRC"
[[ -f "$COMPOSE" ]] || die "docker-compose.yml not found"

DATE="$(date +%Y-%m-%d)"
STABLE_TAG="llama-server:stable-$DATE"

log "backup current primary image and compose"
if docker image inspect "$STABLE_TAG" >/dev/null 2>&1; then
  warn "$STABLE_TAG already exists, keeping it"
else
  current="$(docker inspect -f '{{.Config.Image}}' llm-server 2>/dev/null || true)"
  if [[ -n "$current" ]] && docker image inspect "$current" >/dev/null 2>&1; then
    docker tag "$current" "$STABLE_TAG"
    log "  tagged $current -> $STABLE_TAG"
  else
    warn "  could not determine the running primary image; no rollback tag made"
  fi
fi
mkdir -p "$ROOT/compose-backup"
BACKUP="$ROOT/compose-backup/docker-compose-$DATE-pre-kmic-$(date +%H%M%S).yml"
cp "$COMPOSE" "$BACKUP"
log "  compose backup: ${BACKUP#$ROOT/}"

# GCC 14 libstdc++ no longer pulls <algorithm> in transitively. The fork uses
# std::max<int64_t>({...}) in llama-context.cpp, so add the include explicitly.
CTX="$SRC/src/llama-context.cpp"
if [[ -f "$CTX" ]] && ! grep -q '^#include <algorithm>' "$CTX"; then
  log "patching llama-context.cpp: add #include <algorithm>"
  [[ -f "$CTX.bak" ]] || cp "$CTX" "$CTX.bak"
  perl -0pi -e 's/#include <cinttypes>/#include <algorithm>\n#include <cinttypes>/' "$CTX"
  grep -q '^#include <algorithm>' "$CTX" || die "patch failed: edit $CTX manually"
  NOCACHE="--no-cache"
  warn "forcing --no-cache because source was patched"
else
  log "llama-context.cpp already has <algorithm>"
fi

# The P100 fused GDN CUDA path faults on Qwen3.5-MoE (illegal memory access in
# ggml_cuda_op_gated_delta_net_fused_cache). Keep the tuned path for other
# architectures and fall back to the non-fused path for qwen35moe.
if [[ -f "$CTX" ]] && ! grep -q 'disable_fused_gdn' "$CTX"; then
  log "patching llama-context.cpp: disable fused GDN for Qwen3.5-MoE"
  [[ -f "$CTX.bak" ]] || cp "$CTX" "$CTX.bak"
  perl -0pi -e 's/cparams\.fused_gdn_ar = true;\n    cparams\.fused_gdn_ch = true;\n    cparams\.auto_fgdn    = false;/const bool disable_fused_gdn = model.arch == LLM_ARCH_QWEN35MOE;\n    cparams.fused_gdn_ar = !disable_fused_gdn;\n    cparams.fused_gdn_ch = !disable_fused_gdn;\n    cparams.auto_fgdn    = false;/' "$CTX"
  grep -q 'disable_fused_gdn' "$CTX" || die "patch failed: edit $CTX manually"
  NOCACHE="--no-cache"
  warn "forcing --no-cache because source was patched"
else
  log "llama-context.cpp already has the fused-GDN guard"
fi

if [[ $YES -eq 0 ]]; then
  echo -e "${YEL}Build $TAG from $SRC @ $(git -C "$SRC" log -1 --oneline) ? [y/N]${NC}"
  read -r ans; [[ "$ans" == y || "$ans" == Y ]] || { log "aborted"; exit 0; }
fi

log "docker build $TAG (CUDA_DOCKER_ARCH=$ARCH) ${NOCACHE:+(no-cache)}"
cd "$SRC"
docker build \
  $NOCACHE \
  --build-arg CUDA_DOCKER_ARCH="$ARCH" \
  -f .devops/cuda.Dockerfile \
  --target server \
  -t "$TAG" .

log "verify version"
docker run --rm --entrypoint /app/llama-server "$TAG" --version

if [[ $DEPLOY -eq 1 ]]; then
  log "deploying primary only -> $TAG"
  sed -i "s|^    image: llama-server:.*|    image: $TAG|" "$COMPOSE"
  ( cd "$ROOT" && docker compose up -d --force-recreate llama-server )
  sleep 5
  echo "  primary health: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health 2>/dev/null || echo 000)"
  echo "  mini health:    $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/health 2>/dev/null || echo 000)"
  nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader 2>/dev/null || true
fi

log "done: $TAG"
echo "Rollback:"
echo "  cp $BACKUP $COMPOSE"
echo "  ( cd $ROOT && docker compose up -d --force-recreate llama-server )"
echo "  # rollback anchor: $STABLE_TAG"
