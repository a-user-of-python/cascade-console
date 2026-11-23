// ============================================================================
// ccgeom_mock.cpp — ANALYTIC TEST DOUBLE for ccgeom.h. Host logic tests
// ONLY — never linked into an app build (the build scripts keep it out of
// the device targets; see ../README.md).
//
// What is exact here: volumes/areas/bboxes/counts of the five primitives,
// of polygon-prism extrudes (shoelace area x dist), of transforms
// (volume invariant, bbox recomputed from the 8 corners), of copy, and of
// booleans BETWEEN BOX-LIKE shapes (volume == bbox volume: boxes and
// box-boolean results), where AABB inclusion-exclusion is exact.
// Fillet/chamfer are exact only for the all-edges box case (closed-form
// rounded/chamfered box volume; area/counts are then approximate and the
// harness does not assert them). Anything outside that: CCGEOM_ERR_OCCT
// with a "mock limitation" message — the mock FAILS LOUDLY instead of
// inventing geometry, exactly like the real backend would fail in OCCT.
// Tessellation returns the bounding box's 12 triangles for every shape:
// a placeholder for view-data plumbing tests ONLY (counts/indices
// shape), never a claim about the real surface.
// ============================================================================
#include "ccgeom.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

struct CCGeomShape {
  double volume = 0, area = 0;
  double bbox[6] = {0, 0, 0, 0, 0, 0};
  int faces = 0, edges = 0;
  bool boxLike = false;  // volume == bbox volume (AABB booleans stay exact)
};

static thread_local std::string g_lastError;
const char* ccgeom_last_error(void) { return g_lastError.c_str(); }
static int setErr(int* err, int code, const char* msg) {
  g_lastError = msg; if (err) *err = code; return code;
}
static CCGeomShape* mk(double vol, double area, const double bb[6], int f, int e, bool boxLike, int* err) {
  if (err) *err = CCGEOM_OK;
  auto* s = new CCGeomShape();
  s->volume = vol; s->area = area; std::memcpy(s->bbox, bb, sizeof(s->bbox));
  s->faces = f; s->edges = e; s->boxLike = boxLike;
  return s;
}
CCGeomShape* ccgeom_clone(CCGeomShape* s) { return s ? new CCGeomShape(*s) : nullptr; }
void ccgeom_free(CCGeomShape* s) { delete s; }
void ccgeom_free_buffer(void* p) { std::free(p); }

