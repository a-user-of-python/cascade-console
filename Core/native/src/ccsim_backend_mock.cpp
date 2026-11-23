// ============================================================================
// ccsim_backend_mock.cpp — analytic test double for ccsim_backend.h,
// companion to the engine's ccgeom_mock.cpp. Host tests ONLY, never
// shipped.
//
// The engine mock retains no analytic geometry beyond volume / area
// / bbox / counts, so this extension is implemented over the PUBLIC
// ccgeom API only, and is exact for one case: a shape whose volume
// equals its bbox volume AND which has exactly 6 faces (a box, in
// either backend's creation order). For such a shape the six faces
// are the bbox planes, in THIS test-double order (NOT the OCCT
// census order — the mock has no census; the host test discovers
// faces by probing distances, never by assuming an index):
//   0: x = xmin   1: x = xmax   2: y = ymin
//   3: y = ymax   4: z = zmin   5: z = zmax
// Anything else fails loudly with CCGEOM_ERR_OCCT, exactly the
// engine mock's philosophy: a test double must never invent
// geometry it cannot compute exactly.
// ============================================================================
#include "ccsim_backend.h"

#include <algorithm>
#include <cmath>

namespace {
bool boxFaces(CCGeomShape* s, double bb[6]) {
  if (!s) return false;
  int e = CCGEOM_OK;
  if (ccgeom_bbox(s, bb, &e) != CCGEOM_OK) return false;
  int faces = 0, edges = 0;
  if (ccgeom_counts(s, &faces, &edges, &e) != CCGEOM_OK) return false;
  if (faces != 6) return false;
  double vol = ccgeom_volume(s, &e);
  if (e != CCGEOM_OK) return false;
  double bv = (bb[3] - bb[0]) * (bb[4] - bb[1]) * (bb[5] - bb[2]);
  return bv > 0 && std::fabs(vol - bv) <= 1e-9 * bv;
}
int fail(int* err, int code) { if (err) *err = code; return code; }
// Face plane: axis (0=x,1=y,2=z) and whether it is the max side.
void facePlane(int idx, int& axis, bool& isMax) {
  axis = idx / 2;
  isMax = (idx % 2) == 1;
}
}  // namespace

int ccgeom_point_inside(CCGeomShape* s, double x, double y, double z,
                        int* err) {
  double bb[6];
  if (!boxFaces(s, bb)) {
    // Not provably a box: only the bbox test is available, and using
    // it for a non-box would invent material. Fail loudly.
    if (err) *err = CCGEOM_ERR_OCCT;
    return 0;
  }
  if (err) *err = CCGEOM_OK;
  const double p[3] = {x, y, z};
  for (int d = 0; d < 3; ++d)
    if (p[d] < bb[d] || p[d] > bb[d + 3]) return 0;
  return 1;
}

double ccgeom_point_face_distance(CCGeomShape* s, int faceIndex,
                                  double x, double y, double z, int* err) {
  double bb[6];
  if (!boxFaces(s, bb)) { fail(err, CCGEOM_ERR_OCCT); return -1; }
  if (faceIndex < 0 || faceIndex > 5) { fail(err, CCGEOM_ERR_INVALID_ARG); return -1; }
  int axis; bool isMax;
  facePlane(faceIndex, axis, isMax);
  const double p[3] = {x, y, z};
  double q[3] = {x, y, z};
  q[axis] = isMax ? bb[axis + 3] : bb[axis];
  for (int d = 0; d < 3; ++d) {
    if (d == axis) continue;
    q[d] = std::min(std::max(q[d], bb[d]), bb[d + 3]);
  }
  double dx = p[0] - q[0], dy = p[1] - q[1], dz = p[2] - q[2];
  if (err) *err = CCGEOM_OK;
  return std::sqrt(dx * dx + dy * dy + dz * dz);
}

double ccgeom_face_area(CCGeomShape* s, int faceIndex, int* err) {
  double bb[6];
  if (!boxFaces(s, bb)) { fail(err, CCGEOM_ERR_OCCT); return -1; }
  if (faceIndex < 0 || faceIndex > 5) { fail(err, CCGEOM_ERR_INVALID_ARG); return -1; }
  int axis; bool isMax;
  facePlane(faceIndex, axis, isMax);
  double a = 1;
  for (int d = 0; d < 3; ++d) if (d != axis) a *= (bb[d + 3] - bb[d]);
  if (err) *err = CCGEOM_OK;
  return a;
}

int ccgeom_face_point_normal(CCGeomShape* s, int faceIndex,
                             double pointOut[3], double normalOut[3],
                             int* err) {
  double bb[6];
  if (!boxFaces(s, bb)) return fail(err, CCGEOM_ERR_OCCT);
  if (faceIndex < 0 || faceIndex > 5) return fail(err, CCGEOM_ERR_INVALID_ARG);
  int axis; bool isMax;
  facePlane(faceIndex, axis, isMax);
  for (int d = 0; d < 3; ++d) {
    pointOut[d] = (bb[d] + bb[d + 3]) / 2.0;
    normalOut[d] = 0.0;
  }
  pointOut[axis] = isMax ? bb[axis + 3] : bb[axis];
  normalOut[axis] = isMax ? 1.0 : -1.0;
  if (err) *err = CCGEOM_OK;
  return CCGEOM_OK;
}
