#!/usr/bin/env bash
# repro_run_cpu.sh: reproduce the PHerc0343 First Letters image (Nieuwlaar, MIT) from his published mesh on a GB10 node,
# CPU part (<= 6 CPUs, 22 GB RAM, no GPU): mesh sha256 check, 66-layer render (CT streamed from S3), the three villa
# models at d=+1, ensemble_maps, make_submission_image with his flags, comparison with his published PNG.
# Usage: setsid nohup bash scripts/repro_pherc0343/repro_run_cpu.sh > repro.log 2>&1 < /dev/null &
set -uo pipefail
ts() { date -u +%FT%TZ; }
W=~/vesuvius/work; EXT=~/vesuvius/ext; R=/ext/pherc343-first-letters
N=concat_w047-w048_R5B2_z9500-11000; NR=${N}_66
CT_URL=https://vesuvius-challenge-open-data.s3.us-east-1.amazonaws.com/PHerc0343/volumes/20250521140437-8.640um-1.2m-116keV-masked.zarr
PY=/opt/villa/vesuvius/.venv/bin/python
mkdir -p "$W/repro/maps" "$W/repro/images" "$W/repro/image" "$W/repro/ctcache" "$W/repro/tmp"
cp "$(dirname "$0")/repro_compare.py" "$W/repro/repro_compare.py"
crun() {
  local label="$1"; shift
  echo "[$(ts)] >>> $label"
  docker run --rm --cpus 6 --cpu-shares 256 --memory 22g --memory-swap 22g --label owner=vesuvius \
    -e OMP_NUM_THREADS=6 -e QT_QPA_PLATFORM=offscreen -e HF_HOME=/work/hf -v "$W":/work -v "$EXT":/ext \
    vesuvius-ml:latest bash -lc "$*"
  local rc=$?; echo "[$(ts)] <<< $label rc=$rc"; return $rc
}
crun "verify published mesh sha256" "cd $R/outputs && sha256sum -c SHA256SUMS 2>&1 | tail -12" || exit 1
if [ ! -f "$W/repro/$NR.zarr/0/.zarray" ]; then
  crun "render 66 layers (CT streamed from S3)" "vc_render_tifxyz --volume /work/repro/ctcache --remote-url $CT_URL --group-idx 0 --scale 1 --segmentation $R/outputs/$N.tifxyz --num-slices 66 --slice-step 1 --cache-gb 8 --zarr-output /work/repro/$NR.zarr 2>&1 | tail -15" || exit 1
fi
crun "render shape" "$PY -c \"import zarr; a=zarr.open('/work/repro/$NR.zarr/0', mode='r'); print(a.shape, a.dtype)\""
# CPU copy of run_ink.sh: identical except --no-compile for the villa models (torch.compile is a CUDA-path option)
sed 's/--direction both \\/--direction both --no-compile \\/' "$EXT/pherc343-first-letters/ink/scripts/run_ink.sh" > "$W/repro/run_ink_cpu.sh"
cp "$EXT/pherc343-first-letters/ink/scripts/hecate_prep.py" "$W/repro/"
for M in hybrid_3d2d-seed42 hybrid_3d2d-seed43 dnative hecate; do
  crun "ink $M d=+1 (CPU)" "cd /work/repro && CKPT_DIR=/work/ckpt/ensemble PY=$PY HECATE_PY=/work/ckpt/ensemble/hecate.py PREP_PY=/work/repro/hecate_prep.py N_LAYERS=66 NATIVE_UM=8.64 VILLA_BATCH=4 HEC_BATCH=2 HEC_DEVICE=cpu TMPDIR=/work/repro/tmp bash /work/repro/run_ink_cpu.sh /work/repro/$NR.zarr $M 1 /work/repro/maps 2>&1 | tail -6"
done
mkdir -p "$W/repro/tmp"
crun "ensemble_maps (stats from d=+1 only)" "cd /work/repro/images && $PY $R/ink/scripts/ensemble_maps.py --surface /work/repro/$NR.zarr --name $NR --maps /work/repro/maps --out . --stat-depths 1..1 --write-depths 1 2>&1 | tail -8"
crun "make_submission_image (his flags)" "cd $R/outputs && sha256sum $N.tifxyz/x.tif $N.tifxyz/y.tif $N.tifxyz/z.tif $N.tifxyz/meta.json > /work/repro/mesh_sums && cd /work/repro && $PY $R/ink/scripts/make_submission_image.py --mesh $R/outputs/$N.tifxyz --umbilicus $R/inputs/umbilicus_PHerc0343.json --ct /work/repro/$NR.zarr --overlay-style dimmed-ct --caption compact --geometry-sums /work/repro/mesh_sums --area 380,105,6021,2560 --max-cm2 12 --ct-layer d+1 --ink /work/repro/maps/${NR}__dnative__L66s26_reverse.tif /work/repro/maps/${NR}__hecate__L66zc33.50_reverse.png /work/repro/maps/${NR}__hybrid_3d2d-seed42__L66s26_reverse.tif /work/repro/maps/${NR}__hybrid_3d2d-seed43__L66s26_reverse.tif --ensemble --ink-stats /work/repro/images/${NR}__stats.json --rows $R/inputs/${N}_rows.json --letters $R/inputs/${N}_letter_boxes.json --letter-markers off --sizes-csv /work/repro/image/${N}_letter_sizes.csv --out-dir /work/repro/image --force 2>&1 | tail -12"
crun "compare with the published image" "cd /work/repro && ls image && $PY repro_compare.py $R/outputs/$N.png \$(ls /work/repro/image/*.png | head -1) $R/outputs/$N.json /work/repro/image 2>&1 | tail -30"
echo "[$(ts)] DONE repro_run_cpu"
