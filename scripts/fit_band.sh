#!/usr/bin/env bash
# fit_band.sh [S=<scroll>] [z_begin] [z_end] - spiral-fit one 1000-slice z band (villa fit_spiral) with settings adapted
# from the PHerc0343 First Letters recipe to current villa main (overrides: OV below; docs/METHOD.md and
# docs/FAILURE_CASES.md). Default scroll PHerc0257. Scroll table = volume id + the open-data catalog's
# z_direction_is_top_to_bottom / left_handed_coordinates (metadata.json); the spiral sense follows from them
# (villa spiral-fitting README: CW when equal, ACW when they differ).
# Resources per container (edit for your machine): --cpus 9, 40 GB RAM, one GPU process capped at a 14 GB pool
# (scripts/gpucap). One fit takes ~40-50 min on a GB10 (DGX Spark class) GPU, ~2.3 GB GPU memory.
# Steps: dataset layout -> fit one band (GPU; fit_spiral builds its own Lasagna resident pool) -> list meshes.
# Usage: bash scripts/fit_band.sh [S=PHerc0813] [z_begin] [z_end]
set -uo pipefail
ts() { date -u +%FT%TZ; }
S=PHerc0257; if [[ "${1:-}" == S=* ]]; then S=${1#S=}; shift; fi
case $S in
  PHerc0257) V=20250821151750; ZTB=false; LH=false ;;
  PHerc0813) V=20250821151723; ZTB=false; LH=false ;;
  *) echo "[$(ts)] ABORT: unknown scroll $S"; exit 2 ;;
esac
if [ "$ZTB" = "$LH" ]; then SENSE=CW; else SENSE=ACW; fi
ZB=${1:-9000}; ZE=${2:-10000}
W=~/vesuvius/work; EXT=~/vesuvius/ext
DS=$W/datasets/$S; OUT=$W/spiral_out/$S
SP=/opt/villa/spiral-fitting/.venv/bin/python
DBM=tracks/${S}_${V}_surface_m7_L0_th0.2.dbm
[ -s "$W/data/$S/$DBM" ] || { echo "[$(ts)] ABORT: missing $W/data/$S/$DBM"; exit 2; }
[ -s "$W/data/$S/umbilicus_alexey.json" ] || { echo "[$(ts)] ABORT: missing umbilicus for $S"; exit 2; }
mkdir -p "$DS" "$OUT"
# dataset layout (relative symlinks stay valid inside the container's /work mount)
[ -e "$DS/tracks" ] || ln -s ../../data/$S/tracks "$DS/tracks"
[ -e "$DS/lasagna_inputs" ] || ln -s ../../data/$S/lasagna "$DS/lasagna_inputs"
cp "$W/data/$S/umbilicus_alexey.json" "$DS/umbilicus.json"
cat > "$DS/spiral-scroll.json" <<JSON
{
  "schema_version": 1,
  "name": "$S",
  "voxel_size_um": 9.362,
  "z_direction_is_top_to_bottom": $ZTB,
  "left_handed_coordinates": $LH,
  "spiral_outward_sense": "$SENSE",
  "normal_zarr_group": "2",
  "lasagna_scale": 4,
  "paths": {"tracks_dbm": "$DBM"}
}
JSON
run() {  # run <label> <gpu 0|1> <cmd>
  local label="$1" gpu="$2"; shift 2
  local g=(); [ "$gpu" = 1 ] && g=(--gpus all -e VES_GPU_POOL_GB=14)
  echo "[$(ts)] >>> $label"
  docker run --rm "${g[@]}" --cpus 9 --cpu-shares 256 --memory 40g --memory-swap 40g --shm-size 8g --label owner=vesuvius \
    -e OMP_NUM_THREADS=9 -e PYTHONPATH=/work/gpucap -v "$W":/work -v "$EXT":/ext vesuvius-ml:latest bash -lc "$*"
  local rc=$?; echo "[$(ts)] <<< $label rc=$rc"; return $rc
}
df -h / | tail -1
# No separate "pack resident pools" step: fit_spiral builds its own pool under the las_008_* name it looks up
# (a PHerc0257_*-named pack is an unused 7.8 GB duplicate). Pools are deleted after each fit
# (scripts/cleanup_pools.sh) to keep disk use flat.
echo "[$(ts)] $S volume $V sense $SENSE (catalog z_top_to_bottom=$ZTB left_handed=$LH) band z[$ZB,$ZE)"
OV="{\"z_begin\": $ZB, \"z_end\": $ZE, \"input_disable_patches\": true, \"input_use_tracks\": true, \"input_use_outer_shell\": false, \"input_use_fibers\": false, \"input_use_winding_inference\": false, \"input_use_verified_patches\": false, \"input_use_pcl_absolute\": false, \"input_use_pcl_relative\": false, \"input_use_pcl_same_winding\": false, \"input_use_pcl_drawn_control_points\": false, \"loss_weight_shell_outer\": 0, \"dense_spacing_mode\": \"grad_mag\", \"loss_weight_dense_spacing\": 0}"
FLOG=/work/spiral_out/$S/fit_z${ZB}_${ZE}.log
run "fit_spiral $S z[$ZB,$ZE) (GPU)" 1 "cd /opt/villa/spiral-fitting && FIT_SPIRAL_CONFIG_OVERRIDES='$OV' FIT_SPIRAL_OUT_DIR=/work/spiral_out/$S timeout 10500 $SP fit_spiral.py --dataset /work/datasets/$S > $FLOG 2>&1; rc=\$?; grep -vE '^\s*$' $FLOG | tail -80; exit \$rc" || { echo "[$(ts)] FIT FAILED"; exit 2; }
run "list outputs" 0 "find /work/spiral_out/$S -maxdepth 4 -type d -name '*tifxyz*' | head -20; find /work/spiral_out/$S -maxdepth 3 -name '*.json' | head -10"
df -h / | tail -1
echo "[$(ts)] DONE fit_band $S $ZB-$ZE"
