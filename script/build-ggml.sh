#!/usr/bin/env bash
# build-ggml.sh — build the upstream ggml-org/llama.cpp server image (source-ggml)
# Pascal target: P100 (sm_60) + GTX 1060 (sm_61).
#
# Usage:
#   ./script/build-ggml.sh [--tag TAG] [--no-cache] [--deploy] [--yes]
# Examples:
#   ./script/build-ggml.sh
#   ./script/build-ggml.sh --tag llama-server:ggml-nov16 --yes
#   ./script/build-ggml.sh --tag llama-server:ggml-nov16 --deploy

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/source-ggml"
COMPOSE="$ROOT/docker-compose.yml"
ARCH="60;61"
DEFAULT_TAG="llama-server:ggml-$(date +%Y%m%d)"
TAG="$DEFAULT_TAG"
NOCACHE=""
DEPLOY=0
YES=0

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; NC='\033[0m'
log()  { echo -e "${GRN}[build-ggml]${NC} $*"; }
warn() { echo -e "${YEL}[build-ggml] WARN:${NC} $*"; }
die()  { echo -e "${RED}[build-ggml] FAIL:${NC} $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing: $1"; }

usage(){
  cat <<EOF
Usage: $(basename "$0") [options]
  --tag TAG     image tag (default: $DEFAULT_TAG)
  --no-cache    docker build --no-cache
  --deploy      recreate the primary (llama-server) after a successful build
  --yes         skip confirmation prompt
  -h/--help     this help
Source: $SRC (upstream master)
Arch:   CUDA_DOCKER_ARCH=$ARCH (P100=60, 1060=61)
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
BACKUP="$ROOT/compose-backup/docker-compose-$DATE-pre-ggml-$(date +%H%M%S).yml"
cp "$COMPOSE" "$BACKUP"
log "  compose backup: ${BACKUP#$ROOT/}"
git -C "$SRC" log -1 --oneline
git -C "$SRC" status --porcelain | head -20

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

log "built: $TAG  $(docker images --format '{{.Size}}' "$TAG" 2>/dev/null | head -1)"
log "verify:"
docker run --rm --entrypoint /app/llama-server "$TAG" --version || true

if [[ $DEPLOY -eq 1 ]]; then
  sed -i "s|image: llama-server:.*|image: $TAG|" "$COMPOSE"
  docker compose -f "$COMPOSE" up -d --force-recreate llama-server
fi

log "Done. Image: $TAG"
