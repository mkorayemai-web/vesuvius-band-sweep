#!/usr/bin/env bash
# cleanup_pools.sh - CPU, seconds: delete the Lasagna resident pools of every scroll after a spiral fit (each fit rebuilds
# its pool in ~1 min; the pools hold ~12 GB and once pushed our node under its disk floor). One tiny
# container (--cpus 1, 2 GB), our files only.
set -uo pipefail
docker run --rm --cpus 1 --memory 2g --label owner=vesuvius -v "${W:-$HOME/vesuvius/work}":/work vesuvius-ml:latest \
  bash -c "rm -rf /work/data/*/lasagna/*respool* && ls /work/data/*/lasagna/"
rc=$?; df -h / | tail -1
[ $rc -eq 0 ] && echo "[$(date -u +%FT%TZ)] ALL DONE cleanup_pools"
