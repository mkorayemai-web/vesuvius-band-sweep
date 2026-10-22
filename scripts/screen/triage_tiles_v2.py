#!/usr/bin/env python
"""Tile triage v2 (screening aid only): row-periodicity score per 2 cm x 2 cm tile, fixed for maps shorter than a tile.

v1 (triage_tiles.py) set rows with no valid pixels to 0. On band maps only ~14-16 mm tall (shorter than the 20 mm
tile) the dark top/bottom borders then form a box-shaped step in the row profile, whose leakage peaks at the lowest
admissible bin (k = 2 cycles per tile, ~7-8 mm). All four flags of our first screen sat exactly there (74-89 % of the
non-DC power at k <= 2 vs 11-37 % for the PHerc0343 positive control), see docs/FAILURE_CASES.md.

v2 changes (nothing else):
  1. the row profile uses only the span between the first and last row with >= 50 % valid pixels; rows inside that
     span with < 50 % valid are linearly interpolated; the span must be >= 1 cm;
  2. a straight line is fitted and removed before the Hann window;
  3. the peak must lie in 2.5-8 mm AND have >= 3 cycles within the span.
Score = peak power / median spectral power (as v1). Also reports 'peak_frac' = peak power / total non-DC power.

Usage: python triage_tiles_v2.py <out.json> <px_um> <ds> <map1.tif|png> [map2 ...]
  ds = integer decimation applied to each map first (a[::ds, ::ds]); pixel size becomes px_um * ds.
  Thumbnails written by quick_screen.sh are already a[::8, ::8]: pass px_um = 8 * native and ds = 1.
"""
import sys, json
import numpy as np
import tifffile
from PIL import Image

out, px_um, ds = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
maps = sys.argv[4:]
px = px_um * ds
T = int(round(20000 / px))
res = {}
for m in maps:
    a = (tifffile.imread(m) if m.endswith(('.tif', '.tiff')) else np.asarray(Image.open(m).convert('L'))).astype(np.float32)
    a = a.squeeze()[::ds, ::ds]
    H, W = a.shape
    tiles = []
    for y0 in range(0, max(H - T // 2, 1), T // 2):
        for x0 in range(0, max(W - T // 2, 1), T // 2):
            t = a[y0:y0 + T, x0:x0 + T]
            valid = t > 0
            if valid.mean() < 0.5 or t.shape[0] < T // 2:
                continue
            vf = valid.mean(1)
            good = np.where(vf >= 0.5)[0]
            if good.size < 2:
                continue
            lo, hi = good[0], good[-1] + 1
            if (hi - lo) * px < 10000:
                continue
            rows = np.full(hi - lo, np.nan)
            g = vf[lo:hi] >= 0.5
            tv, vv = t[lo:hi], valid[lo:hi]
            rows[g] = (tv[g] * vv[g]).sum(1) / vv[g].sum(1)
            idx = np.arange(hi - lo)
            rows = np.interp(idx, idx[g], rows[g])
            p = rows - np.polyval(np.polyfit(idx, rows, 1), idx)
            n = len(p)
            spec = np.abs(np.fft.rfft(p * np.hanning(n))) ** 2
            f = np.fft.rfftfreq(n, d=px / 1000.0)
            kk = np.arange(len(f))
            band = (f >= 1 / 8.0) & (f <= 1 / 2.5) & (kk >= 3)
            if not band.any():
                continue
            med = float(np.median(spec[1:])) or 1e-9
            k = int(np.argmax(np.where(band, spec, 0)))
            tiles.append({'y0': y0 * ds, 'x0': x0 * ds, 'score': float(spec[k] / med), 'period_mm': float(1 / f[k]),
                          'k': k, 'span_mm': round(n * px / 1000, 2),
                          'peak_frac': float(spec[k] / max(spec[1:].sum(), 1e-9)), 'valid': float(valid.mean())})
    tiles.sort(key=lambda d: -d['score'])
    res[m] = {'shape': [H * ds, W * ds], 'px_um_eff': px, 'tile_px': T, 'n_tiles': len(tiles), 'top': tiles[:10],
              'p50': float(np.median([t['score'] for t in tiles])) if tiles else None}
json.dump(res, open(out, 'w'), indent=1)
for m, v in res.items():
    t = v['top'][0] if v['top'] else None
    print(m.split('/')[-1], v['n_tiles'], t and (round(t['score']), round(t['period_mm'], 2), t['k'], t['span_mm'], round(t['peak_frac'], 3)))