CCGeomShape* ccgeom_box(double w, double d, double h, int* err) {
  double bb[6] = {0, 0, 0, w, d, h};
  return mk(w * d * h, 2 * (w * d + w * h + d * h), bb, 6, 12, true, err);
}
CCGeomShape* ccgeom_cylinder(double r, double h, int* err) {
  double bb[6] = {-r, -r, 0, r, r, h};
  return mk(M_PI * r * r * h, 2 * M_PI * r * r + 2 * M_PI * r * h, bb, 3, 3, false, err);
}
CCGeomShape* ccgeom_sphere(double r, int* err) {
  double bb[6] = {-r, -r, -r, r, r, r};
  return mk(4.0 / 3.0 * M_PI * r * r * r, 4 * M_PI * r * r, bb, 1, 3, false, err);
}
CCGeomShape* ccgeom_cone(double r1, double r2, double h, int* err) {
  double R = std::max(r1, r2);
  double bb[6] = {-R, -R, 0, R, R, h};
  double vol = M_PI * h / 3.0 * (r1 * r1 + r1 * r2 + r2 * r2);
  double slant = std::sqrt(h * h + (r1 - r2) * (r1 - r2));
  double area = M_PI * (r1 + r2) * slant + M_PI * r1 * r1 + M_PI * r2 * r2;
  return mk(vol, area, bb, 3, 3, false, err);
}
CCGeomShape* ccgeom_torus(double ringR, double tubeR, int* err) {
  double R = ringR + tubeR;
  double bb[6] = {-R, -R, -tubeR, R, R, tubeR};
  return mk(2 * M_PI * M_PI * ringR * tubeR * tubeR, 4 * M_PI * M_PI * ringR * tubeR, bb, 1, 2, false, err);
}
CCGeomShape* ccgeom_prism(const double* xy, int n, double dist, int* err) {
  if (!xy || n < 3) { setErr(err, CCGEOM_ERR_INVALID_ARG, "mock prism: < 3 points"); return nullptr; }
  double a = 0, per = 0, mnx = 1e300, mny = 1e300, mxx = -1e300, mxy = -1e300;
  for (int i = 0; i < n; ++i) {
    int j = (i + 1) % n;
    a += xy[2 * i] * xy[2 * j + 1] - xy[2 * j] * xy[2 * i + 1];
    per += std::hypot(xy[2 * j] - xy[2 * i], xy[2 * j + 1] - xy[2 * i + 1]);
    mnx = std::min(mnx, xy[2 * i]); mxx = std::max(mxx, xy[2 * i]);
    mny = std::min(mny, xy[2 * i + 1]); mxy = std::max(mxy, xy[2 * i + 1]);
  }
  a = std::fabs(a) / 2.0;
  double bb[6] = {mnx, mny, 0, mxx, mxy, dist};
  return mk(a * dist, 2 * a + per * dist, bb, n + 2, 3 * n, false, err);
}
static double overlapVol(const CCGeomShape* a, const CCGeomShape* b) {
  double dx = std::min(a->bbox[3], b->bbox[3]) - std::max(a->bbox[0], b->bbox[0]);
  double dy = std::min(a->bbox[4], b->bbox[4]) - std::max(a->bbox[1], b->bbox[1]);
  double dz = std::min(a->bbox[5], b->bbox[5]) - std::max(a->bbox[2], b->bbox[2]);
  if (dx <= 0 || dy <= 0 || dz <= 0) return 0;
  return dx * dy * dz;
}
static CCGeomShape* booleanOp(CCGeomShape* a, CCGeomShape* b, int* err, int which, const char* op) {
  if (!a || !b) { setErr(err, CCGEOM_ERR_INVALID_ARG, "mock boolean: null operand"); return nullptr; }
  if (!a->boxLike || !b->boxLike) {
    setErr(err, CCGEOM_ERR_OCCT, "mock limitation: booleans are exact only between box-like shapes");
    return nullptr;
  }
  double inter = overlapVol(a, b);
  double vol = which == 0 ? a->volume + b->volume - inter : which == 1 ? a->volume - inter : inter;
  double bb[6];
  if (which == 0) {
    for (int i = 0; i < 3; ++i) { bb[i] = std::min(a->bbox[i], b->bbox[i]); bb[i + 3] = std::max(a->bbox[i + 3], b->bbox[i + 3]); }
  } else if (which == 1) {
    std::memcpy(bb, a->bbox, sizeof(bb));
  } else {
    for (int i = 0; i < 3; ++i) { bb[i] = std::max(a->bbox[i], b->bbox[i]); bb[i + 3] = std::min(a->bbox[i + 3], b->bbox[i + 3]); }
  }
  // Counts/area of boolean results are not analytic in the mock; report
  // the operands' sums as placeholders and let the harness assert volume
  // and bbox only (documented in tests/test_engine.cpp).
  return mk(vol, a->area + b->area, bb, a->faces + b->faces, a->edges + b->edges, true, err);
}
CCGeomShape* ccgeom_unite(CCGeomShape* a, CCGeomShape* b, int* err) { return booleanOp(a, b, err, 0, "union"); }
CCGeomShape* ccgeom_subtract(CCGeomShape* a, CCGeomShape* b, int* err) { return booleanOp(a, b, err, 1, "cut"); }
CCGeomShape* ccgeom_intersect(CCGeomShape* a, CCGeomShape* b, int* err) { return booleanOp(a, b, err, 2, "intersect"); }

