#!/usr/bin/env python3
"""CI-only patch: add the Cascade Console Layer-1 additions to a
cascade-ios checkout (a-user-of-python/cascade-ios, pinned in
build-ipa.yml):

  * mc_clone_shape   — second owned handle for an immutable shape.
  * mc_export_stl    — binary STL via StlAPI_Writer.
  * mc_tessellate_ex — (v0.4.2) mc_tessellate with a caller-chosen
                       ANGULAR deflection. The pinned mc_tessellate
                       hardcodes 0.5 rad, which leaves small curved
                       faces (a 1 mm fillet) faceted no matter how
                       fine the linear deflection is — measured:
                       a filleted 10 mm cube stays at 628 triangles
                       for every linear deflection from 0.5 to
                       0.05 mm. The _ex body is the pinned
                       mc_tessellate body verbatim apart from the
                       signature, the mesher's angle argument and
                       the error-label strings.
  * mc_export_stl tessellates with the same size-aware policy the
    viewer mesh uses (v0.4.2): linear deflection =
    clamp(0.004 * bbox diagonal, 0.02, 0.5) mm, angular deflection
    0.20 rad — an exported STL carries the same smooth curves the
    viewer shows, instead of the old fixed 0.5 mm mesh.

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
Idempotent: each addition is applied only when missing; an
mc_export_stl injected by an older version of this script (fixed
0.5 mm mesh) is upgraded in place. Fails loudly (exit 1) if any
anchor is missing — no silent drift.
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

/// Write `s` to a binary STL file at `path` (UTF-8), tessellating
/// with the size-aware viewer policy first (v0.4.2: linear
/// deflection clamp(0.004 * bbox diagonal, 0.02, 0.5) mm, angular
/// deflection 0.20 rad). Returns MC_OK on success.
int mc_export_stl(MCFacadeShape* s, const char* path, int* err);

/// mc_tessellate with a caller-chosen angular deflection (radians).
/// The pinned mc_tessellate hardcodes 0.5 rad, which facets small
/// curved faces (fillets) regardless of the linear deflection.
int mc_tessellate_ex(MCFacadeShape* s, double deflectionMM,
                     double angleRad, MCFacadeMesh* out, int* err);

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
    // v0.4.2: the same size-aware tessellation policy as the viewer
    // mesh (ccgeom_mc.cpp's tessellationPolicy): linear deflection
    // scales with the bounding-box diagonal so a 1 mm fillet and a
    // 100 mm sphere both come out smooth; angular deflection
    // 0.20 rad. Keep the two formulas in step.
    Bnd_Box bb;
    BRepBndLib::Add(shape, bb);
    double x0 = 0, y0 = 0, z0 = 0, x1 = 0, y1 = 0, z1 = 0;
    bb.Get(x0, y0, z0, x1, y1, z1);
    const double diag = std::sqrt((x1 - x0) * (x1 - x0) +
                                  (y1 - y0) * (y1 - y0) +
                                  (z1 - z0) * (z1 - z0));
    double lin = 0.004 * diag;
    if (lin < 0.02) lin = 0.02;
    if (lin > 0.5) lin = 0.5;
    BRepMesh_IncrementalMesh mesher(shape, lin, Standard_False,
                                    0.20, Standard_True);
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

// mc_tessellate_ex: the pinned mc_tessellate body verbatim apart
// from the signature, the mesher's angle argument (angleRad instead
// of the hardcoded 0.5) and the error-label strings. The pinned
// function cannot be reused for fine work: its 0.5 rad angular
// deflection facets small curved faces no matter how fine the
// linear deflection is (v0.4.2 measurement: filleted 10 mm cube,
// 628 triangles at every linear deflection from 0.5 to 0.05 mm).
int mc_tessellate_ex(MCFacadeShape* s, double deflectionMM,
                     double angleRad, MCFacadeMesh* out,
                     int* err) {
  if (!s || !out) {
    return fail(err, MC_ERR_INVALID_ARG, "null argument");
  }
  std::memset(out, 0, sizeof(*out));
  try {
    BRepMesh_IncrementalMesh mesher(shapeOf(s), deflectionMM, Standard_False,
                                    angleRad, Standard_True);
    mesher.Perform();

    NCollection_IndexedMap<TopoDS_Shape, TopTools_ShapeMapHasher> faceMap;
    TopExp::MapShapes(shapeOf(s), TopAbs_FACE, faceMap);
    const int faceCount = faceMap.Extent();

    std::vector<float> positions;
    std::vector<float> normals;
    std::vector<int> indices;
    std::vector<int> faceStart(faceCount, 0);
    std::vector<int> faceCountArr(faceCount, 0);

    for (int fi = 1; fi <= faceCount; ++fi) {
      const TopoDS_Face face = TopoDS::Face(faceMap.FindKey(fi));
      TopLoc_Location loc;
      Handle(Poly_Triangulation) tri = BRep_Tool::Triangulation(face, loc);
      faceStart[fi - 1] = (int)indices.size() / 3;
      if (tri.IsNull()) {
        faceCountArr[fi - 1] = 0;
        continue;
      }
      if (!tri->HasNormals()) tri->ComputeNormals();
      const gp_Trsf& trsf = loc.Transformation();
      const bool reversed = (face.Orientation() == TopAbs_REVERSED);
      const int baseVertex = (int)positions.size() / 3;
      const int nbNodes = tri->NbNodes();
      for (int i = 1; i <= nbNodes; ++i) {
        gp_Pnt p = tri->Node(i).Transformed(trsf);
        positions.push_back((float)p.X());
        positions.push_back((float)p.Y());
        positions.push_back((float)p.Z());
        gp_Vec nrm = tri->Normal(i);
        gp_Dir nd(nrm);
        nd.Transform(trsf);
        float nx = (float)nd.X(), ny = (float)nd.Y(), nz = (float)nd.Z();
        if (reversed) { nx = -nx; ny = -ny; nz = -nz; }
        normals.push_back(nx);
        normals.push_back(ny);
        normals.push_back(nz);
      }
      const int nbTris = tri->NbTriangles();
      for (int i = 1; i <= nbTris; ++i) {
        Standard_Integer n1, n2, n3;
        tri->Triangle(i).Get(n1, n2, n3);
        if (reversed) std::swap(n2, n3);
        indices.push_back(baseVertex + n1 - 1);
        indices.push_back(baseVertex + n2 - 1);
        indices.push_back(baseVertex + n3 - 1);
      }
      faceCountArr[fi - 1] = nbTris;
    }

    const size_t nv = positions.size() / 3;
    const size_t nt = indices.size() / 3;
    out->positions = (float*)std::malloc(sizeof(float) * (nv * 3 ? nv * 3 : 1));
    out->normals = (float*)std::malloc(sizeof(float) * (nv * 3 ? nv * 3 : 1));
    out->indices = (int*)std::malloc(sizeof(int) * (nt * 3 ? nt * 3 : 1));
    out->faceTriStart = (int*)std::malloc(sizeof(int) * (faceCount ? faceCount : 1));
    out->faceTriCount = (int*)std::malloc(sizeof(int) * (faceCount ? faceCount : 1));
    if (!out->positions || !out->normals || !out->indices ||
        !out->faceTriStart || !out->faceTriCount) {
      mc_free_mesh(out);
      return fail(err, MC_ERR_OCCT, "out of memory");
    }
    if (nv) {
      std::memcpy(out->positions, positions.data(), sizeof(float) * nv * 3);
      std::memcpy(out->normals, normals.data(), sizeof(float) * nv * 3);
    }
    if (nt) std::memcpy(out->indices, indices.data(), sizeof(int) * nt * 3);
    if (faceCount) {
      std::memcpy(out->faceTriStart, faceStart.data(), sizeof(int) * faceCount);
      std::memcpy(out->faceTriCount, faceCountArr.data(), sizeof(int) * faceCount);
    }
    out->vertexCount = (int)nv;
    out->triangleCount = (int)nt;
    out->faceCount = faceCount;
    if (err) *err = MC_OK;
    return MC_OK;
  } catch (const Standard_Failure& e) {
    setOcctError(err, "mc_tessellate_ex", e);
    return MC_ERR_OCCT;
  }
}

"""

