#!/bin/sh
# build_sim.sh — host proof for the Cascade Console sim module.
# Builds the SAME test suite three ways:
#   1. mock backend  (engine's analytic ccgeom_mock + ccsim_backend_mock)
#   2. OCCT backend  (engine's ccgeom_occt + ccsim_backend_occt, real
#      OCCT geometry — 8.0.1 conda tree if present, else system OCCT)
#   3. mc adapter compile check (ccsim_backend_mc.cpp, object only —
#      CascadeKit linking is a device/CI step, as with the engine)
# Then runs suites 1 and 2 from results/ so field files land there.
# CC_OCCT_PREFIX overrides the OCCT tree. Nothing here touches the
# network. Repo layout: ENG is this directory (Core/native).
set -e
cd "$(dirname "$0")"
SIM=$PWD
ENG=$SIM
PORT=${CC_PORT_DIR:-$HOME/workspace/cascade-port}
CXX=${CXX:-c++}
CXXFLAGS="-std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter"
mkdir -p build results

# ---- OCCT prefix selection (same policy as the engine build) ----
OCCT_PREFIX=${CC_OCCT_PREFIX:-}
if [ -z "$OCCT_PREFIX" ]; then
  for cand in \
    "$HOME/workspace/tools/mamba-root/pkgs/https/conda.anaconda.org/conda-forge/linux-64/occt-8.0.1-all_hbfeb9d6_201" \
    /usr; do
    if [ -f "$cand/include/opencascade/BRepPrimAPI_MakeBox.hxx" ] || \
       [ -f "$cand/include/BRepPrimAPI_MakeBox.hxx" ]; then
      OCCT_PREFIX=$cand; break
    fi
  done
fi
if [ -n "$OCCT_PREFIX" ] && [ -d "$OCCT_PREFIX/include/opencascade" ]; then
  OCCT_INC=$OCCT_PREFIX/include/opencascade
else
  OCCT_INC=$OCCT_PREFIX/include
fi
OCCT_LIB=$OCCT_PREFIX/lib
[ -d "$OCCT_LIB" ] || OCCT_LIB=/usr/lib64
echo "OCCT prefix: $OCCT_PREFIX (include: $OCCT_INC)"

OCCT_LIBS="-lTKPrim -lTKBO -lTKBool -lTKFillet -lTKMesh -lTKTopAlgo \
-lTKGeomAlgo -lTKShHealing -lTKBRep -lTKGeomBase -lTKG3d -lTKG2d \
-lTKMath -lTKernel"
HAS_DESTEP=0
for d in "$OCCT_LIB" "$OCCT_PREFIX/lib/x86_64-linux-gnu" /usr/lib/x86_64-linux-gnu /usr/lib; do
  { [ -e "$d/libTKDESTEP.so" ] || [ -e "$d/libTKDESTEP.dylib" ]; } && HAS_DESTEP=1
done
if [ "$HAS_DESTEP" = 1 ]; then
  OCCT_LIBS="$OCCT_LIBS -lTKDESTEP -lTKDEGLTF -lTKDEIGES -lTKDESTL"
else
  OCCT_LIBS="$OCCT_LIBS -lTKSTEP -lTKSTEPAttr -lTKSTEP209 -lTKSTEPBase \
-lTKIGES -lTKSTL -lTKXSBase"
fi

echo "== [1/3] mock backend build =="
$CXX $CXXFLAGS \
  -I"$SIM/include" -I"$ENG/include" \
  "$SIM/src/ccsim.cpp" "$SIM/src/ccsim_commands.cpp" \
  "$SIM/src/ccsim_backend_mock.cpp" \
  "$ENG/src/ccgeom_mock.cpp" \
  "$SIM/tests/test_sim.cpp" \
  -o build/test_sim_mock

echo "== [2/3] OCCT backend build =="
$CXX $CXXFLAGS \
  -I"$SIM/include" -I"$ENG/include" -I"$OCCT_INC" \
  "$SIM/src/ccsim.cpp" "$SIM/src/ccsim_commands.cpp" \
  "$ENG/src/ccgeom_occt.cpp" \
  "$SIM/tests/test_sim.cpp" \
  -L"$OCCT_LIB" -Wl,-rpath,"$OCCT_LIB" $OCCT_LIBS \
  -o build/test_sim_occt

echo "== [3/3] mc adapter compile check (object only) =="
$CXX $CXXFLAGS -c \
  -I"$SIM/include" -I"$ENG/include" -I"$ENG/src" -I"$PORT/Facade" \
  "$SIM/src/ccsim_backend_mc.cpp" \
  -o build/ccsim_backend_mc.o
echo "mc adapter: compiled OK"

echo "== run: mock =="
(cd results && ../build/test_sim_mock mock sim_results_mock.json)
echo "== run: OCCT =="
(cd results && ../build/test_sim_occt occt sim_results_occt.json)
echo "ALL SIM BUILDS + RUNS DONE"
