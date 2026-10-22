#!/usr/bin/env bash
# setup_workdir.sh - one-time layout the other scripts expect (CPU/network, a few minutes; no GPU):
#   $ROOT/villa                              ScrollPrize/villa @ VILLA_SHA (source for scripts/build/)
#   $ROOT/ext/pherc343-first-letters         Nieuwlaar's PHerc0343 First Letters package (MIT) @ PHERC343_SHA
#   $ROOT/ext/herculaneum-umbilici           Alexey Drobkov's manual scroll axes @ UMBILICI_SHA
#   $ROOT/work/bin/run_ink_cpu.sh            his ink/scripts/run_ink.sh + --no-compile (eager mode: the reproduction
#                                            began on CPU; the GPU screen kept the same validated runner. torch.compile
#                                            was not tested on GB10, although the image has Triton 3.7.1)
#   $ROOT/work/gpucap/sitecustomize.py       per-process GPU memory cap (active when VES_GPU_POOL_GB is set)
#   $ROOT/work/screen/*.py                   screening helpers (scripts/screen/), run inside the container
#   $ROOT/work/repro/                        PHerc0343 reproduction dir (run_ink_cpu.sh + his hecate_prep.py)
#   $ROOT/work/{ckpt/ensemble,data,spiral_out,ctcache,screen/tmp,repro/tmp}
# ROOT defaults to ~/vesuvius: every script uses ~/vesuvius/{villa,ext,work}. Existing clones are only checked.
# Usage: bash scripts/setup_workdir.sh
set -euo pipefail
ROOT=${ROOT:-$HOME/vesuvius}
HERE=$(cd "$(dirname "$0")" && pwd)
VILLA_SHA=d63d3e9687f0; PHERC343_SHA=e8370f1f88a2; UMBILICI_SHA=de7642ac9b38   # the commits these scripts ran on
clone() {  # <url> <dir> <sha>
  local url=$1 dir=$2 sha=$3 have
  if [ ! -d "$dir/.git" ]; then git clone -q "$url" "$dir"; git -C "$dir" checkout -q "$sha"; fi
  have=$(git -C "$dir" rev-parse --short=12 HEAD)
  if [ "$have" = "$sha" ]; then echo "ok    $dir @ $have"; else echo "NOTE  $dir @ $have (tested with $sha)"; fi
}
mkdir -p "$ROOT/ext" "$ROOT/work"/{bin,gpucap,ckpt/ensemble,data,spiral_out,ctcache,screen/tmp,repro/tmp}
clone https://github.com/ScrollPrize/villa.git "$ROOT/villa" "$VILLA_SHA"
clone https://github.com/Nieuwlaar/pherc343-first-letters.git "$ROOT/ext/pherc343-first-letters" "$PHERC343_SHA"
clone https://github.com/AlexeyDrobkovStrikesBack/herculaneum-umbilici.git "$ROOT/ext/herculaneum-umbilici" "$UMBILICI_SHA"
R="$ROOT/ext/pherc343-first-letters/ink/scripts"
sed 's/--direction both \\/--direction both --no-compile \\/' "$R/run_ink.sh" > "$ROOT/work/bin/run_ink_cpu.sh"
grep -q -- '--no-compile' "$ROOT/work/bin/run_ink_cpu.sh" || { echo "ABORT: run_ink.sh changed upstream (no '--direction both' line)"; exit 2; }
cp "$HERE/gpucap/sitecustomize.py" "$ROOT/work/gpucap/"
cp "$HERE"/screen/*.py "$ROOT/work/screen/"
for d in bin repro; do cp "$ROOT/work/bin/run_ink_cpu.sh" "$ROOT/work/$d/" 2>/dev/null || true; cp "$R/hecate_prep.py" "$ROOT/work/$d/"; done
echo "next: build the image (scripts/build/build_vc3d.sh, then build_py.sh), fetch the checkpoints (README step 3)"
echo "ALL DONE setup_workdir $ROOT"
