// ============================================================================
// ccgeom_mc.cpp — Layer-1 backend: adapter over the cascade-port mc_*
// façade (CascadeKit, OCCT 8.0.1). THIS is the device build's backend:
// every call forwards to an existing mc_* function; the only new Layer-1
// functions required are the two in mc_additions.h (mc_clone_shape,
// mc_export_stl). Conventions match the façade: mm, inputs never
// consumed, caller owns handles (here: this adapter owns them and frees
// with mc_free_shape when the interpreter releases a shape).
//
// mc_* error translation: MC_ERR_INVALID_ARG -> CCGEOM_ERR_INVALID_ARG,
// MC_ERR_EMPTY_RESULT -> CCGEOM_ERR_EMPTY, anything else -> CCGEOM_ERR_OCCT.
// Edge-index range is validated here against mc_edge_count BEFORE calling
// mc_fillet/mc_chamfer, so a bad index surfaces as CCGEOM_ERR_EDGE_INDEX
// (the interpreter's E2005) instead of the façade's generic invalid-arg —
// the same distinction the Python prototype makes.
// ============================================================================
#include "ccgeom.h"
#include "occt_facade.h"
#include "mc_additions.h"

#include <cstdlib>
#include <cstring>
#include <string>

struct CCGeomShape {
  MCFacadeShape* h;
};

static thread_local std::string g_lastError;
const char* ccgeom_last_error(void) {
  const char* m = mc_last_error();
  if (m && *m) return m;
  return g_lastError.c_str();
}
static int xlate(int mcErr) {
  switch (mcErr) {
    case MC_OK: return CCGEOM_OK;
    case MC_ERR_INVALID_ARG: return CCGEOM_ERR_INVALID_ARG;
    case MC_ERR_EMPTY_RESULT: return CCGEOM_ERR_EMPTY;
    default: return CCGEOM_ERR_OCCT;
  }
}
static CCGeomShape* wrapH(MCFacadeShape* h, int* err) {
  if (!h) { if (err) *err = xlate(*err == MC_OK ? MC_ERR_OCCT : *err); return nullptr; }
  if (err) *err = CCGEOM_OK;
  return new CCGeomShape{h};
}
static MCFacadeShape* raw(CCGeomShape* s) { return s ? s->h : nullptr; }

CCGeomShape* ccgeom_clone(CCGeomShape* s) {
  if (!s) return nullptr;
  int e = MC_OK;
  MCFacadeShape* h = mc_clone_shape(s->h, &e);
  return h ? new CCGeomShape{h} : nullptr;
}
void ccgeom_free(CCGeomShape* s) {
  if (!s) return;
  mc_free_shape(s->h);
  delete s;
}
void ccgeom_free_buffer(void* p) { std::free(p); }

