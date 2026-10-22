#!/usr/bin/env bash
# fit_snap_band.sh [S=<scroll>] <z_begin> <z_end> - band preparation only (default scroll PHerc0257): spiral fit (if
# missing), m7 slab chunk rows for the band, snapping of all windings (band_screen.sh with no winding list). Prints the
# snap QA per 20 windings and ALL DONE when the band's snap_report.tsv exists (so run_queue.sh can move on).
set -uo pipefail
S=PHerc0257; if [[ "${1:-}" == S=* ]]; then S=${1#S=}; shift; fi
ZB=$1; ZE=$2
bash "$(dirname "$0")/band_screen.sh" "S=$S" "$ZB" "$ZE" 1
if [ "$S" = PHerc0257 ] && [ "$ZB-$ZE" = "9000-10000" ]; then SNAP=snapped; else SNAP=snapped_${ZB}_${ZE}; fi
R=~/vesuvius/work/spiral_out/$S/$SNAP/snap_report.tsv
if [ -s "$R" ]; then
  python3 - "$R" <<'EOF'
import csv, statistics as st, sys
rows = list(csv.DictReader(open(sys.argv[1]), delimiter='\t'))
for lo in range(0, 120, 20):
    sub = [r for r in rows if lo <= int(r['winding'][1:]) < lo + 20]
    if sub:
        print(f"snapQA w{lo:03d}-w{lo + 19:03d}: frac_with_sheet {st.median(float(r['frac_with_sheet']) for r in sub):.2f} "
              f"med|off| {st.median(float(r['median_abs_off']) for r in sub):.2f} (n={len(sub)})")
EOF
  echo "[$(date -u +%FT%TZ)] ALL DONE fit_snap_band $S $ZB-$ZE"
else
  echo "[$(date -u +%FT%TZ)] fit_snap_band $ZB-$ZE: no snap report"
fi