static bool isPureBox(CCGeomShape* s) {
  return s->boxLike && s->faces == 6 && s->edges == 12;
}
CCGeomShape* ccgeom_fillet(CCGeomShape* s, double r, const int* idx, int n, int* err) {
  if (!s) { setErr(err, CCGEOM_ERR_INVALID_ARG, "mock fillet: null"); return nullptr; }
  if (idx && n > 0) {
    for (int i = 0; i < n; ++i)
      if (idx[i] < 0 || idx[i] >= s->edges) { setErr(err, CCGEOM_ERR_EDGE_INDEX, "mock fillet: edge index out of range"); return nullptr; }
    setErr(err, CCGEOM_ERR_OCCT, "mock limitation: selective fillet not modelled");
    return nullptr;
  }
  if (!isPureBox(s)) { setErr(err, CCGEOM_ERR_OCCT, "mock limitation: fillet modelled only for a box, all edges"); return nullptr; }
  double w = s->bbox[3] - s->bbox[0], d = s->bbox[4] - s->bbox[1], h = s->bbox[5] - s->bbox[2];
  if (2 * r > std::min({w, d, h})) { setErr(err, CCGEOM_ERR_OCCT, "mock fillet: radius too large"); return nullptr; }
  double iw = w - 2 * r, id = d - 2 * r, ih = h - 2 * r;
  double vol = iw * id * ih + 2 * r * (iw * id + iw * ih + id * ih)
             + M_PI * r * r * (iw + id + ih) + 4.0 / 3.0 * M_PI * r * r * r;
  auto* out = new CCGeomShape(*s);
  out->volume = vol; out->faces = 26; out->edges = 56; out->boxLike = false;
  if (err) *err = CCGEOM_OK;
  return out;
}
CCGeomShape* ccgeom_chamfer(CCGeomShape* s, double c, const int* idx, int n, int* err) {
  if (!s) { setErr(err, CCGEOM_ERR_INVALID_ARG, "mock chamfer: null"); return nullptr; }
  if (idx && n > 0) {
    for (int i = 0; i < n; ++i)
      if (idx[i] < 0 || idx[i] >= s->edges) { setErr(err, CCGEOM_ERR_EDGE_INDEX, "mock chamfer: edge index out of range"); return nullptr; }
    setErr(err, CCGEOM_ERR_OCCT, "mock limitation: selective chamfer not modelled");
    return nullptr;
  }
  if (!isPureBox(s)) { setErr(err, CCGEOM_ERR_OCCT, "mock limitation: chamfer modelled only for a box, all edges"); return nullptr; }
  double w = s->bbox[3] - s->bbox[0], d = s->bbox[4] - s->bbox[1], h = s->bbox[5] - s->bbox[2];
  double sumL = 4 * (w + d + h);
  double vol = w * d * h - 0.5 * c * c * (sumL - 24 * c) - 8 * (5.0 / 6.0) * c * c * c;
  auto* out = new CCGeomShape(*s);
  out->volume = vol; out->faces = 26; out->edges = 48; out->boxLike = false;
  if (err) *err = CCGEOM_OK;
  return out;
}
CCGeomShape* ccgeom_transform(CCGeomShape* s, const double m[12], int* err) {
  if (!s || !m) { setErr(err, CCGEOM_ERR_INVALID_ARG, "mock transform: null"); return nullptr; }
  double det = m[0] * (m[5] * m[10] - m[6] * m[9]) - m[1] * (m[4] * m[10] - m[6] * m[8]) + m[2] * (m[4] * m[9] - m[5] * m[8]);
  auto* out = new CCGeomShape(*s);
  out->volume = s->volume * std::fabs(det);
  out->area = s->area;  // exact only for rigid motion; harness asserts volume+bbox
  double bb[6] = {1e300, 1e300, 1e300, -1e300, -1e300, -1e300};
  for (int i = 0; i < 8; ++i) {
    double x = (i & 1) ? s->bbox[3] : s->bbox[0];
    double y = (i & 2) ? s->bbox[4] : s->bbox[1];
    double z = (i & 4) ? s->bbox[5] : s->bbox[2];
    double px = m[0] * x + m[1] * y + m[2] * z + m[3];
    double py = m[4] * x + m[5] * y + m[6] * z + m[7];
    double pz = m[8] * x + m[9] * y + m[10] * z + m[11];
    bb[0] = std::min(bb[0], px); bb[3] = std::max(bb[3], px);
    bb[1] = std::min(bb[1], py); bb[4] = std::max(bb[4], py);
    bb[2] = std::min(bb[2], pz); bb[5] = std::max(bb[5], pz);
  }
  std::memcpy(out->bbox, bb, sizeof(bb));
  out->boxLike = s->boxLike && std::fabs(det - 1.0) < 1e-12;
  if (err) *err = CCGEOM_OK;
  return out;
}
double ccgeom_volume(CCGeomShape* s, int* err) { if (err) *err = s ? CCGEOM_OK : CCGEOM_ERR_INVALID_ARG; return s ? s->volume : 0; }
double ccgeom_area(CCGeomShape* s, int* err) { if (err) *err = s ? CCGEOM_OK : CCGEOM_ERR_INVALID_ARG; return s ? s->area : 0; }
int ccgeom_bbox(CCGeomShape* s, double out[6], int* err) {
  if (!s || !out) return setErr(err, CCGEOM_ERR_INVALID_ARG, "mock bbox: null");
  std::memcpy(out, s->bbox, sizeof(s->bbox)); if (err) *err = CCGEOM_OK; return CCGEOM_OK;
}
int ccgeom_counts(CCGeomShape* s, int* faces, int* edges, int* err) {
  if (!s) return setErr(err, CCGEOM_ERR_INVALID_ARG, "mock counts: null");
  if (faces) *faces = s->faces;
  if (edges) *edges = s->edges;
  if (err) *err = CCGEOM_OK; return CCGEOM_OK;
}
int ccgeom_tessellate(CCGeomShape* s, double, float** outVertices, int* outVertexCount,
                      int** outIndices, int* outIndexCount, int* err) {
  if (!s) return setErr(err, CCGEOM_ERR_INVALID_ARG, "mock tessellate: null");
  // Bounding-box placeholder (documented in the header comment).
  const double* b = s->bbox;
  float corners[8][3] = {{(float)b[0], (float)b[1], (float)b[2]}, {(float)b[3], (float)b[1], (float)b[2]},
                         {(float)b[3], (float)b[4], (float)b[2]}, {(float)b[0], (float)b[4], (float)b[2]},
                         {(float)b[0], (float)b[1], (float)b[5]}, {(float)b[3], (float)b[1], (float)b[5]},
                         {(float)b[3], (float)b[4], (float)b[5]}, {(float)b[0], (float)b[4], (float)b[5]}};
  static const int tris[12][3] = {{0,1,2},{0,2,3},{4,6,5},{4,7,6},{0,4,5},{0,5,1},
                                  {1,5,6},{1,6,2},{2,6,7},{2,7,3},{3,7,4},{3,4,0}};
  float* v = (float*)std::malloc(36 * 3 * sizeof(float));
  int* ix = (int*)std::malloc(36 * sizeof(int));
  for (int t = 0; t < 12; ++t)
    for (int k = 0; k < 3; ++k) {
      int vi = t * 3 + k;
      std::memcpy(&v[vi * 3], corners[tris[t][k]], 3 * sizeof(float));
      ix[vi] = vi;
    }
  *outVertices = v; *outIndices = ix;
  if (outVertexCount) *outVertexCount = 36;
  if (outIndexCount) *outIndexCount = 36;
  if (err) *err = CCGEOM_OK; return CCGEOM_OK;
}
int ccgeom_export_step(CCGeomShape* s, const char* path, int* err) {
  if (!s || !path) return setErr(err, CCGEOM_ERR_INVALID_ARG, "mock export-step: null");
  // The mock writes a clearly-marked placeholder file so export plumbing
  // (paths, result strings) is testable; it is NOT a STEP file.
  FILE* f = std::fopen(path, "w");
  if (!f) return setErr(err, CCGEOM_ERR_OCCT, "mock export-step: cannot open path");
  std::fprintf(f, "MOCK EXPORT (not a STEP file) volume=%f\n", s->volume);
  std::fclose(f);
  if (err) *err = CCGEOM_OK; return CCGEOM_OK;
}
int ccgeom_export_stl(CCGeomShape* s, const char* path, int* err) {
  if (!s || !path) return setErr(err, CCGEOM_ERR_INVALID_ARG, "mock export-stl: null");
  float* v = nullptr; int* ix = nullptr; int vc = 0, ic = 0, e = CCGEOM_OK;
  if (ccgeom_tessellate(s, 0.5, &v, &vc, &ix, &ic, &e) != CCGEOM_OK) return setErr(err, e, "mock export-stl: tessellate failed");
  FILE* f = std::fopen(path, "w");
  if (!f) { ccgeom_free_buffer(v); ccgeom_free_buffer(ix); return setErr(err, CCGEOM_ERR_OCCT, "mock export-stl: cannot open path"); }
  std::fprintf(f, "solid mock\nendsolid mock\n");
  std::fclose(f);
  ccgeom_free_buffer(v); ccgeom_free_buffer(ix);
  if (err) *err = CCGEOM_OK; return CCGEOM_OK;
}

