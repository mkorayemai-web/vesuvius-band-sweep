#!/usr/bin/env python
"""Tile triage for ink maps: row-periodicity score per ~4 cm2 tile (2 cm x 2 cm), as a screening aid only.
Text rows are horizontal (along the flattened winding) and ~2.5-8 mm apart, so a tile with text shows a peak in the
row-mean spectrum at that period. Score = peak power in the 2.5-8 mm band / median spectral power (Hann-windowed,
mean-removed row profile of the tile; invalid pixels = 0 are excluded from the row means).
Usage: python triage_tiles.py <out.json> <px_um> <map1.tif|png> [map2 ...]
Prints the top tiles per map; writes all tile scores to <out.json>.
"""
import sys, json
import numpy as np
import tifffile
from PIL import Image

out, px_um = sys.argv[1], float(sys.argv[2])
maps = sys.argv[3:]
T = int(round(20000 / px_um))           # 2 cm tile edge in px
res = {}
for m in maps:
    a = (tifffile.imread(m) if m.endswith(('.tif', '.tiff')) else np.asarray(Image.open(m).convert('L'))).astype(np.float32)
    a = a.squeeze()
    H, W = a.shape
    tiles = []
    for y0 in range(0, max(H - T // 2, 1), T // 2):           # 50 % overlap
        for x0 in range(0, max(W - T // 2, 1), T // 2):
            t = a[y0:y0 + T, x0:x0 + T]
            valid = t > 0
            if valid.mean() < 0.5 or t.shape[0] < T // 2:
                continue
            rows = np.where(valid.sum(1) > 0, (t * valid).sum(1) / np.maximum(valid.sum(1), 1), 0.0)
            p = rows - rows.mean()
            n = len(p)
            spec = np.abs(np.fft.rfft(p * np.hanning(n))) ** 2
            f = np.fft.rfftfreq(n, d=px_um / 1000.0)
            band = (f >= 1 / 8.0) & (f <= 1 / 2.5)
            if not band.any():
                continue
            med = float(np.median(spec[1:])) or 1e-9
            k = int(np.argmax(np.where(band, spec, 0)))
            tiles.append({'y0': y0, 'x0': x0, 'score': float(spec[k] / med), 'period_mm': float(1 / f[k]),
                          'valid': float(valid.mean()), 'mean': float(t[valid].mean())})
    tiles.sort(key=lambda d: -d['score'])
    res[m] = {'shape': [H, W], 'tile_px': T, 'n_tiles': len(tiles), 'top': tiles[:10],
              'p50': float(np.median([t['score'] for t in tiles])) if tiles else None}
    top = tiles[0] if tiles else None
    print(f"{m}: tiles={len(tiles)} p50={res[m]['p50']} top={top}")
json.dump(res, open(out, 'w'), indent=1)