CCGeomShape* ccgeom_box(double w, double d, double h, int* err) {
  int e = MC_OK; auto r = mc_box(w, d, h, &e); if (err) *err = xlate(e); return wrapH(r, err);
}
CCGeomShape* ccgeom_cylinder(double r, double h, int* err) {
  int e = MC_OK; auto x = mc_cylinder(r, h, &e); if (err) *err = xlate(e); return wrapH(x, err);
}
CCGeomShape* ccgeom_sphere(double r, int* err) {
  int e = MC_OK; auto x = mc_sphere(r, &e); if (err) *err = xlate(e); return wrapH(x, err);
}
CCGeomShape* ccgeom_cone(double r1, double r2, double h, int* err) {
  int e = MC_OK; auto x = mc_cone(r1, r2, h, &e); if (err) *err = xlate(e); return wrapH(x, err);
}
CCGeomShape* ccgeom_torus(double ringR, double tubeR, int* err) {
  int e = MC_OK; auto x = mc_torus(ringR, tubeR, &e); if (err) *err = xlate(e); return wrapH(x, err);
}
CCGeomShape* ccgeom_prism(const double* xy, int n, double dist, int* err) {
  // Profile in the XY plane at the origin, extruded along +Z: the
  // façade's mc_prism plane parameters for that placement.
  static const double origin[3] = {0, 0, 0};
  static const double xAxis[3] = {1, 0, 0};
  static const double yAxis[3] = {0, 1, 0};
  static const double dir[3] = {0, 0, 1};
  int e = MC_OK; auto x = mc_prism(xy, n, origin, xAxis, yAxis, dir, dist, &e);
  if (err) *err = xlate(e); return wrapH(x, err);
}
CCGeomShape* ccgeom_unite(CCGeomShape* a, CCGeomShape* b, int* err) {
  int e = MC_OK; auto x = mc_unite(raw(a), raw(b), &e); if (err) *err = xlate(e); return wrapH(x, err);
}
CCGeomShape* ccgeom_subtract(CCGeomShape* a, CCGeomShape* b, int* err) {
  int e = MC_OK; auto x = mc_subtract(raw(a), raw(b), &e); if (err) *err = xlate(e); return wrapH(x, err);
}
CCGeomShape* ccgeom_intersect(CCGeomShape* a, CCGeomShape* b, int* err) {
  int e = MC_OK; auto x = mc_intersect(raw(a), raw(b), &e); if (err) *err = xlate(e); return wrapH(x, err);
}
static bool badIndex(CCGeomShape* s, const int* idx, int n, int* err) {
  if (!idx || n <= 0) return false;
  int e = MC_OK;
  int count = mc_edge_count(raw(s), &e);
  if (e != MC_OK) { if (err) *err = xlate(e); return true; }
  for (int i = 0; i < n; ++i)
    if (idx[i] < 0 || idx[i] >= count) { if (err) *err = CCGEOM_ERR_EDGE_INDEX; return true; }
  return false;
}
CCGeomShape* ccgeom_fillet(CCGeomShape* s, double radius, const int* idx, int n, int* err) {
  if (badIndex(s, idx, n, err)) return nullptr;
  int e = MC_OK; auto x = mc_fillet(raw(s), radius, idx, n, &e); if (err) *err = xlate(e); return wrapH(x, err);
}
CCGeomShape* ccgeom_chamfer(CCGeomShape* s, double dist, const int* idx, int n, int* err) {
  if (badIndex(s, idx, n, err)) return nullptr;
  int e = MC_OK; auto x = mc_chamfer(raw(s), dist, idx, n, &e); if (err) *err = xlate(e); return wrapH(x, err);
}
CCGeomShape* ccgeom_transform(CCGeomShape* s, const double m[12], int* err) {
  int e = MC_OK; auto x = mc_transform(raw(s), m, &e); if (err) *err = xlate(e); return wrapH(x, err);
}
double ccgeom_volume(CCGeomShape* s, int* err) {
  int e = MC_OK; double v = mc_volume(raw(s), &e); if (err) *err = xlate(e); return v;
}
double ccgeom_area(CCGeomShape* s, int* err) {
  int e = MC_OK; double v = mc_face_area(raw(s), &e); if (err) *err = xlate(e); return v;
}
int ccgeom_bbox(CCGeomShape* s, double out[6], int* err) {
  int e = MC_OK; int rc = mc_bbox(raw(s), out, &e); if (err) *err = xlate(e); return xlate(e) == CCGEOM_OK ? rc : xlate(e);
}
int ccgeom_counts(CCGeomShape* s, int* faces, int* edges, int* err) {
  int e = MC_OK; int verts = 0;
  int rc = mc_shape_counts(raw(s), faces, edges, &verts, &e);
  if (err) *err = xlate(e); return xlate(e) == CCGEOM_OK ? rc : xlate(e);
}
int ccgeom_tessellate(CCGeomShape* s, double deflectionMM,
                      float** outVertices, int* outVertexCount,
                      int** outIndices, int* outIndexCount, int* err) {
  MCFacadeMesh mesh{};
  int e = MC_OK;
  int rc = mc_tessellate(raw(s), deflectionMM, &mesh, &e);
  if (e != MC_OK || rc != MC_OK) { if (err) *err = xlate(e); return xlate(e); }
  // The façade mesh carries normals + per-face ranges the ccgeom layout
  // does not need; copy positions/indices into ccgeom-owned buffers.
  // COUNTS FIRST: mc_free_mesh() zeroes the whole MCFacadeMesh struct
  // (it memsets it after freeing the arrays), so vertexCount /
  // triangleCount must be captured BEFORE the free. Reading them after
  // it — the v0.2 bug — returned 0/0 for every shape, so cc_view_data
  // handed the apps an empty tessellation and the viewer rendered
  // nothing ("0 object(s)") even though the session held the object.
  const int vc = mesh.vertexCount;
  const int tc = mesh.triangleCount;
  float* v = (float*)std::malloc((vc > 0 ? vc * 3 : 1) * sizeof(float));
  int* ix = (int*)std::malloc((tc > 0 ? tc * 3 : 1) * sizeof(int));
  if (!v || !ix) { std::free(v); std::free(ix); mc_free_mesh(&mesh); if (err) *err = CCGEOM_ERR_OCCT; return CCGEOM_ERR_OCCT; }
  std::memcpy(v, mesh.positions, (size_t)vc * 3 * sizeof(float));
  std::memcpy(ix, mesh.indices, (size_t)tc * 3 * sizeof(int));
  mc_free_mesh(&mesh);
  *outVertices = v; *outIndices = ix;
  if (outVertexCount) *outVertexCount = vc;
  if (outIndexCount) *outIndexCount = tc * 3;
  if (err) *err = CCGEOM_OK;
  return CCGEOM_OK;
}
int ccgeom_export_step(CCGeomShape* s, const char* path, int* err) {
  int e = MC_OK; int rc = mc_export_step(raw(s), path, &e); if (err) *err = xlate(e); return xlate(e) == CCGEOM_OK ? rc : xlate(e);
}
int ccgeom_export_stl(CCGeomShape* s, const char* path, int* err) {
  int e = MC_OK; int rc = mc_export_stl(raw(s), path, &e); if (err) *err = xlate(e); return xlate(e) == CCGEOM_OK ? rc : xlate(e);
}

