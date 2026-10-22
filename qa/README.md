# QA tables

Made by `scripts/compile_qa.py` from the fit metrics, snap reports, meshes and screen markers. Tab-separated, one
header row.

## windings.tsv (960 rows, one per fitted winding)

| column | meaning |
|---|---|
| `scroll`, `volume` | scroll id and CT volume id (9.362 µm voxels) |
| `z0`, `z1` | the 1000-slice z band the winding was fitted in |
| `winding` | winding index within the band's fit, counted outward from the scroll centre |
| `area_3d_cm2` | true mesh area: two triangles per valid quad, summed, × (9.362 µm)² |
| `area_grid_cm2` | the area stored in the tifxyz `meta.json` (valid quads × step²); under-reports, see docs/FAILURE_CASES.md §1 |
| `n_valid` | grid vertices with valid coordinates (snap report) |
| `frac_with_sheet` | fraction of vertices that found a predicted sheet within 15 voxels along the normal |
| `frac_snapped` | fraction of vertices that were actually moved by the snap |
| `median_abs_off_vox`, `p90_abs_off_vox` | median and 90th-percentile snap offset, in voxels |
| `qa_ge_0p85` | 1 if `frac_with_sheet` ≥ 0.85 (the screening set) |
| `screened` | 1 if the winding was ink-screened (maps written); every such winding is on a reviewed sheet in docs/REVIEW_LOG.md |

## bands.tsv (8 rows, one per band)

`satisfied_tracks_fraction` and `satisfied_track_points_fraction` are the fit quality reported by villa
`fit_spiral`. The remaining columns are counts and areas, totalled over the band: all windings, windings with
`qa_ge_0p85`, and screened windings.
