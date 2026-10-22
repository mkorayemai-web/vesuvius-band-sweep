#!/usr/bin/env bash
# band_screen.sh [S=<scroll>] <z_begin> <z_end> <depths_csv> <winding...>   (default scroll PHerc0257)
# Band preparation, idempotent and resumable: spiral fit (if missing; scripts/fit_band.sh) -> m7 surface-prediction
# slab chunks for the band -> snap all windings (Nieuwlaar's mesh/snap_meshes.py) -> snap_report.tsv.
# With windings listed it also runs our FIRST screen version per winding (flatten, 66-layer render, 3 villa models,
# periodicity triage v1); the survey used scripts/screen_band.sh (streaming) for that part instead.
# Caps: one container at a time, --cpus 9, shares 256, 40 GB, 1 GPU process with a 14 GB pool; job budget 2h40m.
set -uo pipefail
ts() { date -u +%FT%TZ; }
T0=$(date +%s); BUDGET=$((160*60))
S=PHerc0257; if [[ "${1:-}" == S=* ]]; then S=${1#S=}; shift; fi
case $S in PHerc0257) V=20250821151750 ;; PHerc0813) V=20250821151723 ;; *) echo "[$(date -u +%FT%TZ)] ABORT: unknown scroll $S"; exit 2 ;; esac
ZB=$1; ZE=$2; DEPTHS=$(echo "$3" | tr ',' ' '); shift 3
W=~/vesuvius/work; EXT=~/vesuvius/ext
VOL=https://vesuvius-challenge-open-data.s3.us-east-1.amazonaws.com/$S/volumes/${V}-9.362um-1.2m-113keV-masked.zarr
M7=s3://vesuvius-challenge-open-data/$S/representations/predictions/surfaces/${V}-surface-20260413222639-surface-m7-L0-th0.2.zarr
LM7=/work/data/$S/m7_slab.zarr
PY=/opt/villa/vesuvius/.venv/bin/python; LPY=/opt/villa/lasagna/.venv/bin/python
if [ "$S" = PHerc0257 ] && [ "$ZB-$ZE" = "9000-10000" ]; then SNAP=snapped; GB=/work/screen/$S; else SNAP=snapped_${ZB}_${ZE}; GB=/work/screen/$S/b${ZB}; fi
mkdir -p "$W/screen/tmp" "$W${GB#/work}"
cp "$(dirname "$0")/screen/triage_tiles.py" "$W/screen/"
run() {  # run <label> <gpu 0|1> <cmd>
  local label="$1" gpu="$2"; shift 2
  local g=(); [ "$gpu" = 1 ] && g=(--gpus all -e VES_GPU_POOL_GB=14)
  echo "[$(ts)] >>> $label"
  docker run --rm "${g[@]}" --cpus 9 --cpu-shares 256 --memory 40g --memory-swap 40g --label owner=vesuvius \
    -e OMP_NUM_THREADS=9 -e PYTHONPATH=/work/gpucap -e QT_QPA_PLATFORM=offscreen -v "$W":/work -v "$EXT":/ext \
    vesuvius-ml:latest bash -lc "set -o pipefail; $*"
  local rc=$?; echo "[$(ts)] <<< $label rc=$rc"; return $rc
}
over() { [ $(( $(date +%s) - T0 )) -gt $BUDGET ]; }
# 0. pre-flight: the node must reach the open-data bucket (during a 2-hour Wi-Fi outage every stream failed
#    silently); abort instead of producing snaps/renders from missing data.
curl -s -o /dev/null -m 20 -w "%{http_code}" "$VOL/.zgroup" | grep -q 200 || { echo "[$(ts)] ABORT: S3 unreachable from $(hostname)"; exit 3; }
# 1. fit
FITDIR=$(ls -d $W/spiral_out/$S/*_${S}_slice-${ZB}-${ZE}_0-patch 2>/dev/null | head -1)
if [ -z "$FITDIR" ] || [ ! -d "$FITDIR/meshes/fitted" ]; then
  echo "[$(ts)] fit band $ZB-$ZE"; bash "$(dirname "$0")/fit_band.sh" "S=$S" "$ZB" "$ZE" || { echo "[$(ts)] fit FAILED"; exit 2; }
  FITDIR=$(ls -d $W/spiral_out/$S/*_${S}_slice-${ZB}-${ZE}_0-patch | head -1)
fi
FIT=/work${FITDIR#$W}
grep -E "satisfied_tracks|satisfied_track_points|winding range" "$FITDIR/../fit_z${ZB}_${ZE}.log" 2>/dev/null | tail -3
# 2. m7 slab rows for this band, 3. snap
C0=$(( (ZB - 15) / 192 )); C1=$(( (ZE + 15) / 192 ))
if [ ! -f "$W/spiral_out/$S/$SNAP/snap_report.tsv" ]; then
  run "m7 slab chunk rows $C0..$C1" 0 "mkdir -p $LM7/0 && for f in .zattrs .zgroup; do [ -f $LM7/\$f ] || aws s3 cp --no-sign-request --only-show-errors $M7/\$f $LM7/\$f; done && [ -f $LM7/0/.zarray ] || aws s3 cp --no-sign-request --only-show-errors $M7/0/.zarray $LM7/0/.zarray; for zc in \$(seq $C0 $C1); do aws s3 sync --no-sign-request --only-show-errors $M7/0/\$zc/ $LM7/0/\$zc/ || exit 4; n=\$(find $LM7/0/\$zc -type f | wc -l); echo row \$zc files \$n; [ \$n -gt 0 ] || exit 5; done; du -sh $LM7" || exit 1
  run "snap band $ZB-$ZE" 0 "cd $FIT/meshes && ls -d fitted/w[0-9][0-9][0-9] | xargs -n1 basename > /work/spiral_out/$S/windings_${ZB}_${ZE}.txt && SURF_ZARR=$LM7 $PY /ext/pherc343-first-letters/mesh/snap_meshes.py $FIT/meshes/fitted $S /work/spiral_out/$S/$SNAP --windings /work/spiral_out/$S/windings_${ZB}_${ZE}.txt --z0 $ZB --z1 $ZE --level 0 --procs 8 2>&1 | tail -3" || exit 1
fi
# 4. per winding
for w in "$@"; do
  if over; then echo "[$(ts)] budget reached; stopping before $w"; break; fi
  D=$GB/$w; HD=$W${D#/work}; mkdir -p "$HD/maps"
  if [ ! -d "$HD/flatten/tifxyz/flatten.tifxyz" ]; then
    echo "{\"external_surfaces\": [{\"path\": \"/work/spiral_out/$S/$SNAP/$w\"}]}" > "$HD/flatten_input.json"
    run "$w flatten" 1 "cd /opt/villa/lasagna && $LPY fit.py configs/flatten_fast_nofilter.json $D/flatten_input.json --out-dir $D/flatten --device cuda > $D/flatten.log 2>&1; rc=\$?; tail -2 $D/flatten.log; exit \$rc" || continue
  fi
  if [ ! -f "$HD/${w}_66.zarr/0/.zarray" ]; then
    run "$w render 66" 0 "vc_render_tifxyz --volume /work/ctcache/$S --remote-url $VOL --group-idx 0 --scale 1 --segmentation $D/flatten/tifxyz/flatten.tifxyz --num-slices 66 --slice-step 1 --cache-gb 8 --zarr-output $D/${w}_66.zarr > $D/render.log 2>&1; rc=\$?; tail -2 $D/render.log; exit \$rc" || continue
  fi
  todo=""
  for d in $DEPTHS; do
    s=$((33 + d - 8))
    for M in hybrid_3d2d-seed42 hybrid_3d2d-seed43 dnative; do
      ls "$HD/maps/"*"__${M}__L66s${s}.tif" >/dev/null 2>&1 || todo="$todo $M:$d"
    done
  done
  if [ -n "$todo" ]; then
    run "$w villa ink depths [$DEPTHS] (GPU)" 1 "cd /work/screen && for md in $todo; do M=\${md%%:*}; d=\${md##*:}; CKPT_DIR=/work/ckpt/ensemble PY=$PY N_LAYERS=66 NATIVE_UM=9.362 VILLA_BATCH=8 TMPDIR=/work/screen/tmp bash /work/bin/run_ink_cpu.sh $D/${w}_66.zarr \$M \$d $D/maps > /dev/null 2>&1 || echo FAIL \$M \$d; done; ls $D/maps | wc -l"
  fi
  run "$w triage" 0 "cd /work/screen && $PY triage_tiles.py $D/triage_all.json 9.362 $D/maps/*.tif > $D/triage_all.log 2>&1; rc=\$?; tail -1 $D/triage_all.log; exit \$rc"
done
echo "[$(ts)] DONE band_screen $ZB-$ZE ($(( ($(date +%s) - T0) / 60 )) min)"
