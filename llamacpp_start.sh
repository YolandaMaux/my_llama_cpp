#!/usr/bin/env bash
# llama.cpp Compose launcher.
# All deployment configuration belongs in the Compose YAML, llamacpp.env,
# llamacpp.secrets.env, and llamacpp_models.ini. This script selects a
# Compose deployment and provides lifecycle, validation, and API helpers.
#
# Every path referenced below is relative to this script's own directory,
# so the whole project can live anywhere on disk (and be moved/renamed)
# without editing a single file. The one exception is MODELS_DIR, which is
# an intentionally hardcoded host path -- but it lives only in llamacpp.env.
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

CONTAINER_NAME="llamacpp"

command -v podman >/dev/null 2>&1 || {
  echo "ERROR: podman is required but was not found in PATH." >&2
  exit 127
}

[[ -f llamacpp.env ]] || {
  echo "ERROR: llamacpp.env is required. Set MODELS_DIR before starting." >&2
  exit 1
}

[[ -f llamacpp_models.ini ]] || {
  echo "ERROR: llamacpp_models.ini is required." >&2
  exit 1
}

# Keep Compose interpolation and the container environment sourced from the
# same files; never source .env files directly in the shell.
env_args=()
[[ -f llamacpp.secrets.env ]] && env_args+=(--env-file llamacpp.secrets.env)
env_args+=(--env-file llamacpp.env)

compose_cpu=(podman compose "${env_args[@]}" -f llamacpp_compose.cpu.yml)
compose_gpu=(podman compose "${env_args[@]}" -f llamacpp_compose.standard-gpu.yml)
compose_titanx=(podman compose "${env_args[@]}" -f llamacpp_compose.titanx.yml)

# Used only by the models API helper. The YAML files remain the source of
# truth for published ports, container healthchecks, and server configuration.
port="$(sed -nE 's/^[[:space:]]*LLAMACPP_PORT[[:space:]]*=[[:space:]]*([^[:space:]#]+).*$/\1/p' llamacpp.env | tail -n 1)"
port="${port:-8080}"

# podman-compose does not reliably recreate a container that already exists
# under the same name -- it can silently reuse a stale one, or error out
# with "name already in use", even after --build produces a new image.
# Force removal before every start so each deployment is guaranteed fresh.
reset_container() {
  podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}

# Starts a service, rebuilding the image by default. Pass --no-build (in
# any position) to skip the image build entirely and just recreate the
# container from whatever image already exists -- use this after editing
# llamacpp.env / llamacpp_models.ini / compose YAML only, with no Dockerfile
# or llama.cpp source changes, to avoid paying the full build cost again.
start_service() {
  local -n compose_arr="$1"
  shift
  local build_flag=1
  local args=()
  for a in "$@"; do
    if [[ "$a" == "--no-build" ]]; then
      build_flag=0
    else
      args+=("$a")
    fi
  done
  reset_container
  if [[ "$build_flag" -eq 1 ]]; then
    "${compose_arr[@]}" up --build "${args[@]}"
  else
    "${compose_arr[@]}" up "${args[@]}"
  fi
}

usage() {
cat <<'EOF'
Usage: ./llamacpp_start.sh COMMAND [OPTIONS]

Start commands
  cpu [up-options]        Build and start the CPU Compose deployment.
  gpu [up-options]        Start the generic NVIDIA CUDA Compose deployment.
  titanx [up-options]     Build and start the Titan X Maxwell (SM 5.2) deployment.

  Pass --no-build to cpu/titanx to skip the image build and just recreate
  the container from the existing image (e.g. after only editing
  llamacpp.env, llamacpp_models.ini, or a compose YAML file):
    ./llamacpp_start.sh titanx --no-build
    ./llamacpp_start.sh titanx --no-build -d

Lifecycle commands
  rebuild-cpu             Rebuild CPU image without cache, then start detached.
  rebuild-titanx          Rebuild Titan X image without cache, then start detached.
  down                    Stop and remove the running llamacpp container.
  logs                    Follow container logs.
  status                  Show container status, including health state.

Checks and API helpers
  validate                Validate all three Compose configurations.
  models                  Request GET /v1/models on the configured host port.
  help                    Show this help.

Examples
  ./llamacpp_start.sh titanx
  ./llamacpp_start.sh titanx --no-build -d
  ./llamacpp_start.sh logs
  ./llamacpp_start.sh models
EOF
}

case "${1:-help}" in
  cpu)
    shift
    start_service compose_cpu "$@"
    ;;
  gpu)
    shift
    reset_container
    "${compose_gpu[@]}" up "$@"
    ;;
  titanx)
    shift
    start_service compose_titanx "$@"
    ;;
  rebuild-cpu)
    reset_container
    "${compose_cpu[@]}" build --no-cache
    "${compose_cpu[@]}" up -d
    ;;
  rebuild-titanx)
    reset_container
    "${compose_titanx[@]}" build --no-cache
    "${compose_titanx[@]}" up -d
    ;;
  down)
    podman stop -t 30 "${CONTAINER_NAME}" 2>/dev/null || true
    podman rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    ;;
  logs)
    exec podman logs --follow "${CONTAINER_NAME}"
    ;;
  status)
    podman ps -a --filter "name=^${CONTAINER_NAME}\$"
    ;;
  validate)
    "${compose_cpu[@]}" config >/dev/null
    "${compose_gpu[@]}" config >/dev/null
    "${compose_titanx[@]}" config >/dev/null
    echo "All Compose configurations are valid."
    ;;
  models)
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required." >&2; exit 127; }
    curl --fail --silent --show-error "http://127.0.0.1:${port}/v1/models"
    echo
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "ERROR: unknown command: $1" >&2
    usage >&2
    exit 64
    ;;
esac
