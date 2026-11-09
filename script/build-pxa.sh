#!/usr/bin/env bash
# build-pxa.sh - Build the PXA llama.cpp server image (source-pxa)
#
# PXA 4.0 fork (poisonxa16/pxa): tuned for Tesla P100 (sm_60), GTX 10-series (sm_61),
# Tesla V100 (sm_70). Builds with CUDA_DOCKER_ARCH="60;61" to cover both cards.
#
# Usage:
#   ./script/build-pxa.sh [--tag TAG] [--no-cache] [--deploy] [--yes]
# Examples:
#   ./script/build-pxa.sh
#   ./script/build-pxa.sh --tag llama-server:pxa-nov9 --deploy --yes

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/source-pxa"
COMPOSE="$ROOT/docker-compose.yml"
ARCH="60;61"
DEFAULT_TAG="llama-server:pxa-nov9"
TAG="$DEFAULT_TAG"
NOCACHE=""
DEPLOY=0
YES=0

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; NC='\033[0m'
log()  { echo -e "${GRN}[build-pxa]${NC} $*"; }
warn() { echo -e "${YEL}[build-pxa] WARN:${NC} $*"; }
die()  { echo -e "${RED}[build-pxa] FAIL:${NC} $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing: $1"; }

usage(){
  cat <<EOF
Usage: $(basename "$0") [options]
  --tag TAG     image tag (default: $DEFAULT_TAG)
  --no-cache    docker build --no-cache
  --deploy      recreate the pxa service after a successful build
  --yes         skip confirmation prompt
  -h/--help     this help
Source: $SRC
Arch:   CUDA_DOCKER_ARCH=$ARCH (sm_60 + sm_61)
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
[[ -f "$SRC/.devops/llama-server-cuda.Dockerfile" ]] || die "llama-server-cuda.Dockerfile not found in $SRC"
[[ -f "$COMPOSE" ]] || die "docker-compose.yml not found"

DATE="$(date +%Y-%m-%d)"
STABLE_TAG="llama-server:stable-pxa-$DATE"

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
BACKUP="$ROOT/compose-backup/docker-compose-$DATE-pre-pxa-$(date +%H%M%S).yml"
cp "$COMPOSE" "$BACKUP"
log "  compose backup: ${BACKUP#$ROOT/}"

# PXA requires the public PXQ/PXQN encoder tree which is not included in this clone.
# Disable both encoder options so cmake configures successfully for a server-only build.
# Also disable tests (missing test source files in this shallow clone).
DF="$SRC/.devops/llama-server-cuda.Dockerfile"
NEED_PATCH=0
if [[ -f "$DF" ]] && ! grep -q 'PXA_PXQ_ENCODER=OFF' "$DF"; then
  NEED_PATCH=1
fi
if [[ -f "$DF" ]] && ! grep -q 'PXA_PXQN_ENCODER=OFF' "$DF"; then
  NEED_PATCH=1
fi
if [[ -f "$DF" ]] && ! grep -q 'LLAMA_BUILD_TESTS=OFF' "$DF"; then
  NEED_PATCH=1
fi
if [[ $NEED_PATCH -eq 1 ]]; then
  log "patching llama-server-cuda.Dockerfile: add -DPXA_PXQ_ENCODER=OFF -DPXA_PXQN_ENCODER=OFF -DLLAMA_BUILD_TESTS=OFF"
  [[ -f "$DF.bak" ]] || cp "$DF" "$DF.bak"
  # insert all three flags after the CUDA_ARCHITECTURES line
  perl -0pi -e 's/(-DCMAKE_CUDA_ARCHITECTURES="\$\{CUDA_DOCKER_ARCH\}")/$1 \\\n    -DPXA_PXQ_ENCODER=OFF \\\n    -DPXA_PXQN_ENCODER=OFF \\\n    -DLLAMA_BUILD_TESTS=OFF/' "$DF"
  grep -q 'PXA_PXQ_ENCODER=OFF' "$DF" || die "patch failed: edit $DF manually"
  grep -q 'PXA_PXQN_ENCODER=OFF' "$DF" || die "patch failed: edit $DF manually"
  grep -q 'LLAMA_BUILD_TESTS=OFF' "$DF" || die "patch failed: edit $DF manually"
  NOCACHE="--no-cache"
  warn "forcing --no-cache because Dockerfile was patched"
else
  log "llama-server-cuda.Dockerfile already has PXA_PXQ_ENCODER=OFF / PXA_PXQN_ENCODER=OFF / LLAMA_BUILD_TESTS=OFF"
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
  -f .devops/llama-server-cuda.Dockerfile \
  --target runtime \
  -t "$TAG" .

log "verify version"
docker run --rm --entrypoint /llama-server "$TAG" --version

if [[ $DEPLOY -eq 1 ]]; then
  log "deploying pxa service -> $TAG"
  ( cd "$ROOT" && docker compose up -d --force-recreate llama-server-pxa )
  sleep 5
  echo "  pxa health:     $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8082/health 2>/dev/null || echo 000)"
  echo "  primary health: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/health 2>/dev/null || echo 000)"
  nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader 2>/dev/null || true
fi

log "done: $TAG"
echo "Rollback:"
echo "  cp $BACKUP $COMPOSE"
echo "  ( cd $ROOT && docker compose up -d --force-recreate llama-server )"
echo "  # rollback anchor: $STABLE_TAG"