void* ccgeom_native_handle(CCGeomShape* s) { return s ? (void*)s->h : nullptr; }

int ccgeom_face_ranges(CCGeomShape* s, double deflectionMM,
                       CCGeomFaceRange** outRanges, int* outCount, int* err) {
  // The facade mesh's per-face triangle ranges are in the same TopExp
  // traversal order as the census (facade header, section 9), so
  // range f IS census face f. Converted to index-element units.
  MCFacadeMesh mesh{};
  int e = MC_OK;
  int rc = mc_tessellate(raw(s), deflectionMM, &mesh, &e);
  if (e != MC_OK || rc != MC_OK) { if (err) *err = xlate(e); return xlate(e); }
  // Same capture-before-free rule as ccgeom_tessellate above:
  // mc_free_mesh() memsets the struct, so faceCount is read first.
  const int fc = mesh.faceCount;
  CCGeomFaceRange* buf = (CCGeomFaceRange*)std::malloc((fc > 0 ? fc : 1) * sizeof(CCGeomFaceRange));
  if (!buf) { mc_free_mesh(&mesh); if (err) *err = CCGEOM_ERR_OCCT; return CCGEOM_ERR_OCCT; }
  for (int f = 0; f < fc; ++f) {
    buf[f].faceIndex = f;
    buf[f].indexStart = mesh.faceTriStart[f] * 3;
    buf[f].indexCount = mesh.faceTriCount[f] * 3;
  }
  mc_free_mesh(&mesh);
  *outRanges = buf; *outCount = fc;
  if (err) *err = CCGEOM_OK;
  return CCGEOM_OK;
}