void* ccgeom_native_handle(CCGeomShape*) { return nullptr; }  // mock has no native handle

int ccgeom_face_ranges(CCGeomShape* s, double,
                       CCGeomFaceRange** outRanges, int* outCount, int* err) {
  if (!s) return setErr(err, CCGEOM_ERR_INVALID_ARG, "mock face_ranges: null");
  // The mock tessellation is a bounding-box placeholder with 12
  // triangles in fixed order: 2 per box face (z-min, z-max, y-min,
  // x-max, y-max, x-min). For a 6-face shape the ranges below are the
  // honest slices of THAT placeholder; for anything else the mock
  // cannot attribute triangles to faces and returns one range.
  std::vector<CCGeomFaceRange> ranges;
  if (s->faces == 6) {
    for (int f = 0; f < 6; ++f) ranges.push_back(CCGeomFaceRange{f, f * 6, 6});
  } else {
    ranges.push_back(CCGeomFaceRange{0, 0, 36});
  }
  CCGeomFaceRange* buf = (CCGeomFaceRange*)std::malloc(ranges.size() * sizeof(CCGeomFaceRange));
  if (!buf) return setErr(err, CCGEOM_ERR_OCCT, "mock face_ranges: out of memory");
  std::memcpy(buf, ranges.data(), ranges.size() * sizeof(CCGeomFaceRange));
  *outRanges = buf; *outCount = (int)ranges.size();
  if (err) *err = CCGEOM_OK; return CCGEOM_OK;
}
