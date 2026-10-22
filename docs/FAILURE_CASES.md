# Failure cases and fixes

Problems we hit while fitting and screening PHerc0257 and PHerc0813 on a GB10, with the evidence and what the scripts in
this repository do about each. Commit references are to [ScrollPrize/villa](https://github.com/ScrollPrize/villa).

## 1. spiral-fitting tifxyz area and scale

**Symptom.** `meta.json` of every fitted winding says `scale: [0.05, 0.05]` (one grid step = 20 voxels) and
`area_vx2 = valid quads × 400`. The windings are not sampled at that step, so the stored `area_cm2` is wrong.

**Cause.** `spiral-fitting/tifxyz.py`, `save_tifxyz` (line 445 on main, 2026-10-22) and `save_combined_tifxyz`
(line 588) compute `area_vx2 = int(valid_quad.sum()) * step_size ** 2` and write `scale = 1 / step_size`. That is exact
only for an isometric grid with neighbour spacing `step_size`.

**Evidence.** On the released (snapped) meshes: median 3D distance between neighbouring grid vertices, and true
triangle area ÷ stored area (the same ratios as `qa/windings.tsv`):

| winding | grid spacing, rows × columns (voxels) | true / stored area |
|---|---|---|
| PHerc0813 z10000-11000 w020 | 36.5 × 14.7 | 1.16 |
| PHerc0257 z9000-10000 w040 | 23.4 × 24.6 | 1.63 |
| PHerc0813 z10000-11000 w040 | 36.8 × 26.0 | 2.16 |
| PHerc0813 z10000-11000 w070 | 34.0 × 26.9 | 2.38 |

Over all 960 windings in this release the true area is a median 1.68× the stored area (5-95 %: 1.16-2.09×, range
0.84-2.60×). Before snapping, the same four windings give 1.13, 1.62, 2.15 and 2.37 (snapping adds 0.3-3 %), so the
error comes from the fit export, not from the snap.
Grid-count areas therefore under-state how much papyrus a fit covers. The opposite mistake also happens: measuring
coverage from render rectangles counts their empty margins (about +17 % for our bands).

**What to do.** Measure area on the mesh: `scripts/compile_qa.py` sums the two triangles of every valid quad and
multiplies by (9.362 µm)². Do not size renders from the fitted grid's `scale`. Flatten first: after Lasagna flattening
(`configs/flatten_fast_nofilter.json`, `flatten_output_step` 20) the measured spacing is 19.7 × 19.4 voxels (w040
above), so renders made from the flattened surface are at the volume's native scale within ~3 %. All screening in
this repository renders from flattened surfaces.

## 2. The published First Letters fit settings no longer place windings

villa PR #1651 (merged 2026-08-30) changed the spiral-fit input defaults. With the PHerc0343 First Letters overrides,
current main fits with no winding-placing input at all (villa issue #1716, open). `scripts/fit_band.sh` therefore sets
`input_use_tracks: true` and turns off every input these datasets do not have (`input_use_outer_shell`,
`input_use_fibers`, `input_use_winding_inference`, verified patches, point-cloud inputs). At the tested commit two of the
recipe's keys were also stale: `loss_weight_shell_patch_radius` no longer exists and `dense_spacing_mode` accepts only `grad_mag`
or `winding_model` (not `phase`). Check every override key against `Config().as_dict()` before a long fit.

## 3. Lasagna store names and duplicate pools

`fit_spiral` looks Lasagna stores up only by the names `lasagna_inputs/las_008_{nx,ny,grad_mag}.ome.zarr` (with their
`.respool_*` sidecars). With the catalog names (`PHercXXXX_nx.ome.zarr`, ...) it tries to rebuild a pool from a
missing store. It also builds its own resident pool (~7.8 GB normals + 3.9 GB grad_mag), so a separately packed pool
under another name is an unused duplicate. `fetch_scroll_inputs.sh` creates the expected names;
`cleanup_pools.sh` deletes the pools after each fit to keep disk use flat.

## 4. A periodicity triage score that failed calibration

We tried to rank windings automatically with a tile periodicity score (`scripts/screen/triage_tiles*.py`), relative
to the PHerc0343 known-text control. On real band maps all four windings it flagged in the first screen were map-border
artefacts on 14-16 mm tall maps: 74-89 % of their non-DC power sat at k ≤ 2 cycles per tile, against 11-37 % for the
control. The score did not separate text from borders, so it is only logged; every decision in
[RESULTS.md](RESULTS.md) comes from the visual review.

## 5. Blank maps from a reused partial render

After a network drop, `vc_render_tifxyz` (streaming the CT from S3) returned rc=1 after writing a partial, mostly
empty zarr. A "does `.zarray` exist" check then reused it, and three windings (PHerc0257 z9000-10000 w018-w020) were
screened on blank maps. `screen_band.sh` now waits for S3, deletes any partial render, and treats a render as done
only when it wrote `render.ok` after rc=0. Those three windings were re-screened.

## 6. One sheet sampled by two windings

Adjacent fitted windings can come within ~0.1 mm of each other. A feature then shows up on both and looks like a
consistent signal. This happened with a single row-like feature on PHerc0257 z10000-11000 w063/w064: the two meshes
were ~0.1 mm apart there, and Hecate did not reproduce the feature, so it was rejected.
`scripts/mesh_gap_probe.py` measures the distance from a feature's points to the neighbouring winding surfaces.

## 7. Review images that are silently downscaled

Image viewers, including the vision model used for our review, downscale large images (above ~1.15 MP or 1568 px on
a side), which erases stroke-scale detail. `review_sheets.py` therefore builds sheets at ~150 µm per pixel and about
1.15 MP (settings in the README). Our first PHerc0257 sheets (2026-10-14/15, 1.6-5.8 MP) were shrunk 2-4× by the
viewer; that review was discarded and redone on 47 new sheets. 23 of the 110 counted sheets are slightly above the
limit (shrunk by up to 11 %, by our calculation); every sheet is listed in [REVIEW_LOG.md](REVIEW_LOG.md).

## 8. libvolcomp missing from the installed VC3D tools (older villa only)

At the commit these scripts were tested on (`d63d3e9687f0`, 2026-10-11), `cmake --install --component vc_runtime`
did not install `libvolcomp.so`, so every installed command-line tool failed with "libvolcomp.so: cannot open shared
object file". `scripts/build/fix_volcomp.sh` compiles the vendored codec with the same flags and checks every
installed binary with `ldd`. villa PR #2008 (merged 2026-10-12) fixed the install rule, so builds from later commits do
not need it.

## 9. Jobs tied to a terminal session

A queue runner that writes to an interactive session dies when that session ends. The container it had started
finished its winding, and then nothing started the next one. Start long jobs detached
(`setsid nohup ... > log 2>&1 < /dev/null &`). Every screening step is idempotent (`quick_done.json` per winding), so
re-running the same command resumes where it stopped.
