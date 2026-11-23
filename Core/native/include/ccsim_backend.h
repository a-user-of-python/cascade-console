// ============================================================================
// ccsim_backend.h — Layer-1 extension functions the simulation module
// needs beyond ccgeom.h (the Cascade Console engine's geometry
// interface). Same conventions as ccgeom.h: mm units, inputs never
// consumed, failures are CCGEOM_* error codes, never exceptions across
// the boundary, messages via ccgeom_last_error().
//
// Face indices are the shared census indices (TopExp traversal order,
// 0-based here) — the same space as fillet/chamfer edge indices and
// the cascade-port facade's section-8 census, so `@face n` in a sim
// command, a tessellation face group and an mc_face_info call all mean
// the same face.
//
// Implementations (one per engine backend, exactly like ccgeom):
//   src/ccsim_backend_occt.cpp — direct OCCT (host proof; BRepClass3d
//                                classifier + BRepExtrema distances)
//   src/ccsim_backend_mc.cpp   — adapter over the cascade-port mc_*
//                                facade (device build; compile-checked
//                                on the host, see INTEGRATION.md for
//                                its one proposed mc_* addition)
//   src/ccsim_backend_mock.cpp — analytic test double: exact for
//                                box-like shapes only (volume == bbox
//                                volume), fails loudly otherwise.
//                                Host tests only, NEVER shipped.
// ============================================================================
#pragma once

#include "ccgeom.h"

#ifdef __cplusplus
extern "C" {
#endif

/// 1 when (x,y,z) is inside a solid of the shape (points exactly ON
/// the boundary count as inside — voxel cell centres that land on a
/// face are measure-zero in practice, and counting them in keeps
/// grid-aligned thin features; the cascade-port mc_contains differs
/// here, it reports boundary as outside — see INTEGRATION.md).
/// 0 when outside. Returns a CCGEOM_* code via *err on failure
/// (CCGEOM_ERR_EMPTY when the shape contains no solid).
int ccgeom_point_inside(CCGeomShape* s, double x, double y, double z,
                        int* err);

/// Euclidean distance from (x,y,z) to census face `faceIndex`
/// (0-based). Negative return + *err set on failure
/// (CCGEOM_ERR_INVALID_ARG for an out-of-range face index).
double ccgeom_point_face_distance(CCGeomShape* s, int faceIndex,
                                  double x, double y, double z,
                                  int* err);

/// Area (mm^2) of census face `faceIndex`. Negative + *err on failure.
double ccgeom_face_area(CCGeomShape* s, int faceIndex, int* err);

/// A point ON census face `faceIndex` (its mid-parameter point) and
/// the face's OUTWARD unit normal there. For curved faces this is the
/// true surface normal at that point (OCCT backend). Returns a
/// CCGEOM_* code.
int ccgeom_face_point_normal(CCGeomShape* s, int faceIndex,
                             double pointOut[3], double normalOut[3],
                             int* err);

#ifdef __cplusplus
}
#endif
