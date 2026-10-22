#!/usr/bin/env python3
"""compile_qa.py - per-winding and per-band QA tables for the band-sweep package (runs on the node, stdlib only).

Inputs (under WORK = ~/vesuvius/work):
  spiral_out/<scroll>/<fit dir for band>/satisfaction_metrics_fitted.json   (fit_spiral)
  spiral_out/<scroll>/snapped[_<z0>_<z1>]/snap_report.tsv + w*/meta.json      (snap_meshes + tifxyz meta)
  screen/<scroll>/[b<z0>/]w*/{quick_done.json | thumbs/}                          (screen done markers)
Outputs: <out>/windings.tsv, <out>/bands.tsv
"""
import csv, glob, json, os, sys

WORK = os.path.expanduser(os.environ.get('WORK', '~/vesuvius/work'))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(WORK, 'pkg_qa')
os.makedirs(OUT, exist_ok=True)
VOL = {'PHerc0257': '20250821151750', 'PHerc0813': '20250821151723'}
BANDS = {'PHerc0257': [(9000, 10000), (10000, 11000), (11000, 12000), (12000, 13000)],
         'PHerc0813': [(7000, 8000), (8000, 9000), (9000, 10000), (10000, 11000)]}


def snapped_dir(s, z0, z1):
    d = f'{WORK}/spiral_out/{s}/snapped_{z0}_{z1}'
    if os.path.isdir(d):
        return d
    return f'{WORK}/spiral_out/{s}/snapped'  # PHerc0257 first band used the plain name


def screen_dir(s, z0):
    if s == 'PHerc0257' and z0 == 9000:
        return f'{WORK}/screen/{s}'
    return f'{WORK}/screen/{s}/b{z0}'


def fit_metrics(s, z0, z1):
    for d in sorted(glob.glob(f'{WORK}/spiral_out/{s}/*_{s}_slice-{z0}-{z1}_0-patch')):
        p = f'{d}/satisfaction_metrics_fitted.json'
        if os.path.exists(p):
            return json.load(open(p))['summary']
    return {}


UM = 9.362  # both volumes: 20250821151750 / 20250821151723-9.362um-1.2m-113keV-masked.zarr


def area3d_cm2(d):
    """true surface area of a tifxyz mesh: sum of the two triangles of every quad whose 4 corners are valid.
    (meta.json area_cm2 = valid quads x (1/scale)^2 voxels, i.e. it assumes 20-voxel grid steps; fitted meshes are
    stretched, so it under-reports by ~1.6-1.8x.)"""
    import numpy as np
    from PIL import Image
    X, Y, Z = (np.asarray(Image.open(f'{d}/{c}.tif'), dtype=np.float64) for c in 'xyz')
    P = np.stack([X, Y, Z], -1)
    ok = (X > 0) & (Y > 0) & (Z > 0)
    a, b, c, e = P[:-1, :-1], P[:-1, 1:], P[1:, :-1], P[1:, 1:]
    q = ok[:-1, :-1] & ok[:-1, 1:] & ok[1:, :-1] & ok[1:, 1:]
    A = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=-1) + 0.5 * np.linalg.norm(np.cross(b - e, c - e), axis=-1)
    return float(A[q].sum()) * (UM * 1e-4) ** 2


wrows, brows = [], []
for s, bands in BANDS.items():
    for z0, z1 in bands:
        sd, gd = snapped_dir(s, z0, z1), screen_dir(s, z0)
        rep = {}
        if os.path.exists(f'{sd}/snap_report.tsv'):
            for r in csv.DictReader(open(f'{sd}/snap_report.tsv'), delimiter='\t'):
                rep[r['winding']] = r
        fm = fit_metrics(s, z0, z1)
        n = nq = ns = 0
        a_all = a_q = a_s = 0.0
        for w in sorted(os.path.basename(p) for p in glob.glob(f'{sd}/w*')):
            meta = json.load(open(f'{sd}/{w}/meta.json'))
            ag = float(meta.get('area_cm2', 0.0))  # grid-count area from meta.json (under-reports)
            a = area3d_cm2(f'{sd}/{w}')
            r = rep.get(w, {})
            fws = float(r['frac_with_sheet']) if r.get('frac_with_sheet') else float('nan')
            wd = f'{gd}/{w}'
            screened = os.path.exists(f'{wd}/quick_done.json') or bool(glob.glob(f'{wd}/thumbs/*'))
            q = fws >= 0.85
            n += 1; a_all += a
            if q:
                nq += 1; a_q += a
            if screened:
                ns += 1; a_s += a
            wrows.append({'scroll': s, 'volume': VOL[s], 'z0': z0, 'z1': z1, 'winding': w,
                          'area_3d_cm2': round(a, 3), 'area_grid_cm2': round(ag, 3), 'n_valid': r.get('n_valid', ''),
                          'frac_with_sheet': r.get('frac_with_sheet', ''), 'frac_snapped': r.get('frac_snapped', ''),
                          'median_abs_off_vox': r.get('median_abs_off', ''), 'p90_abs_off_vox': r.get('p90_abs_off', ''),
                          'qa_ge_0p85': int(q), 'screened': int(screened)})
        brows.append({'scroll': s, 'volume': VOL[s], 'z0': z0, 'z1': z1,
                      'satisfied_tracks_fraction': round(fm.get('satisfied_tracks_fraction', float('nan')), 4),
                      'satisfied_track_points_fraction': round(fm.get('satisfied_track_points_fraction', float('nan')), 4),
                      'windings': n, 'area_3d_cm2': round(a_all, 1), 'windings_qa_ge_0p85': nq,
                      'area_3d_qa_ge_0p85_cm2': round(a_q, 1), 'windings_screened': ns, 'area_3d_screened_cm2': round(a_s, 1)})

for name, rows in (('windings.tsv', wrows), ('bands.tsv', brows)):
    with open(f'{OUT}/{name}', 'w', newline='') as f:
        wr = csv.DictWriter(f, fieldnames=list(rows[0].keys()), delimiter='\t', lineterminator='\n')
        wr.writeheader(); wr.writerows(rows)
print(open(f'{OUT}/bands.tsv').read())
