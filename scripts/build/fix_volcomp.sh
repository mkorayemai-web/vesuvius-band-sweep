#!/usr/bin/env bash
# fix_volcomp.sh <container> <villa_src_dir_in_container>
# villa main's install rule walks core/utils/libs/c3d but not libs/volcomp, so the installed CLI tools fail with
# "libvolcomp.so: cannot open shared object file". Compile the vendored single-file codec as the same shared library
# (Release flags, C23, -w, -lm as in libs/volcomp/CMakeLists.txt) into /usr/local/lib, then verify every installed
# ELF binary resolves all its shared libraries and that vc_render_tifxyz starts.
set -euo pipefail
C="$1"; S="${2:-/opt/villa/volume-cartographer}"
docker exec "$C" bash -c "cc -shared -fPIC -O3 -DNDEBUG -std=c2x -w -I$S/libs/volcomp -o /usr/local/lib/libvolcomp.so $S/libs/volcomp/volcomp_lib.c -lm && ldconfig && ls -la /usr/local/lib/libvolcomp.so"
docker exec "$C" bash -c 'bad=0; n=0; for f in /usr/local/bin/*; do if file "$f" | grep -q ELF; then n=$((n+1)); if ldd "$f" | grep -q "not found"; then echo "UNRESOLVED $f: $(ldd "$f" | grep "not found" | tr -s " " | tr "\n" ";")"; bad=1; fi; fi; done; echo "checked $n ELF binaries, unresolved=$bad"; exit $bad'
docker exec "$C" bash -c 'vc_render_tifxyz --help 2>&1 | head -12; vc_grow_seg_from_seed --help 2>&1 | head -3'
