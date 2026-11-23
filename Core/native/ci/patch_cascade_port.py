#!/usr/bin/env python3
"""CI-only patch: add mc_clone_shape + mc_export_stl to a cascade-ios
checkout (a-user-of-python/cascade-ios, pinned in build-ipa.yml).

WHY THIS EXISTS / CAVEAT (read before reusing):
Core/native/src/mc_additions.cpp is delivered as a *commented* paste
block, and as delivered it does NOT match the real facade: it treats
the handle's `_impl` as a raw TopoDS_Shape* and calls a `setError()`
helper. In the real Facade/occt_facade.cpp (cascade-ios
061875afb5384227db5f39cba81266cf889257a4) `_impl` points to a private
`ShapeImpl { TopoDS_Shape shape; ... }`, accessed via the internal
helpers `shapeOf()` / `wrap()`, and the internal error helper is
`fail(err, code, msg)` writing `g_lastError`. This script injects
implementations written against THOSE real helpers, inside the
facade's own extern "C" block, so they compile as part of the facade
translation unit exactly as the engine report intended. The patch is
applied ONLY to the ephemeral CI checkout — cascade-ios itself is
never modified upstream, and OCCT sources are untouched (LGPL).

Usage: patch_cascade_port.py <cascade-ios checkout dir>
Idempotent: exits 0 without changes if already patched.
Fails loudly (exit 1) if any anchor is missing — no silent drift.
"""
import sys
from pathlib import Path

root = Path(sys.argv[1])
hdr = root / "Facade" / "occt_facade.h"
cpp = root / "Facade" / "occt_facade.cpp"

DECLS = """
// ---- Cascade Console additions (CI-injected; see mc_additions.h) ----
/// New owned handle wrapping the same (immutable) shape as `s`.
/// Release with mc_free_shape(). NULL on failure (*err set).
MCFacadeShape* mc_clone_shape(MCFacadeShape* s, int* err);

/// Write `s` to a binary STL file at `path` (UTF-8), tessellating at
/// 0.5 mm linear deflection first. Returns MC_OK on success.
int mc_export_stl(MCFacadeShape* s, const char* path, int* err);

"""

IMPLS = """
// ---- Cascade Console additions (CI-injected) ----
// Written against the facade's real internal helpers: shapeOf()/wrap()
// (ShapeImpl access) and fail() (g_lastError setter). See
// patch_cascade_port.py in the cascade-console repo for why the
// originally delivered paste block could not be used verbatim.
MCFacadeShape* mc_clone_shape(MCFacadeShape* s, int* err) {
  if (!s || !s->_impl) {
    fail(err, MC_ERR_INVALID_ARG, "mc_clone_shape: null shape");
    return nullptr;
  }
  return wrap(shapeOf(s), err);
}

int mc_export_stl(MCFacadeShape* s, const char* path, int* err) {
  if (!s || !s->_impl || !path) {
    return fail(err, MC_ERR_INVALID_ARG, "mc_export_stl: null argument");
  }
  try {
    const TopoDS_Shape& shape = shapeOf(s);
    BRepMesh_IncrementalMesh mesher(shape, 0.5);
    (void)mesher;
    StlAPI_Writer writer;
    if (!writer.Write(shape, path)) {
      return fail(err, MC_ERR_OCCT, "mc_export_stl: writer did not complete");
    }
  } catch (const std::exception& e) {
    return fail(err, MC_ERR_OCCT, e.what());
  }
  if (err) *err = MC_OK;
  return MC_OK;
}

"""

h = hdr.read_text()
c = cpp.read_text()

if "mc_clone_shape" in h and "mc_clone_shape" in c:
    print("already patched")
    sys.exit(0)

# Header: insert declarations just before the closing extern "C" guard.
anchor_h = "#ifdef __cplusplus\n}\n#endif"
idx = h.rfind(anchor_h)
if idx < 0:
    sys.exit("FATAL: header anchor (extern C close) not found")
h = h[:idx] + DECLS + h[idx:]
hdr.write_text(h)

# Cpp: StlAPI_Writer include (TKDESTL is in the staged toolkit tree).
if "StlAPI_Writer.hxx" not in c:
    anchor_inc = '#include "occt_facade.h"'
    if anchor_inc not in c:
        sys.exit("FATAL: cpp include anchor not found")
    c = c.replace(anchor_inc, anchor_inc + "\n#include <StlAPI_Writer.hxx>", 1)

# Cpp: implementations just before the final extern "C" close, so the
# facade's anonymous-namespace helpers (shapeOf/wrap/fail) are in scope.
anchor_c = '}  // extern "C"'
idx = c.rfind(anchor_c)
if idx < 0:
    sys.exit("FATAL: cpp anchor (extern C close) not found")
c = c[:idx] + IMPLS + c[idx:]
cpp.write_text(c)
print("patched cascade-port facade: mc_clone_shape + mc_export_stl added")
