#!/usr/bin/env bash
# screen_band.sh [S=<scroll>] <z_begin> <z_end> <models_csv> <depths_csv> <winding...|QA<thr>>
#   (default scroll PHerc0257; "QA0.85" = every winding of the band with snap frac_with_sheet >= 0.85;
#    env CPUS (default 9) = docker --cpus)
# Streaming First Letters screen for one band whose snapped windings exist (scripts/fit_snap_band.sh).
# Per winding: Lasagna flatten (GPU) -> 66-layer render (CPU, CT streamed from S3, network-safe) -> the listed villa
# ink models at the listed depths, both directions (GPU) -> 1/4 + 1/8 thumbnails of every map, then the render and
# the full-size maps are deleted (disk stays flat: ~2 MB kept per winding). The thumbnails feed scripts/review_sheets.py.
# A periodicity triage (screen/triage_tiles*.py) is logged per winding; it FAILED calibration on band maps
# (docs/FAILURE_CASES.md) and decides nothing. Idempotent (quick_done.json per winding); job budget 2h40m, re-run to
# continue. Caps: one container at a time, --cpus 9, shares 256, 40 GB, 1 GPU process with a 14 GB pool.
set -uo pipefail
ts() { date -u +%FT%TZ; }
T0=$(date +%s); BUDGET=$((160*60)); KEEP=9; FLAG=0.5   # KEEP=9: never keep renders (the triage ratio failed calibration; 1/4 + 1/8 PNGs kept for review)
S=PHerc0257; if [[ "${1:-}" == S=* ]]; then S=${1#S=}; shift; fi
case $S in PHerc0257) V=20250821151750 ;; PHerc0813) V=20250821151723 ;; *) echo "[$(date -u +%FT%TZ)] ABORT: unknown scroll $S"; exit 2 ;; esac
ZB=$1; ZE=$2; MODELS=$(echo "$3" | tr ',' ' '); DEPTHS=$(echo "$4" | tr ',' ' '); shift 4
W=~/vesuvius/work; EXT=~/vesuvius/ext; CPUS=${CPUS:-9}
VOL=https://vesuvius-challenge-open-data.s3.us-east-1.amazonaws.com/$S/volumes/${V}-9.362um-1.2m-113keV-masked.zarr
PY=/opt/villa/vesuvius/.venv/bin/python; LPY=/opt/villa/lasagna/.venv/bin/python
if [ "$S" = PHerc0257 ] && [ "$ZB-$ZE" = "9000-10000" ]; then SNAP=snapped; GB=/work/screen/$S; else SNAP=snapped_${ZB}_${ZE}; GB=/work/screen/$S/b${ZB}; fi
[ -f "$W/spiral_out/$S/$SNAP/snap_report.tsv" ] || { echo "[$(ts)] ABORT: no snaps for band $ZB-$ZE"; exit 2; }
if [[ "${1:-}" == QA* ]]; then
  thr=${1#QA}; set -- $(awk -F'\t' -v t="$thr" 'NR > 1 && $3 + 0 >= t {print $1}' "$W/spiral_out/$S/$SNAP/snap_report.tsv")
  echo "[$(ts)] $S band $ZB-$ZE: $# windings with snap frac_with_sheet >= $thr"
fi
curl -s -o /dev/null -m 20 -w "%{http_code}" "$VOL/.zgroup" | grep -q 200 || { echo "[$(ts)] ABORT: S3 unreachable from $(hostname)"; exit 3; }
mkdir -p "$W/screen/tmp"; cp "$(dirname "$0")"/screen/{triage_tiles.py,triage_tiles_v2.py,score_winding.py} "$W/screen/"
[ -s "$W/screen/control_reference_triage_v2.json" ] || echo "[$(ts)] note: no control reference for the (withdrawn) triage ratio; logged as 0"
run() {  # run <label> <gpu 0|1> <cmd>
  local label="$1" gpu="$2"; shift 2
  local g=(); [ "$gpu" = 1 ] && g=(--gpus all -e VES_GPU_POOL_GB=14)
  echo "[$(ts)] >>> $label"
  docker run --rm "${g[@]}" --cpus $CPUS --cpu-shares 256 --memory 40g --memory-swap 40g --label owner=vesuvius \
    -e OMP_NUM_THREADS=$CPUS -e PYTHONPATH=/work/gpucap -e QT_QPA_PLATFORM=offscreen -v "$W":/work -v "$EXT":/ext \
    vesuvius-ml:latest bash -lc "set -o pipefail; $*"
  local rc=$?; echo "[$(ts)] <<< $label rc=$rc"; return $rc
}
s3wait() { local i; for i in $(seq 1 20); do curl -s -o /dev/null -m 20 -w "%{http_code}" "$VOL/.zgroup" | grep -q 200 && return 0; echo "[$(ts)] S3 unreachable (try $i/20), waiting 60 s"; sleep 60; done; return 1; }
for w in "$@"; do
  D=$GB/$w; HD=$W${D#/work}
  [ -f "$HD/quick_done.json" ] && continue
  if [ $(( $(date +%s) - T0 )) -gt $BUDGET ]; then echo "[$(ts)] budget reached; stopping before $w"; exit 0; fi
  mkdir -p "$HD/maps" "$HD/thumbs"
  if [ ! -d "$HD/flatten/tifxyz/flatten.tifxyz" ]; then
    echo "{\"external_surfaces\": [{\"path\": \"/work/spiral_out/$S/$SNAP/$w\"}]}" > "$HD/flatten_input.json"
    run "$w flatten" 1 "cd /opt/villa/lasagna && $LPY fit.py configs/flatten_fast_nofilter.json $D/flatten_input.json --out-dir $D/flatten --device cuda > $D/flatten.log 2>&1; rc=\$?; tail -1 $D/flatten.log; exit \$rc" || continue
  fi
  if [ ! -f "$HD/render.ok" ]; then
    # Network-safe render: a network drop made vc_render_tifxyz return rc=1 after writing a partial, mostly-zero
    # zarr, which an ".zarray exists" check then reused (blank maps for three windings of our first band).
    # Wait for S3, delete any partial render inside the container, mark success with render.ok.
    s3wait || { echo "[$(ts)] ABORT: S3 unreachable for 20 min"; exit 3; }
    run "$w render 66" 0 "rm -rf $D/${w}_66.zarr $D/render.ok; vc_render_tifxyz --volume /work/ctcache/$S --remote-url $VOL --group-idx 0 --scale 1 --segmentation $D/flatten/tifxyz/flatten.tifxyz --num-slices 66 --slice-step 1 --cache-gb 8 --zarr-output $D/${w}_66.zarr > $D/render.log 2>&1; rc=\$?; tail -1 $D/render.log; if [ \$rc -eq 0 ]; then touch $D/render.ok; else rm -rf $D/${w}_66.zarr; fi; exit \$rc" || continue
  fi
  todo=""
  for d in $DEPTHS; do s=$((33 + d - 8)); for M in $MODELS; do
    ls "$HD/maps/"*"__${M}__L66s${s}.tif" >/dev/null 2>&1 || todo="$todo $M:$d"; done; done
  if [ -n "$todo" ]; then
    run "$w ink [$MODELS] x d[$DEPTHS] (GPU)" 1 "cd /work/screen && for md in $todo; do M=\${md%%:*}; d=\${md##*:}; CKPT_DIR=/work/ckpt/ensemble PY=$PY N_LAYERS=66 NATIVE_UM=9.362 VILLA_BATCH=8 TMPDIR=/work/screen/tmp bash /work/bin/run_ink_cpu.sh $D/${w}_66.zarr \$M \$d $D/maps > /dev/null 2>&1 || echo FAIL \$M \$d; done; ls $D/maps | wc -l"
  fi
  run "$w triage v1+v2, score, cleanup" 0 "cd /work/screen && $PY triage_tiles.py $D/triage_quick.json 9.362 $D/maps/*.tif > $D/triage_quick.log 2>&1 && $PY triage_tiles_v2.py $D/triage_v2.json 9.362 8 $D/maps/*.tif >> $D/triage_quick.log 2>&1 && $PY score_winding.py $D $KEEP $FLAG"
done
echo "[$(ts)] ALL DONE quick_screen_v2 $ZB-$ZE ($(( ($(date +%s) - T0) / 60 )) min)"
