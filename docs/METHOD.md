# Method

One GB10 machine (NVIDIA Grace-Blackwell, aarch64, 128 GB unified memory), Docker, the public open-data bucket.
Everything runs in one image built from villa (`scripts/build/`). Containers are capped at 9 CPUs and 40 GB RAM, and GPU
processes at a 14 GB memory pool (`scripts/gpucap/sitecustomize.py`, `VES_GPU_POOL_GB`), so the work can share a machine.

## Inputs

| input | source |
|---|---|
| CT volumes | PHerc0257 `20250821151750`, PHerc0813 `20250821151723` (9.362 µm), streamed from S3 by `vc_render_tifxyz` |
| surface tracks | `spiral_datasets/<scroll>/<volume>/tracks/<scroll>_<volume>_surface_m7_L0_th0.2.dbm` (dl.ash2txt.org) |
| sheet normals | Lasagna `nx`, `ny`, `grad_mag` group 2 (`lasagna_scale` 4), from the open-data catalog |
| scroll axis | Alexey Drobkov's manual umbilici (`herculaneum-umbilici`) |
| spiral sense | from the catalog's `z_direction_is_top_to_bottom` / `left_handed_coordinates` (both false → CW) |

`scripts/fetch_scroll_inputs.sh` downloads tracks and normals for one scroll and creates the store names `fit_spiral`
expects (see [FAILURE_CASES.md §3](FAILURE_CASES.md#3-lasagna-store-names-and-duplicate-pools)).

## 1. Fit (`fit_band.sh`, `fit_snap_band.sh`)

villa `fit_spiral` on one 1000-slice z band, with tracks as the winding-placing input:

```json
{"z_begin": Z0, "z_end": Z1, "input_disable_patches": true, "input_use_tracks": true,
 "input_use_outer_shell": false, "input_use_fibers": false, "input_use_winding_inference": false,
 "input_use_verified_patches": false, "input_use_pcl_absolute": false, "input_use_pcl_relative": false,
 "input_use_pcl_same_winding": false, "input_use_pcl_drawn_control_points": false,
 "loss_weight_shell_outer": 0, "dense_spacing_mode": "grad_mag", "loss_weight_dense_spacing": 0}
```

All other settings are villa defaults at the tested commit. Why these differ from the published PHerc0343 overrides:
[FAILURE_CASES.md §2](FAILURE_CASES.md#2-the-published-first-letters-fit-settings-no-longer-place-windings).
On a GB10 one band takes ~40-50 min (≈3.5 min warm-up, then ~14.6 it/s) and ~2.3 GB of GPU memory. Fit quality
reported by `fit_spiral` (satisfied-track fraction) was 11.25-15.69 % per band ([RESULTS.md](RESULTS.md)).

Each band yields 120 windings as tifxyz. `fit_snap_band.sh` then runs Nieuwlaar's `mesh/snap_meshes.py`: every vertex
moves along its normal to the nearest predicted sheet, with the script's default parameters (`--max-off 15`
voxels, `--jump 6`, `--sigma 1`; each mesh's `meta.json` records them under `snap`). The
snap report gives, per winding, the fraction of vertices with a predicted sheet in reach (`frac_with_sheet`), the
fraction actually moved, and the median / 90th-percentile offset. For PHerc0813 the screening set is every winding
with `frac_with_sheet` ≥ 0.85. PHerc0257 was screened first, by winding range (z9000 and z10000
w010-w090 + w100, z11000 w010-w089, z12000 w010-w061), which mostly coincides with that set (22 of its 296 screened
windings are below 0.85); per-band counts are in [RESULTS.md](RESULTS.md).

## 2. Screen (`screen_band.sh`)

Per winding, resumable, with a time budget per job:

1. **Flatten:** Lasagna `fit.py configs/flatten_fast_nofilter.json` on the snapped mesh (GPU). The flattened grid is
   isometric at 20 voxels per step within ~3 %, so the render below is at native scale.
2. **Render:** `vc_render_tifxyz --num-slices 66 --slice-step 1`: layer k samples the CT k - 32.5 voxels along the
   surface normal (Nieuwlaar's 66-layer convention). The CT is streamed from S3. A render counts as done only after
   rc=0 (`render.ok`).
3. **Ink:** Nieuwlaar's `ink/scripts/run_ink.sh` (eager mode, `--no-compile`) at `NATIVE_UM=9.362`, two models and
   two depths, each model in both directions (reverse = reading side, forward = blind side):

   | model | checkpoint | source |
   |---|---|---|
   | `dnative` | `dense_native-016000`, rebuilt from the public safetensors release | `Nieuwlaar/ink9um-dense-native` |
   | `hybrid_3d2d-seed42` | `hybrid_3d2d-seed42_step-075000.pth` | `scrollprize/ink_9um` |

   Depth d = centre layer - 33 (positive = away from the scroll axis); the model window starts at layer d + 25
   (map names `L66s26` for d = +1, `L66s28` for d = +3). d = +1 is the depth of the published PHerc0343 image (his
   ensemble statistics use d = +1); d = +3 was added as a second depth. That gives 8 maps per winding.
4. **Keep:** 1/4 and 1/8 thumbnails of all 8 maps. The 66-layer render (~1-1.5 GB) and the full maps are deleted to
   keep disk use flat. A per-winding periodicity score is logged but decides nothing
   ([FAILURE_CASES.md §4](FAILURE_CASES.md#4-a-periodicity-triage-score-that-failed-calibration)).

A quick screen takes 2.7-5 min of GPU time per winding, and a band of ~80 good windings ~3.6-6.7 h.

## 3. Review (`review_sheets.py`)

Sheets of 1-22 windings (inner windings are small) at 150-200 µm per pixel. Each tile shows one winding: the mean of
its four maps (2 models × 2 depths) for the reading side, above the same for the blind side, each stretched to its
1-99 % range. Sheets are sized to about 1.15 MP, the largest image the reviewing vision model views unshrunk
([FAILURE_CASES.md §7](FAILURE_CASES.md#7-review-images-that-are-silently-downscaled)); by our calculation 23 of the
110 were somewhat larger and were seen shrunk by up to 11 %. The first tile of every sheet is
the known-text control: the same two models at d = +1 on the published PHerc0343 First Letters mesh, at the same
scale. A sheet counts only if the control's letter rows are visible on it.

The rule was fixed before any sheet was reviewed:

- **Candidate:** at least two roughly parallel rows of discrete, stroke-like marks over at least 1 cm, not explained
  by map borders, cracks, fibres or blocky edge artefacts.
- **Structure, not text:** a feature that recurs at the same place on consecutive windings (a physical feature of the
  scroll seen through several layers).
- **Confirmation (candidates only):** all four models (both villa hybrids, dense-native and Hecate) at several
  depths, a mesh-distance check
  ([FAILURE_CASES.md §6](FAILURE_CASES.md#6-one-sheet-sampled-by-two-windings)), and an independent second review
  before anything is called text.

The review was done by the vision model of the AI agent that ran this work, not by a human papyrologist. Each sheet,
the windings on it and what was seen on it are listed in [REVIEW_LOG.md](REVIEW_LOG.md).

## 4. Known-text reproduction (`repro_pherc0343/`)

Before screening, the pipeline reproduced the published PHerc0343 First Letters image from Nieuwlaar's published mesh
on this hardware: the same CT contrast stretch (26 / 164), the four ink models at d = +1, his ensemble and image
scripts with his flags, then a pixel comparison with his published PNG (`repro_compare.py`): ink-overlay
correlation r = 0.871 and grey correlation r = 0.972 (pass ≥ 0.70); the same letter clusters appear in both annotated
rows. Our overlay is somewhat weaker: it marks 3.4 % of pixels as ink, against 4.8 % in his image.

## 5. QA tables (`compile_qa.py`)

Reads the fit metrics, snap reports, meshes and screen markers and writes `windings.tsv` / `bands.tsv` (columns in
[../qa/README.md](../qa/README.md)). Areas are true 3D mesh areas, not the stored `area_cm2`
([FAILURE_CASES.md §1](FAILURE_CASES.md#1-spiral-fitting-tifxyz-area-and-scale)).
