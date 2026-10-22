#!/usr/bin/env python
"""score_winding.py <winding_dir> <keep> <flag> - per-winding finish step of screen_band.sh after triage v1 + v2.
The triage ratio FAILED calibration on band maps (docs/FAILURE_CASES.md): it is logged, not used for decisions.

Ratios are taken against the PHerc0343 positive control of the same model: v1 vs control_reference_triage.json,
v2 vs control_reference_triage_v2.json (both in /work/screen). Writes 1/8 thumbnails of every map, deletes the 66-layer render
and the full maps unless v2 >= keep, writes quick_done.json, and prints one line:
  FLAG|SCORE <winding> <v2 ratio> v1=<v1 ratio> <best v2 tile as JSON>
FLAG means v2 >= flag (an audit candidate, not a finding).
"""
import glob, json, os, shutil, sys
from PIL import Image
import tifffile

D, KEEP, FLAG = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])


def best_ratio(tri_path, ref_path):
    if not (os.path.exists(ref_path) and os.path.exists(tri_path)):
        return (0.0, None)  # no control reference: ratio not computed
    ref = {os.path.basename(k).split('__')[1]: v['top'][0]['score']
           for k, v in json.load(open(ref_path)).items() if v['top']}
    best = (0.0, None)
    for k, v in json.load(open(tri_path)).items():
        model = os.path.basename(k).split('__')[1]
        if model in ref and v['top']:
            t = v['top'][0]
            r = t['score'] / ref[model]
            if r > best[0]:
                best = (r, {'map': os.path.basename(k), 'ratio': round(r, 4), 'period_mm': round(t['period_mm'], 2),
                            'k': t.get('k'), 'y0': t['y0'], 'x0': t['x0']})
    return best


b1 = best_ratio(D + '/triage_quick.json', '/work/screen/control_reference_triage.json')
b2 = best_ratio(D + '/triage_v2.json', '/work/screen/control_reference_triage_v2.json')
os.makedirs(D + '/thumbs', exist_ok=True)
for t in glob.glob(D + '/maps/*.tif'):
    a = tifffile.imread(t).squeeze()
    Image.fromarray(a[::8, ::8]).save(D + '/thumbs/' + os.path.basename(t).replace('.tif', '_ds8.png'))
    Image.fromarray(a[::4, ::4]).save(D + '/thumbs/' + os.path.basename(t).replace('.tif', '_ds4.png'))
keep = b2[0] >= KEEP
if not keep:
    shutil.rmtree(D + '/' + os.path.basename(D) + '_66.zarr', ignore_errors=True)
    for t in glob.glob(D + '/maps/*.tif'):
        os.remove(t)
json.dump({'stat': 'v2', 'max_ratio': round(b2[0], 4), 'best': b2[1], 'max_ratio_v1': round(b1[0], 4),
           'best_v1': b1[1], 'kept_full': keep}, open(D + '/quick_done.json', 'w'), indent=1)
print('FLAG' if b2[0] >= FLAG else 'SCORE', os.path.basename(D), round(b2[0], 4), 'v1=%.4f' % b1[0], json.dumps(b2[1]))
