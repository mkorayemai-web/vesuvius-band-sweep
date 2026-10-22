#!/usr/bin/env python3
"""Visual review sheets, shelf-packed: per winding and direction the mean of the available screen maps at 1/8 scale,
with the PHerc0343 known-text control processed the same way as the first tile of every sheet.

Layout: each winding is one tile = reverse mean (top) over forward mean (bottom), each stretched 1-99 % over valid
pixels; tiles are packed left to right into shelves of a sheet <= MAX px on each side. Check that your image viewer
shows the sheet at native size (some downscale large images silently). First tile = known-text control.

Usage: review_sheets.py <out_prefix> <control_dir> <label>=<band_dir> [<label>=<band_dir> ...]
  band_dir/<w>/thumbs/<w>_66__<model>__L66s2[68][_reverse]_ds8.png   (dnative + hybrid_3d2d-seed42, d=+1/+3)
Prints one line per sheet with the tiles it holds; writes <out_prefix>_NN.png and <out_prefix>_index.json.
"""
import glob, json, os, sys
import numpy as np
from PIL import Image, ImageDraw

MAX = 3100; PAD = 10; LAB = 24; GAP = 6
MAXW = int(os.environ.get('SHEET_MAXW', MAX)); MAXH = int(os.environ.get('SHEET_MAXH', MAX))
KB = int(os.environ.get('SHEET_KB', '380'))   # viewer downscales large files: keep jpg under this size
ONLY = [x for x in os.environ.get('SHEET_ONLY', '').split(',') if x]   # optional 'label wNNN' allow-list
SCALE = float(os.environ.get('SHEET_SCALE', '1'))   # 0.5 = area-resample the whole sheet to ~150 um/px (viewer-safe)
MODELS = ('dnative', 'hybrid_3d2d-seed42')
out, ctrl_dir = sys.argv[1], sys.argv[2]
bands = [a.split('=', 1) for a in sys.argv[3:]]
PX_T = 9.362 * 8


def stretch(a):
    out = np.zeros(a.shape, np.uint8)
    v = a[np.isfinite(a)]
    if v.size:
        lo, hi = np.percentile(v, [1, 99])
        out = (np.clip((np.nan_to_num(a, nan=lo) - lo) / max(hi - lo, 1e-6), 0, 1) * 255).astype(np.uint8)
        out[~np.isfinite(a)] = 0
    return out


def mean_of(paths, f=None):
    arrs = []
    for p in paths:
        a = np.asarray(Image.open(p).convert('L')).astype(np.float32)
        if f:
            ri = (np.arange(int(a.shape[0] / f)) * f).astype(int); ci = (np.arange(int(a.shape[1] / f)) * f).astype(int)
            a = a[ri][:, ci]
        a[a == 0] = np.nan
        arrs.append(a)
    if not arrs:
        return None
    h = min(a.shape[0] for a in arrs); w = min(a.shape[1] for a in arrs)
    with np.errstate(all='ignore'):
        return np.nanmean(np.stack([a[:h, :w] for a in arrs]), 0)


def tile(label, rev, fwd):
    ims = [Image.fromarray(stretch(x)) for x in (rev, fwd) if x is not None]
    W = max(i.width for i in ims); H = LAB + sum(i.height for i in ims) + GAP * (len(ims) - 1)
    t = Image.new('RGB', (W, H), (70, 70, 70))
    y = LAB
    for i in ims:
        t.paste(i.convert('RGB'), (0, y)); y += i.height + GAP
    return t


ctrl = {}
for key, suf in (('rev', '_reverse.tif'), ('fwd', '.tif')):
    ps = [p for m in MODELS for p in glob.glob(os.path.join(ctrl_dir, f'*__{m}__L66s26{suf}'))]
    ctrl[key] = mean_of(ps, f=PX_T / 8.64)
CTRL_TILE = tile('KNOWN TEXT PHerc0343 control (top=reverse/reading side)', ctrl['fwd'] if False else ctrl['rev'], ctrl['fwd'])

tiles = []
for label, root in bands:
    for d in sorted(glob.glob(os.path.join(root, 'w*'))):
        w = os.path.basename(d); th = os.path.join(d, 'thumbs')
        rev = mean_of(sorted(p for m in MODELS for p in glob.glob(f'{th}/{w}_66__{m}__L66s2[68]_reverse_ds8.png')))
        fwd = mean_of(sorted(p for m in MODELS for p in glob.glob(f'{th}/{w}_66__{m}__L66s2[68]_ds8.png')))
        if rev is None and fwd is None:
            continue
        if ONLY and f'{label} {w}' not in ONLY:
            continue
        tiles.append((f'{label} {w}', tile(f'{label} {w}', rev, fwd)))

sheets, index = [], []
cur = None


def new_sheet():
    return {'items': [(CTRL_TILE, 'CONTROL')], 'tiles': []}


def layout(items):
    # shelf packing; returns positions and sheet size, or None if it overflows MAX x MAX
    x = PAD; y = PAD; shelf_h = 0; pos = []
    for im, _ in items:
        if x + im.width + PAD > MAXW:
            x = PAD; y += shelf_h + PAD; shelf_h = 0
        if im.width + 2 * PAD > MAXW:
            return None
        pos.append((x, y)); x += im.width + PAD; shelf_h = max(shelf_h, im.height)
    H = y + shelf_h + PAD
    return (pos, H) if H <= MAXH else None


cur = new_sheet()
for name, t in tiles:
    trial = cur['items'] + [(t, name)]
    if layout(trial) is None:
        sheets.append(cur); cur = new_sheet(); trial = cur['items'] + [(t, name)]
    cur['items'] = trial; cur['tiles'].append(name)
sheets.append(cur)
for i, s in enumerate(sheets, 1):
    pos, H = layout(s['items'])
    W = max(px + im.width for (px, _), (im, _) in zip(pos, s['items'])) + PAD
    sheet = Image.new('RGB', (W, H), (25, 25, 25))
    for (px, py), (im, _) in zip(pos, s['items']):
        sheet.paste(im, (px, py))
    if SCALE != 1:
        sheet = sheet.resize((int(W * SCALE), int(H * SCALE)), Image.LANCZOS)
    dr = ImageDraw.Draw(sheet)
    for (px, py), (im, name) in zip(pos, s['items']):
        lab = 'KNOWN TEXT control (top = reading side)' if name == 'CONTROL' else name
        dr.text((int(px * SCALE) + 2, int(py * SCALE) + 1), lab, fill=(255, 220, 0))
    ext = os.environ.get('SHEET_FMT', 'png')
    fn = f'{out}_{i:02d}.{ext}'
    q = int(os.environ.get('SHEET_Q', '92'))
    while True:   # the image viewer halves files above ~400 KB: step quality down to stay under 380 KB
        sheet.save(fn, quality=q) if ext == 'jpg' else sheet.save(fn)
        if ext != 'jpg' or os.path.getsize(fn) <= KB * 1000 or q <= 50:
            break
        q -= 5
    index.append({'sheet': fn, 'size': sheet.size, 'tiles': s['tiles']})
    print(fn, sheet.size, len(s['tiles']), s['tiles'][0], '...', s['tiles'][-1])
json.dump(index, open(f'{out}_index.json', 'w'), indent=1)
