#!/usr/bin/env python
"""thumbs.py <winding_dir> [...] - write 1/4 and 1/8 PNGs (nearest decimation) of every map in <dir>/maps
(villa .tif and Hecate .png) into <dir>/thumbs; never deletes anything."""
import glob, os, sys
import numpy as np
import tifffile
from PIL import Image

for D in sys.argv[1:]:
    os.makedirs(D + '/thumbs', exist_ok=True)
    for t in sorted(glob.glob(D + '/maps/*.tif') + glob.glob(D + '/maps/*.png')):
        a = tifffile.imread(t).squeeze() if t.endswith('.tif') else np.asarray(Image.open(t).convert('L'))
        stem = os.path.basename(t).rsplit('.', 1)[0]
        for ds in (4, 8):
            Image.fromarray(np.ascontiguousarray(a[::ds, ::ds])).save(f'{D}/thumbs/{stem}_ds{ds}.png')
    print(D, len(glob.glob(D + '/thumbs/*.png')), 'thumbs')
