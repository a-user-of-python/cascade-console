#!/bin/bash
# Host build + test for the Cascade Console native engine.
# Builds the interpreter against (a) the analytic mock backend and
# (b) a real OCCT, then runs the test harness on both.
#
# OCCT selection: if the conda OCCT 8.0.1 tree is present it is used
# (same version as the device target); otherwise the system OCCT
# (Debian libocct-*-dev, 7.6.3) is used. Set CC_OCCT_PREFIX to force one.
set -e
cd "$(dirname "$0")"
mkdir -p build

CXX=${CXX:-g++}
CXXFLAGS="-std=c++17 -O1 -Wall -Wextra -Iinclude"

CONDA_OCCT="$HOME/workspace/tools/mamba-root/pkgs/https/conda.anaconda.org/conda-forge/linux-64/occt-8.0.1-all_hbfeb9d6_201"
if [ -n "$CC_OCCT_PREFIX" ]; then
  OCCT_PREFIX="$CC_OCCT_PREFIX"
elif [ -d "$CONDA_OCCT/include/opencascade" ]; then
  OCCT_PREFIX="$CONDA_OCCT"
else
  OCCT_PREFIX="/usr"
fi
OCCT_INC="$OCCT_PREFIX/include/opencascade"
OCCT_LIB="$OCCT_PREFIX/lib"
echo "OCCT prefix: $OCCT_PREFIX"
grep -m1 "OCC_VERSION_COMPLETE " "$OCCT_INC/Standard_Version.hxx" || true

TK_LIBS="-lTKPrim -lTKBO -lTKBool -lTKFillet -lTKMesh -lTKTopAlgo -lTKGeomAlgo -lTKShHealing -lTKBRep -lTKGeomBase -lTKG3d -lTKG2d -lTKMath -lTKernel -lTKSTEP -lTKXSBase -lTKSTL"
# 8.0.1 renamed some STEP toolkits (TKDESTEP/TKDE); tolerate either set.
# Detection searches the multiarch lib dirs too (Ubuntu puts them in
# /usr/lib/x86_64-linux-gnu, not $OCCT_PREFIX/lib).
HAS_STEP=0; HAS_DESTEP=0
for d in "$OCCT_LIB" "$OCCT_PREFIX/lib/x86_64-linux-gnu"; do
  [ -e "$d/libTKSTEP.so" ] && HAS_STEP=1
  [ -e "$d/libTKDESTEP.so" ] && HAS_DESTEP=1
done
if [ "$HAS_STEP" = 0 ] && [ "$HAS_DESTEP" = 1 ]; then
  TK_LIBS="-lTKPrim -lTKBO -lTKBool -lTKFillet -lTKMesh -lTKTopAlgo -lTKGeomAlgo -lTKShHealing -lTKBRep -lTKGeomBase -lTKG3d -lTKG2d -lTKMath -lTKernel -lTKDESTEP -lTKDE -lTKXSBase -lTKDESTL"
fi

echo "== mock backend =="
$CXX $CXXFLAGS -DCC_MOCK src/cc_interpreter.cpp src/ccgeom_mock.cpp src/ccsim.cpp src/ccsim_commands.cpp src/ccsim_backend_mock.cpp tests/test_engine.cpp -o build/test_engine_mock
./build/test_engine_mock mock

echo "== OCCT backend =="
$CXX $CXXFLAGS -I"$OCCT_INC" src/cc_interpreter.cpp src/ccgeom_occt.cpp src/ccsim.cpp src/ccsim_commands.cpp tests/test_engine.cpp \
  -L"$OCCT_LIB" -Wl,-rpath,"$OCCT_LIB" $TK_LIBS -lpthread -o build/test_engine_occt
./build/test_engine_occt occt

echo "== mc adapter compile check (object only; CascadeKit link is a device/CI step) =="
# Needs a cascade-port checkout; on CI runners the dedicated macOS job
# of build-native-engine.yml does this check against the pinned
# cascade-ios fetch, so skip (loudly) when no checkout is present.
PORT_DIR="${CC_PORT_DIR:-$HOME/workspace/cascade-port}"
if [ -f "$PORT_DIR/Facade/occt_facade.h" ]; then
  $CXX $CXXFLAGS -I"$PORT_DIR/Facade" -I src -c src/ccgeom_mc.cpp -o build/ccgeom_mc.o \
    && echo "ccgeom_mc.cpp compiles against the real cascade-port occt_facade.h"
  $CXX $CXXFLAGS -I"$PORT_DIR/Facade" -I src -c src/ccsim_backend_mc.cpp -o build/ccsim_backend_mc.o \
    && echo "ccsim_backend_mc.cpp compiles against the real cascade-port occt_facade.h"
else
  echo "SKIP: no cascade-port checkout at $PORT_DIR (mc adapter check runs in the macOS CI job)"
fi

echo "ALL HOST BUILDS DONE"
