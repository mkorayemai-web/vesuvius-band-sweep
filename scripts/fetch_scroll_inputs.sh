#!/usr/bin/env bash
# First scroll on a node: mkdir -p ~/vesuvius/work/data/none and pass old_scroll=none.
# fetch_scroll_inputs.sh <old_scroll> <new_scroll> [cpus=1] - CPU/network only. Frees the old scroll's spiral-fit inputs (tracks,
# Lasagna, m7 slab; fitted meshes, snaps and screen thumbnails are kept), then fetches the new scroll's inputs:
# Alexey Drobkov's umbilicus (ext/herculaneum-umbilici), spiral tracks (dl.ash2txt.org; resumable, size-checked) and
# Lasagna nx/ny/grad_mag group 2 (S3 sync) + the las_008_* names fit_spiral looks up. Idempotent. Prints ALL DONE only
# after the file checks pass. Containers: --cpus <cpus>, 4 GB (can run beside a --cpus 8 screen).
set -uo pipefail
ts() { date -u +%FT%TZ; }
OLD=$1; NEW=$2; CPUS=${3:-1}
case $NEW in
  PHerc0813) V=20250821151723; NEXP=133523 ;;   # NEXP = S3 keys under each <ch>.ome.zarr/2/ (listed 2026-10-15T15:50Z)
  *) echo "[$(ts)] ABORT: unknown scroll $NEW"; exit 2 ;;
esac
W=~/vesuvius/work; EXT=~/vesuvius/ext
c() { docker run --rm --cpus "$CPUS" --cpu-shares 256 --memory 4g --memory-swap 4g --label owner=vesuvius \
        -v "$W":/work -v "$EXT":/ext vesuvius-ml:latest bash -lc "set -o pipefail; $*"; }
[ -d "$W/data/$OLD" ] || { echo "[$(ts)] ABORT: no data dir for $OLD"; exit 2; }
echo "[$(ts)] >>> free $OLD inputs (tracks, lasagna, m7 slab)"
c "rm -rf /work/data/$OLD/tracks /work/data/$OLD/lasagna /work/data/$OLD/m7_slab.zarr && ls /work/data/$OLD/" \
  || { echo "[$(ts)] ABORT: delete failed"; exit 4; }
df -h / | tail -1
echo "[$(ts)] >>> $NEW umbilicus"
mkdir -p "$W/data/$NEW"
cp "$EXT/herculaneum-umbilici/${NEW}_umbilicus.json" "$W/data/$NEW/umbilicus_alexey.json" \
  || { echo "[$(ts)] ABORT: no umbilicus for $NEW"; exit 4; }
echo "[$(ts)] >>> $NEW spiral tracks (dl.ash2txt.org)"
c "/opt/villa/vesuvius/.venv/bin/python /work/dl_index.py https://dl.ash2txt.org/datasets/spiral_datasets/$NEW/$V/tracks/ /work/data/$NEW/tracks | tail -8" \
  || { echo "[$(ts)] ABORT: tracks download failed"; exit 4; }
echo "[$(ts)] >>> $NEW Lasagna nx/ny/grad_mag group 2 (S3)"
L=s3://vesuvius-challenge-open-data/$NEW/representations/predictions/lasagna/$V-lasagna-20260419180421
for pass in 1 2; do
  c "mkdir -p /work/data/$NEW/lasagna && aws s3 cp --no-sign-request --only-show-errors $L/$NEW.lasagna.json /work/data/$NEW/lasagna/ && for ch in nx ny grad_mag; do for f in .zattrs .zgroup; do aws s3 cp --no-sign-request --only-show-errors $L/${NEW}_\$ch.ome.zarr/\$f /work/data/$NEW/lasagna/${NEW}_\$ch.ome.zarr/\$f; done; aws s3 sync --no-sign-request --only-show-errors $L/${NEW}_\$ch.ome.zarr/2/ /work/data/$NEW/lasagna/${NEW}_\$ch.ome.zarr/2/ || exit 4; done; cd /work/data/$NEW/lasagna && for ch in nx ny grad_mag; do ln -sfn ${NEW}_\$ch.ome.zarr las_008_\$ch.ome.zarr; done" \
    || { echo "[$(ts)] lasagna sync pass $pass failed"; continue; }
  ok=1
  for ch in nx ny grad_mag; do
    n=$(find "$W/data/$NEW/lasagna/${NEW}_$ch.ome.zarr/2" -type f 2>/dev/null | wc -l)
    echo "  $ch group-2 files $n (expected $NEXP)"
    [ "$n" -eq "$NEXP" ] || ok=0
  done
  [ $ok = 1 ] && break
done
[ "${ok:-0}" = 1 ] || { echo "[$(ts)] ABORT: Lasagna file counts wrong after 2 passes"; exit 4; }
DBM=$W/data/$NEW/tracks/${NEW}_${V}_surface_m7_L0_th0.2.dbm
[ -s "$DBM" ] && [ -s "$DBM.crossings.npz" ] && [ "$(ls "$DBM.vctracks" 2>/dev/null | wc -l)" -ge 9 ] \
  || { echo "[$(ts)] ABORT: tracks incomplete"; exit 4; }
du -sh "$W/data/$NEW"/* 2>/dev/null
df -h / | tail -1
echo "[$(ts)] ALL DONE swap_data $OLD -> $NEW"
