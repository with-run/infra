#!/usr/bin/env bash
set -euo pipefail

APP_HOME="/opt/withrun"
COMPOSE_FILE="$APP_HOME/deploy/compose/docker-compose.yml"
IMAGE_ENV="$APP_HOME/run/images.env"

MODE="${1:-infra}"
WEB_IMAGE_INPUT="${2:-}"
WAS_IMAGE_INPUT="${3:-}"

mkdir -p "$APP_HOME/run"
touch "$IMAGE_ENV"

set_kv() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" "$IMAGE_ENV"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$IMAGE_ENV"
  else
    echo "${key}=${value}" >> "$IMAGE_ENV"
  fi
}

get_kv() {
  local key="$1"

  if grep -q "^${key}=" "$IMAGE_ENV"; then
    grep "^${key}=" "$IMAGE_ENV" | tail -n 1 | cut -d'=' -f2-
  fi
}

resolve_image() {
  local key="$1"
  local input_value="$2"
  local stored_value

  if [[ -n "$input_value" ]]; then
    set_kv "$key" "$input_value"
    echo "$input_value"
    return
  fi

  stored_value="$(get_kv "$key")"
  if [[ -z "$stored_value" ]]; then
    echo "missing ${key} in ${IMAGE_ENV}"
    exit 1
  fi

  echo "$stored_value"
}

compose() {
  docker compose --env-file "$IMAGE_ENV" -f "$COMPOSE_FILE" "$@"
}

if [[ -n "${DOCKERHUB_USERNAME:-}" && -n "${DOCKERHUB_TOKEN:-}" ]]; then
  echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin
fi

case "$MODE" in
  web)
    WEB_IMAGE="$(resolve_image "WEB_IMAGE" "$WEB_IMAGE_INPUT")"
    docker pull "$WEB_IMAGE"
    compose up -d --no-deps web
    ;;
  was)
    WAS_IMAGE="$(resolve_image "WAS_IMAGE" "$WAS_IMAGE_INPUT")"
    docker pull "$WAS_IMAGE"
    compose up -d --no-deps was
    ;;
  infra)
    compose pull nginx || true
    compose up -d nginx
    ;;
  all)
    WEB_IMAGE="$(resolve_image "WEB_IMAGE" "$WEB_IMAGE_INPUT")"
    WAS_IMAGE="$(resolve_image "WAS_IMAGE" "$WAS_IMAGE_INPUT")"
    docker pull "$WEB_IMAGE"
    docker pull "$WAS_IMAGE"
    compose pull nginx || true
    compose up -d nginx web was
    ;;
  *)
    echo "usage: deploy.sh [infra|web|was|all] [web_image] [was_image]"
    exit 1
    ;;
esac

docker image prune -af --filter "until=168h" || true
