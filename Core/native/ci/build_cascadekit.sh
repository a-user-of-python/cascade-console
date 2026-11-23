#!/bin/bash
# build_cascadekit.sh — build libCascadeKit.a from a cascade-ios
# checkout (OCCT 8.0.1 subset + mc_* facade) for arm64 iOS.
#
# Why not xcodebuild over gen_project.py's project: three CI runs
# never finished that step (>75 min each). Why not one clang call per
# file: also >95 min — every one of the 5,234 translation units
# re-parses the same multi-megabyte OCCT header graph.
#
# This script uses CHUNKED UNITY compilation: sources are grouped by
# toolkit and concatenated 40-per-translation-unit, so the header
# graph is parsed ~130 times instead of 5,234. Same sources, same
# defines and language standard as gen_project.py encodes
# (OCC_CONVERT_SIGNALS / No_Exception / OCCT_NO_PLUGINS / NDEBUG,
# gnu++17); OCCT sources are NOT modified (LGPL) — unity files only
# #include them.
#
# Usage: build_cascadekit.sh <cascade-ios checkout> <output dir>
set -euo pipefail
SRC_DIR="$(cd "$1" && pwd)"
OUT_DIR="$(mkdir -p "$2" && cd "$2" && pwd)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
WORK="$OUT_DIR/kitobj"
mkdir -p "$WORK/unity" "$OUT_DIR/kitlib"

cd "$SRC_DIR"
INC="-IFacade -IOCCT/generated"
while IFS= read -r d; do INC="$INC -I$d"; done < <(find OCCT/src -type d | sort)
export SDK INC SRC_DIR WORK

# --- C sources: few, compile individually -------------------------------
find OCCT/src -name '*.c' > "$WORK/c_sources.txt"
compile_c() {
  src="$1"
  obj="$WORK/$(printf '%s' "$src" | md5 -q).o"
  clang -target arm64-apple-ios17.0 -isysroot "$SDK" -O1 -w \
    -DOCC_CONVERT_SIGNALS -DNo_Exception -DOCCT_NO_PLUGINS -DNDEBUG \
    $INC -c "$SRC_DIR/$src" -o "$obj"
}
export -f compile_c
xargs -P "$(sysctl -n hw.ncpu)" -I S bash -c 'compile_c "$@"' _ S < "$WORK/c_sources.txt"

# --- C++ sources: chunked unity per toolkit ------------------------------
find OCCT/src -name '*.cxx' -o -name '*.cpp' | sort > "$WORK/cxx_sources.txt"
python3 - "$WORK/cxx_sources.txt" "$WORK/unity" <<'PYEOF'
import os, sys
lines = [l.strip() for l in open(sys.argv[1]) if l.strip()]
outdir = sys.argv[2]
groups = {}
for path in lines:
    parts = path.split("/")
    # OCCT/src/<area>/<toolkit>/... — group per toolkit
    key = "/".join(parts[:4]) if len(parts) >= 4 else "misc"
    groups.setdefault(key, []).append(path)
n = 0
for key, files in sorted(groups.items()):
    for i in range(0, len(files), 40):
        chunk = files[i:i + 40]
        with open(os.path.join(outdir, f"unity_{n}.cpp"), "w") as f:
            for p in chunk:
                f.write(f'#include "{p}"\n')
        n += 1
print(f"unity translation units: {n}")
PYEOF
compile_unity() {
  tu="$1"
  obj="$WORK/$(basename "$tu" .cpp).o"
  clang++ -std=gnu++17 -target arm64-apple-ios17.0 -isysroot "$SDK" -O1 -w \
    -DOCC_CONVERT_SIGNALS -DNo_Exception -DOCCT_NO_PLUGINS -DNDEBUG \
    $INC -I"$SRC_DIR" -c "$tu" -o "$obj"
}
export -f compile_unity
ls "$WORK/unity"/*.cpp | xargs -P "$(sysctl -n hw.ncpu)" -I S bash -c 'compile_unity "$@"' _ S

# --- Facade ---------------------------------------------------------------
clang++ -std=gnu++17 -target arm64-apple-ios17.0 -isysroot "$SDK" -O1 -w \
  -DOCC_CONVERT_SIGNALS -DNo_Exception -DOCCT_NO_PLUGINS -DNDEBUG \
  $INC -c "$SRC_DIR/Facade/occt_facade.cpp" -o "$WORK/occt_facade.o"

ar rcs "$OUT_DIR/kitlib/libCascadeKit.a" "$WORK"/*.o
ls -la "$OUT_DIR/kitlib/"
