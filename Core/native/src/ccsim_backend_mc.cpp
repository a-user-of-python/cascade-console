// ============================================================================
// ccsim_backend_mc.cpp — device implementation of ccsim_backend.h
// over the cascade-port mc_* facade (CascadeKit, OCCT 8.0.1). This is
// an ADAPTER: every call forwards to an existing mc_* function. It
// is compile-checked on the host against the real facade header
// (object only — CascadeKit linking is a device/CI step, exactly as
// with the engine's ccgeom_mc.cpp).
//
// Two honest limitations of the current facade surface, both with a
// proposed one-function addition specified in INTEGRATION.md:
//  1. Point-to-face distance: mc_* has no arbitrary point-to-face
//     distance (mc_fem_nodes_on_face does the mapping internally on
//     its own mesh). Below, PLANAR faces use the exact point-to-plane
//     distance from mc_face_plane — a lower bound on the trimmed
//     face distance, so a node just past a face's edge can map when
//     BRepExtrema would reject it. Non-planar faces fail loudly.
//     Proposed addition: mc_point_face_distance (one BRepExtrema
//     wrap, facade style) for exact parity with section 11.
//  2. Face point+normal: mc_face_info reports the outward normal
//     only for planar faces; pressure on a non-planar face therefore
//     fails loudly here. Proposed addition: mc_face_point_normal
//     (BRepAdaptor_Surface D1, as in the OCCT backend file).
// Also note: mc_contains reports boundary points as OUTSIDE (0),
// where the OCCT sim backend counts them in (ccsim_backend.h) —
// voxel centres landing exactly on a face are dropped on device.
// Grid-aligned parts should use a mesh size that does not put
// centres on faces; the mesh-volume drift readout shows the effect.
// ============================================================================
#include "ccsim_backend.h"
#include "occt_facade.h"

#include <cmath>

namespace {
MCFacadeShape* raw(CCGeomShape* s) {
  return s ? (MCFacadeShape*)ccgeom_native_handle(s) : nullptr;
}
int xlate(int mcErr) {
  switch (mcErr) {
    case MC_OK: return CCGEOM_OK;
    case MC_ERR_INVALID_ARG: return CCGEOM_ERR_INVALID_ARG;
    case MC_ERR_EMPTY_RESULT: return CCGEOM_ERR_EMPTY;
    default: return CCGEOM_ERR_OCCT;
  }
}
int faceCount(MCFacadeShape* h, int* errOut) {
  int e = MC_OK, faces = 0, edges = 0, verts = 0;
  mc_shape_counts(h, &faces, &edges, &verts, &e);
  if (errOut) *errOut = xlate(e);
  return faces;
}
}  // namespace

int ccgeom_point_inside(CCGeomShape* s, double x, double y, double z,
                        int* err) {
  MCFacadeShape* h = raw(s);
  if (!h) { if (err) *err = CCGEOM_ERR_INVALID_ARG; return 0; }
  int e = MC_OK;
  int r = mc_contains(h, x, y, z, &e);
  if (err) *err = xlate(e);
  if (e != MC_OK) return 0;
  return r > 0 ? 1 : 0;
}

double ccgeom_point_face_distance(CCGeomShape* s, int faceIndex,
                                  double x, double y, double z, int* err) {
  MCFacadeShape* h = raw(s);
  if (!h) { if (err) *err = CCGEOM_ERR_INVALID_ARG; return -1; }
  int ce = CCGEOM_OK;
  int faces = faceCount(h, &ce);
  if (ce != CCGEOM_OK) { if (err) *err = ce; return -1; }
  if (faceIndex < 0 || faceIndex >= faces) {
    if (err) *err = CCGEOM_ERR_INVALID_ARG;
    return -1;
  }
  int e = MC_OK;
  double origin[3], xDir[3], yDir[3];
  int rc = mc_face_plane(h, faceIndex, origin, xDir, yDir, &e);
  if (e != MC_OK || rc != MC_OK) {
    // Non-planar face: refused by mc_face_plane (MC_ERR_INVALID_ARG)
    // — for THIS function that means "not computable here", not a
    // bad index (the index was range-checked above).
    if (err) *err = CCGEOM_ERR_OCCT;
    return -1;
  }
  // Outward normal = xDir x yDir (mc_face_plane contract).
  double n[3] = {xDir[1] * yDir[2] - xDir[2] * yDir[1],
                 xDir[2] * yDir[0] - xDir[0] * yDir[2],
                 xDir[0] * yDir[1] - xDir[1] * yDir[0]};
  double d = (x - origin[0]) * n[0] + (y - origin[1]) * n[1] +
             (z - origin[2]) * n[2];
  if (err) *err = CCGEOM_OK;
  return std::fabs(d);
}

double ccgeom_face_area(CCGeomShape* s, int faceIndex, int* err) {
  MCFacadeShape* h = raw(s);
  if (!h) { if (err) *err = CCGEOM_ERR_INVALID_ARG; return -1; }
  int e = MC_OK;
  double area = 0, center[3], normal[3];
  int isPlanar = 0;
  int rc = mc_face_info(h, faceIndex, &area, center, normal, &isPlanar, &e);
  if (err) *err = xlate(e);
  if (e != MC_OK || rc != MC_OK) return -1;
  return area;
}

int ccgeom_face_point_normal(CCGeomShape* s, int faceIndex,
                             double pointOut[3], double normalOut[3],
                             int* err) {
  MCFacadeShape* h = raw(s);
  if (!h || !pointOut || !normalOut) {
    if (err) *err = CCGEOM_ERR_INVALID_ARG;
    return CCGEOM_ERR_INVALID_ARG;
  }
  int e = MC_OK;
  double area = 0;
  int isPlanar = 0;
  int rc = mc_face_info(h, faceIndex, &area, pointOut, normalOut, &isPlanar, &e);
  if (e != MC_OK || rc != MC_OK) { if (err) *err = xlate(e); return xlate(e); }
  if (!isPlanar) {
    // mc_face_info reports (0,0,0) normals for non-planar faces.
    if (err) *err = CCGEOM_ERR_OCCT;
    return CCGEOM_ERR_OCCT;
  }
  if (err) *err = CCGEOM_OK;
  return CCGEOM_OK;
}
