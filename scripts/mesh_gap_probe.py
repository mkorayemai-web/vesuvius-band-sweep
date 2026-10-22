#!/usr/bin/env python3
"""mesh_gap_probe.py - worked example (PHerc0257 z10000-11000, windings w063/w064): a feature seen on two adjacent
fitted windings may be ONE physical sheet sampled twice. Read-only, host python (numpy + PIL); edit B/Y0/X0/X1.
1. Full-resolution crops of every reverse/forward map of w064 (and w063 at its matching place) around the row.
2. Mesh geometry: 3D distance from the w064 row points to the w063 and w065 surfaces (tifxyz, scale 0.05),
   to tell 'two windings show the same feature' (same physical sheet sampled twice) from independent windings.
Writes ~/vesuvius/work/screen/cand_probe/ (PNGs + probe.json). Screening aid only.
"""
import glob, json, os
import numpy as np
from PIL import Image

B = os.path.expanduser('~/vesuvius/work/screen/PHerc0257/b10000')
OUT = os.path.expanduser('~/vesuvius/work/screen/cand_probe'); os.makedirs(OUT, exist_ok=True)
Y0, X0, X1 = 952, 548, 2732          # row centre (full-res render px) and extent, from the 1/4-scale 3-model mean
HALF = 320; PADX = 300


def tifxyz(w):
    d = f'{B}/{w}/flatten/tifxyz/flatten.tifxyz'
    a = [np.asarray(Image.open(f'{d}/{c}.tif'), dtype=np.float64) for c in 'xyz']
    P = np.stack(a, -1)
    valid = (P[..., 2] > 0) & np.isfinite(P).all(-1)
    return P, valid


def crop_maps(w, yc, x0, x1, tag):
    rows = []
    for p in sorted(glob.glob(f'{B}/{w}/maps/*')):
        if not p.endswith(('.tif', '.png')):
            continue
        a = np.asarray(Image.open(p).convert('L')).astype(np.float32)
        f = 9.362 / 9.6 if '__hecate__' in p else 1.0      # hecate grid is 9.6 um
        y0, y1 = int((yc - HALF) * f), int((yc + HALF) * f)
        xa, xb = int(max(x0 - PADX, 0) * f), int((x1 + PADX) * f)
        c = a[max(y0, 0):y1, xa:xb]
        v = c[c > 0]
        lo, hi = (np.percentile(v, [1, 99.7]) if v.size else (0, 1))
        img = (np.clip((c - lo) / max(hi - lo, 1e-6), 0, 1) * 255).astype(np.uint8)
        name = os.path.basename(p).rsplit('.', 1)[0].replace(f'{w}_66__', '')
        Image.fromarray(img[::2, ::2]).save(f'{OUT}/{tag}_{name}.png')
        rows.append(name)
    return rows


P4, V4 = tifxyz('w064')
gy = int(round(Y0 * 0.05)); gx0, gx1 = int(X0 * 0.05), int(X1 * 0.05) + 1
q = P4[gy, gx0:gx1][V4[gy, gx0:gx1]]
res = {'w064_row_grid': [gy, gx0, gx1], 'n_query': int(len(q)),
       'w064_row_xyz_first_last': [q[0].round(1).tolist(), q[-1].round(1).tolist()] if len(q) else None}
match = {}
for w in ('w062', 'w063', 'w065', 'w066'):
    if not os.path.exists(f'{B}/{w}/flatten/tifxyz/flatten.tifxyz/x.tif'):
        continue
    P, V = tifxyz(w)
    pts = P[V]; idx = np.argwhere(V)
    dmin, where = [], []
    for s in range(0, len(q), 16):
        d = np.linalg.norm(pts[None, :, :] - q[s:s + 16, None, :], axis=-1)
        j = d.argmin(1); dmin += d[np.arange(len(j)), j].tolist(); where += idx[j].tolist()
    dmin = np.array(dmin); where = np.array(where)
    res[w] = {'dist_vox_median': round(float(np.median(dmin)), 1), 'dist_vox_min': round(float(dmin.min()), 1),
              'dist_vox_max': round(float(dmin.max()), 1),
              'nearest_render_px_y_median': int(np.median(where[:, 0]) * 20), 'nearest_render_px_x_range': [int(where[:, 1].min() * 20), int(where[:, 1].max() * 20)]}
    match[w] = res[w]
print(json.dumps(res, indent=1))
rows64 = crop_maps('w064', Y0, X0, X1, 'w064')
m63 = res.get('w063')
if m63:
    rows63 = crop_maps('w063', m63['nearest_render_px_y_median'], m63['nearest_render_px_x_range'][0], m63['nearest_render_px_x_range'][1], 'w063')
res['crops'] = {'w064': rows64, 'w063': rows63 if m63 else []}
json.dump(res, open(f'{OUT}/probe.json', 'w'), indent=1)
print('crops written:', len(rows64), len(res['crops']['w063']))