# The mc_export_stl body injected by pre-v0.4.2 versions of this
# script (fixed 0.5 mm mesh). If a checkout was already patched by
# one of those, the old body is upgraded to the policy version in
# IMPLS above by exact replacement.
OLD_STL_IMPL = """
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
    print("base additions already present")
else:
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

    # Cpp: implementations just before the final extern "C" close, so
    # the facade's anonymous-namespace helpers (shapeOf/wrap/fail)
    # are in scope.
    anchor_c = '}  // extern "C"'
    idx = c.rfind(anchor_c)
    if idx < 0:
        sys.exit("FATAL: cpp anchor (extern C close) not found")
    c = c[:idx] + IMPLS + c[idx:]
    cpp.write_text(c)
    print("patched cascade-port facade: mc_clone_shape + mc_export_stl + mc_tessellate_ex added")

# Upgrade path: a checkout patched by a pre-v0.4.2 run of this
# script carries the fixed-0.5 mm mc_export_stl and no
# mc_tessellate_ex. Bring it to the same state as a fresh patch.
h = hdr.read_text()
c = cpp.read_text()
changed = False
if "mc_tessellate_ex" not in c:
    if OLD_STL_IMPL not in c:
        sys.exit("FATAL: pre-v0.4.2 mc_export_stl body not found for upgrade")
    # Replace just the STL function inside IMPLS-shaped surroundings:
    # extract the new STL body from IMPLS and swap it in.
    start = IMPLS.index("int mc_export_stl")
    end = IMPLS.index("// mc_tessellate_ex:")
    new_stl = IMPLS[start:end].rstrip() + "\n"
    c = c.replace(OLD_STL_IMPL, "\n" + new_stl, 1)
    # Append the tessellate_ex implementation before the extern "C"
    # close (the additions sit just above it).
    start = IMPLS.index("// mc_tessellate_ex:")
    tess = IMPLS[start:]
    anchor_c = '}  // extern "C"'
    idx = c.rfind(anchor_c)
    if idx < 0:
        sys.exit("FATAL: cpp anchor (extern C close) not found for upgrade")
    c = c[:idx] + "\n" + tess + c[idx:]
    changed = True
if "mc_tessellate_ex" not in h:
    anchor_h = "#ifdef __cplusplus\n}\n#endif"
    idx = h.rfind(anchor_h)
    if idx < 0:
        sys.exit("FATAL: header anchor (extern C close) not found for upgrade")
    decl_start = DECLS.index("/// mc_tessellate with a caller-chosen")
    h = h[:idx] + "\n" + DECLS[decl_start:] + h[idx:]
    hdr.write_text(h)
    changed = True
if changed:
    cpp.write_text(c)
    print("upgraded pre-v0.4.2 patch: mc_export_stl policy + mc_tessellate_ex added")
