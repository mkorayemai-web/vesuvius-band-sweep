# vesuvius-band-sweep

Fitted, snapped and quality-checked papyrus-sheet surfaces for two Herculaneum scrolls, the scripts that made them on an
NVIDIA GB10 (aarch64, DGX Spark class) machine, and a documented negative ink screen of those surfaces.

| | PHerc0257 (volume 20250821151750) | PHerc0813 (volume 20250821151723) |
|---|---|---|
| z range (slices, 9.362 µm) | 9000-13000 (4 bands of 1000) | 7000-11000 (4 bands of 1000) |
| fitted windings (tifxyz) | 480 | 480 |
| true 3D surface area | 4,194 cm² | 4,909 cm² |
| windings with ≥ 85 % of vertices on a predicted sheet | 308 | 295 |
| ink-screened + visually reviewed | 296 windings, 1,829 cm² | 261 windings, 2,137 cm² |
| text found | none | none |

## What is here

1. **Surfaces ([release v1](https://github.com/mkorayemai-web/vesuvius-band-sweep/releases/tag/v1), asset `vesuvius-band-sweep-meshes-v1.tar.gz`, 151 MB).** 960 spiral-fitted windings snapped onto
   the predicted sheet surface, as tifxyz (x/y/z.tif + meta.json), with the per-band snap reports. They can go
   straight into ink detection (flatten → render → ink); together they replace ~6 GPU-hours of fitting on a GB10.
2. **Per-winding QA tables (`qa/`).** True 3D area, sheet support, snap offsets and screening status for every winding
   ([qa/README.md](qa/README.md)).
3. **A negative-results map ([docs/RESULTS.md](docs/RESULTS.md)).** 557 windings (3,966 cm²) were screened with two
   public First Letters ink models at two depths, both sides. Every screened winding was reviewed visually (per side, the mean
   of its four maps), by the vision model of the AI agent that ran this work, on 110 sheets whose first tile is a
   known-text control (PHerc0343). The per-sheet record is [docs/REVIEW_LOG.md](docs/REVIEW_LOG.md). No rows of letters
   were seen. A human pass over the same sheets has not been done yet. This says where these models, at these depths,
   do not show ink. It does not say there is no text.
4. **A metadata finding ([docs/FAILURE_CASES.md](docs/FAILURE_CASES.md#1-spiral-fitting-tifxyz-area-and-scale)).** The tifxyz writer in villa's
   spiral-fitting stores `area_vx2 = valid quads × step²` and `scale = 1/step`, but fitted windings are not sampled at
   that step (measured median vertex spacing 14-37 voxels against a nominal 20). The stored `area_cm2` under-reports
   the true mesh area by a median of 1.68× (5-95 %: 1.16-2.09×, all 960 windings). `scripts/compile_qa.py` measures the
   true area. After Lasagna flattening the grid is regular again (19.4-19.7 voxels against 20), so renders made through
   the flatten step have the right scale.
5. **A GB10 / aarch64 run kit ([docs/METHOD.md](docs/METHOD.md)).** Image builds for aarch64, a per-process GPU memory cap
   for shared machines, network-safe rendering, resumable per-winding screening with a time budget, and an end-to-end reproduction of the published PHerc0343 First Letters image on this
   hardware (ink overlay r = 0.871, grey r = 0.972 against the published image).

## Quick start

All scripts assume `~/vesuvius/{villa,ext,work}`, Docker with the NVIDIA runtime, and the public open-data bucket.
Steps 1-3 are one-time.

```bash
# 1. clone villa, the PHerc0343 package and the scroll axes at the tested commits; lay out ~/vesuvius/work
bash scripts/setup_workdir.sh
# 2. images: VC3D command-line tools, then the Python stage (vesuvius, spiral-fitting, Lasagna, ink inference)
setsid nohup bash scripts/build/build_vc3d.sh > vc3d_build.log 2>&1 < /dev/null &
setsid nohup bash scripts/build/build_py.sh > py_build.log 2>&1 < /dev/null &      # after build_vc3d finishes
# 3. public checkpoints, every file sha256-checked
bash ~/vesuvius/ext/pherc343-first-letters/ink/scripts/fetch_checkpoints.sh \
     ~/vesuvius/ext/pherc343-first-letters/ink/models.tsv ~/vesuvius/work/ckpt/ensemble
# 4. spiral-fit inputs (tracks, Lasagna normals) for one scroll; the first argument is the scroll to free
mkdir -p ~/vesuvius/work/data/none && bash scripts/fetch_scroll_inputs.sh none PHerc0813
# 5. fit one 1000-slice band, export the windings, snap them onto the predicted sheet (~45-50 min GPU)
bash scripts/fit_snap_band.sh S=PHerc0813 10000 11000
# 6. screen: flatten -> 66-layer render -> 2 models x depths d=+1,+3, both sides -> 1/4 and 1/8 thumbnails,
#    for every winding with >= 85 % sheet support
bash scripts/screen_band.sh S=PHerc0813 10000 11000 dnative,hybrid_3d2d-seed42 1,3 QA0.85
# 7. review sheets; the first tile of every sheet is the PHerc0343 known-text control
#    (control_dir = maps from scripts/repro_pherc0343, i.e. ~/vesuvius/work/repro/maps). The SHEET_* settings are
#    those of our final sheets: ~150 um/px and <= ~1.15 MP, so that an AI image viewer shows them unshrunk. Without
#    them the script writes larger PNG sheets at 75 um/px for human viewing.
SHEET_FMT=jpg SHEET_SCALE=0.5 SHEET_MAXW=2300 SHEET_MAXH=2000 SHEET_KB=230 \
python3 scripts/review_sheets.py sheets/p0813_z10000 ~/vesuvius/work/repro/maps \
        0813-z10000=$HOME/vesuvius/work/screen/PHerc0813/b10000
# 8. per-winding / per-band QA tables with the true 3D area
python3 scripts/compile_qa.py qa_out
```

Every script prints its usage and resource limits in its header. GPU steps run one container at a time with
`--cpus 9 --memory 40g` and a GPU memory cap (`VES_GPU_POOL_GB`, default 14 GB).

To use only the released surfaces: download the asset from [release v1](https://github.com/mkorayemai-web/vesuvius-band-sweep/releases/tag/v1), check it against `SHA256SUMS`, and point any tifxyz
tool (VC3D, Lasagna flatten, `vc_render_tifxyz`) at a winding directory.

## Hardware and cost

One GB10 (128 GB unified memory). Per 1000-slice band: fit ~40-50 min (~2.3 GB GPU memory); per winding: quick screen
2.7-5 min. Every container ran with ≤ 9 CPUs and ≤ 40 GB RAM next to other jobs. No cloud spend.

## Credits

- Erwin Nieuwlaar, [pherc343-first-letters](https://github.com/Nieuwlaar/pherc343-first-letters) (MIT): the
  PHerc0343 recipe, snap step, 66-layer render convention, ink runner and checkpoint list this work builds on.
- [ScrollPrize/villa](https://github.com/ScrollPrize/villa) (MIT): VC3D, spiral-fitting, Lasagna, the ink models.
- Alexey Drobkov, [herculaneum-umbilici](https://github.com/AlexeyDrobkovStrikesBack/herculaneum-umbilici): scroll axes.
- Checkpoints: `scrollprize/ink_9um`, `scrollprize/hecate`, `Nieuwlaar/ink9um-dense-native` on Hugging Face.

## Data, citation and licence

Data: Giorgio Angelotti, Stephen Parsons, Sean Johnson, Elian Rafael Dal Prà, Johannes Rudolph, Paul Tafforeau,
Alessandro Mirone, Paul Henderson, Hendrik Schilling, Forrest McDonald, David Josey, Youssef Nader, C. Seth Parker,
W. Brent Seales. *Vesuvius Challenge - CT Scans of Herculaneum Papyri.* Vesuvius Challenge.

Code: MIT ([LICENSE](LICENSE)). The surfaces and QA tables are derived from the scan data and stay under its licence,
CC BY-NC 4.0. No CT data and no ink images are redistributed here.

Mohammed Korayem, working with an AI agent setup. Questions and bug reports: GitHub issues.
