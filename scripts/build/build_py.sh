#!/usr/bin/env bash
# Stage 2: Python ML environments (vesuvius ink inference, spiral-fitting, lasagna) on top of the stage-1 VC3D image.
# CPU-only, resource-capped build container; GPU is NOT used here. Each component is attempted independently and its
# status recorded in /opt/villa/BUILD_STATUS.txt inside the committed image.
# Usage: setsid nohup bash scripts/build/build_py.sh > py_build.log 2>&1 < /dev/null &
set -uo pipefail
SRC=~/vesuvius/villa
SHA=$(git -C "$SRC" rev-parse --short=12 HEAD)
NAME=vesu_py_build
ts() { date -u +%FT%TZ; }
echo "[$(ts)] stage 2 for villa $SHA"
if ! docker image inspect "vesuvius-vc3d:$SHA" >/dev/null 2>&1; then
  echo "[$(ts)] ABORT: stage-1 image vesuvius-vc3d:$SHA missing"; exit 1
fi
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --cpus 6 --cpu-shares 256 --memory 24g --memory-swap 24g \
  --label owner=vesuvius --label purpose=py-build "vesuvius-vc3d:$SHA" sleep infinity >/dev/null || exit 1
docker exec "$NAME" mkdir -p /opt
docker cp "$SRC" "$NAME:/opt/villa"

step() {  # step <label> <shell command run inside the container>
  local label="$1"; shift
  echo "[$(ts)] >>> $label"
  if docker exec -e UV_LINK_MODE=copy -e CMAKE_BUILD_PARALLEL_LEVEL=6 -e MAX_JOBS=6 "$NAME" bash -lc "$*"; then
    echo "[$(ts)] <<< $label OK";  docker exec "$NAME" bash -c "echo 'OK   $label' >> /opt/villa/BUILD_STATUS.txt"
  else
    echo "[$(ts)] <<< $label FAILED"; docker exec "$NAME" bash -c "echo 'FAIL $label' >> /opt/villa/BUILD_STATUS.txt"
  fi
}

step "uv install" 'curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh && uv --version && uv python install 3.14 && uv python list --only-installed'
step "vesuvius uv sync --extra models" 'cd /opt/villa/vesuvius && uv sync --extra models 2>&1 | tail -40'
step "vesuvius import" 'cd /opt/villa/vesuvius && uv run --extra models python -c "import torch, vesuvius, zarr; print(\"torch\", torch.__version__, \"cuda\", torch.version.cuda, \"arch\", torch._C._cuda_getArchFlags())"'
step "spiral-fitting uv sync" 'cd /opt/villa/spiral-fitting && uv sync 2>&1 | tail -40'
step "spiral-fitting import" 'cd /opt/villa/spiral-fitting && uv run python -c "import torch; print(\"torch\", torch.__version__, \"cuda\", torch.version.cuda, \"arch\", torch._C._cuda_getArchFlags()); import fit_spiral; print(\"fit_spiral import ok\")"'
step "lasagna bootstrap cu130" 'cd /opt/villa/lasagna && uv run --no-project --python 3.14 python scripts/bootstrap_venv.py --venv .venv --backend cu130 2>&1 | tail -40'
step "lasagna import" 'cd /opt/villa/lasagna && .venv/bin/python -c "import torch; print(\"torch\", torch.__version__, \"cuda\", torch.version.cuda, \"arch\", torch._C._cuda_getArchFlags())" && .venv/bin/lasagna-fit-service --help | head -5'

docker exec "$NAME" bash -c 'cat /opt/villa/BUILD_STATUS.txt; rm -rf /root/.cache/uv /root/.cache/pip'
docker commit -c 'CMD ["bash"]' "$NAME" "vesuvius-ml:$SHA" >/dev/null && docker tag "vesuvius-ml:$SHA" vesuvius-ml:latest
docker rm -f "$NAME" >/dev/null
docker images vesuvius-ml --format '{{.Repository}}:{{.Tag}} {{.Size}}'
echo "[$(ts)] DONE stage 2 vesuvius-ml:$SHA"
