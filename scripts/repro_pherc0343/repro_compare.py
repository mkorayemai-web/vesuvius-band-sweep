#!/usr/bin/env python
"""Comparison of our reproduced PHerc0343 image with Nieuwlaar's published one (criteria fixed before the run).
Usage: python repro_compare.py <his.png> <ours.png> <his.json> <our_out_dir>
(a) CT stretch lo/hi from the image sidecars within +-4; (b) Pearson r of the ink overlay 'yellowness'
((R+G)/2 - B) between the two images: PASS >= 0.70, PARTIAL 0.40-0.70, FAIL < 0.40. Writes repro_compare.json.
"""
import sys, json, glob, os
import numpy as np
from PIL import Image

his_png, our_png, his_json, our_dir = sys.argv[1:5]
A = np.asarray(Image.open(his_png).convert('RGB'), dtype=np.float32)
Bimg = Image.open(our_png).convert('RGB')
resized = False
if Bimg.size != (A.shape[1], A.shape[0]):
    Bimg = Bimg.resize((A.shape[1], A.shape[0]), Image.BILINEAR); resized = True
B = np.asarray(Bimg, dtype=np.float32)

def yel(x):
    return (x[..., 0] + x[..., 1]) / 2 - x[..., 2]

def r(a, b):
    a = a.ravel() - a.mean(); b = b.ravel() - b.mean()
    return float(a @ b / (np.sqrt((a @ a) * (b @ b)) + 1e-9))

ya, yb = yel(A), yel(B)
res = {'his_png': his_png, 'our_png': our_png, 'shape_his': list(A.shape), 'resized_ours': resized,
       'r_yellowness': round(r(ya, yb), 4), 'r_gray': round(r(A.mean(-1), B.mean(-1)), 4),
       'yellow_px_frac_his': float((ya > 40).mean()), 'yellow_px_frac_ours': float((yb > 40).mean())}
his = json.load(open(his_json))
ours_json = [p for p in glob.glob(os.path.join(our_dir, '*.json'))]
st_h = (his.get('ct') or {}).get('stretch') or {}
st_o = {}
if ours_json:
    o = json.load(open(ours_json[0]))
    st_o = (o.get('ct') or {}).get('stretch') or {}
    res['our_json'] = ours_json[0]
res['ct_stretch_his'] = st_h; res['ct_stretch_ours'] = st_o
ok_a = bool(st_o) and abs(st_o.get('lo', 1e9) - st_h.get('lo', 0)) <= 4 and abs(st_o.get('hi', 1e9) - st_h.get('hi', 0)) <= 4
ry = res['r_yellowness']
res['crit_a_ct_stretch'] = 'PASS' if ok_a else 'FAIL'
res['crit_b_yellowness'] = 'PASS' if ry >= 0.70 else ('PARTIAL' if ry >= 0.40 else 'FAIL')
res['verdict_ab'] = 'PASS' if (ok_a and ry >= 0.70) else ('PARTIAL' if ry >= 0.40 else 'FAIL')
json.dump(res, open('repro_compare.json', 'w'), indent=1)
side = np.concatenate([A, np.full((A.shape[0], 16, 3), 255, np.float32), B], axis=1).astype(np.uint8)
Image.fromarray(side).resize((side.shape[1] // 2, side.shape[0] // 2)).save('repro_his_vs_ours.png')
print(json.dumps(res, indent=1))
