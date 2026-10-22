#!/usr/bin/env bash
# repro_finish_gpu.sh: GPU part of the PHerc0343 reproduction: GPU probe, Hecate at d=+1 on GPU (16 min on GB10 vs
# 2 h+ on CPU), then ensemble_maps, make_submission_image and the comparison. <= 9 CPUs, 40 GB RAM, 1 GPU process
# with a 14 GB pool (scripts/gpucap guard).
# Usage: setsid nohup bash scripts/repro_pherc0343/repro_finish_gpu.sh > repro_finish.log 2>&1 < /dev/null &
set -uo pipefail
ts() { date -u +%FT%TZ; }
W=~/vesuvius/work; EXT=~/vesuvius/ext; R=/ext/pherc343-first-letters
N=concat_w047-w048_R5B2_z9500-11000; NR=${N}_66
PY=/opt/villa/vesuvius/.venv/bin/python
mkdir -p "$W/gpucap" "$W/repro/tmp" "$W/repro/images" "$W/repro/image"
cp "$(dirname "$0")/../gpucap/sitecustomize.py" "$W/gpucap/sitecustomize.py"
run() {  # run <label> <gpu:0|1> <cmd>
  local label="$1" gpu="$2"; shift 2
  local g=(); [ "$gpu" = 1 ] && g=(--gpus all -e VES_GPU_POOL_GB=14)
  echo "[$(ts)] >>> $label"
  docker run --rm "${g[@]}" --cpus 9 --cpu-shares 256 --memory 40g --memory-swap 40g --label owner=vesuvius \
    -e OMP_NUM_THREADS=9 -e PYTHONPATH=/work/gpucap -e QT_QPA_PLATFORM=offscreen -v "$W":/work -v "$EXT":/ext \
    vesuvius-ml:latest bash -lc "$*"
  local rc=$?; echo "[$(ts)] <<< $label rc=$rc"; return $rc
}
run "GPU probe (sm_121, guard 14 GB)" 1 "$PY -c \"import torch,time; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0), torch.cuda.get_device_capability(0)); x=torch.randn(8192,8192,device='cuda'); t=time.time(); y=x@x; torch.cuda.synchronize(); print('gemm ok', round(time.time()-t,3),'s', float(y.float().abs().mean())); print('max_alloc_GB', torch.cuda.max_memory_allocated()/1e9)\"" || exit 1
run "hecate d=+1 (GPU)" 1 "cd /work/repro && CKPT_DIR=/work/ckpt/ensemble PY=$PY HECATE_PY=/work/ckpt/ensemble/hecate.py PREP_PY=/work/repro/hecate_prep.py N_LAYERS=66 NATIVE_UM=8.64 HEC_BATCH=4 HEC_DEVICE=cuda TMPDIR=/work/repro/tmp bash /work/repro/run_ink_cpu.sh /work/repro/$NR.zarr hecate 1 /work/repro/maps 2>&1 | tail -8" || exit 1
run "ensemble_maps (stats from d=+1 only)" 0 "cd /work/repro/images && $PY $R/ink/scripts/ensemble_maps.py --surface /work/repro/$NR.zarr --name $NR --maps /work/repro/maps --out . --stat-depths 1..1 --write-depths 1 2>&1 | tail -8"
run "make_submission_image (his flags)" 0 "cd $R/outputs && sha256sum $N.tifxyz/x.tif $N.tifxyz/y.tif $N.tifxyz/z.tif $N.tifxyz/meta.json > /work/repro/mesh_sums && cd /work/repro && $PY $R/ink/scripts/make_submission_image.py --mesh $R/outputs/$N.tifxyz --umbilicus $R/inputs/umbilicus_PHerc0343.json --ct /work/repro/$NR.zarr --overlay-style dimmed-ct --caption compact --geometry-sums /work/repro/mesh_sums --area 380,105,6021,2560 --max-cm2 12 --ct-layer d+1 --ink /work/repro/maps/${NR}__dnative__L66s26_reverse.tif /work/repro/maps/${NR}__hecate__L66zc33.50_reverse.png /work/repro/maps/${NR}__hybrid_3d2d-seed42__L66s26_reverse.tif /work/repro/maps/${NR}__hybrid_3d2d-seed43__L66s26_reverse.tif --ensemble --ink-stats /work/repro/images/${NR}__stats.json --rows $R/inputs/${N}_rows.json --letters $R/inputs/${N}_letter_boxes.json --letter-markers off --sizes-csv /work/repro/image/${N}_letter_sizes.csv --out-dir /work/repro/image --force 2>&1 | tail -12"
run "compare with the published image" 0 "cd /work/repro && ls image && $PY repro_compare.py $R/outputs/$N.png \$(ls /work/repro/image/*.png | head -1) $R/outputs/$N.json /work/repro/image 2>&1 | tail -30"
echo "[$(ts)] DONE repro_finish_gpu"
