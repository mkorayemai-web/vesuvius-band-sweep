#!/usr/bin/env bash
# Build the VC3D CLI toolchain (villa/volume-cartographer @ the cloned commit) natively on a GB10 (aarch64) node,
# inside a resource-capped container so other work on the same node keeps priority.
# Mirrors villa/volume-cartographer/Dockerfile (ubuntu:26.04 + scripts/install_build_deps.sh + ci-release-gcc preset).
# Usage: setsid nohup bash scripts/build/build_vc3d.sh > vc3d_build.log 2>&1 < /dev/null &   (source: ~/vesuvius/villa)
set -euo pipefail
SRC=~/vesuvius/villa
SHA=$(git -C "$SRC" rev-parse --short=12 HEAD)
NAME=vesu_vc3d_build
JOBS=${JOBS:-6}
echo "[$(date -u +%FT%TZ)] start build of villa $SHA with -j$JOBS"

docker rm -f "$NAME" >/dev/null 2>&1 || true
# CPU-only, capped: 6 CPUs, low cpu-shares (other jobs keep priority), 16 GB RAM hard cap (no swap).
docker run -d --name "$NAME" --cpus 6 --cpu-shares 256 --memory 16g --memory-swap 16g \
  --label owner=vesuvius --label purpose=vc3d-build ubuntu:26.04 sleep infinity >/dev/null
docker cp "$SRC/volume-cartographer" "$NAME:/src"

echo "[$(date -u +%FT%TZ)] installing build deps"
docker exec "$NAME" bash -c 'bash /src/scripts/install_build_deps.sh' 

echo "[$(date -u +%FT%TZ)] configure + build"
docker exec "$NAME" bash -c "cd /src && cmake --preset ci-release-gcc -B /build/ci && nice -n 10 cmake --build /build/ci -j $JOBS"

echo "[$(date -u +%FT%TZ)] install runtime component"
docker exec "$NAME" bash -c 'cmake --install /build/ci --prefix /usr/local --component vc_runtime && ls /usr/local/bin | tr "\n" " "'
echo
docker exec "$NAME" bash -c 'for t in vc_render_tifxyz vc_grow_seg_from_seed vc_gen_umbilicus vc_gen_normalgrids vc_tifxyz2obj vc_obj2tifxyz; do if command -v $t >/dev/null; then echo "OK $t"; else echo "MISSING $t"; fi; done; vc_render_tifxyz --help 2>&1 | head -40'

# Slim the committed image: drop the build tree (keep installed /usr/local) and apt lists.
docker exec "$NAME" bash -c 'rm -rf /build /var/lib/apt/lists/*'
docker commit -c 'CMD ["bash"]' "$NAME" "vesuvius-vc3d:$SHA" >/dev/null
docker tag "vesuvius-vc3d:$SHA" vesuvius-vc3d:latest
docker rm -f "$NAME" >/dev/null
docker images vesuvius-vc3d --format '{{.Repository}}:{{.Tag}} {{.Size}}'
echo "[$(date -u +%FT%TZ)] DONE vesuvius-vc3d:$SHA"
