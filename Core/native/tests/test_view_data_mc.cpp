// ============================================================================
// test_view_data_mc.cpp — view-data smoke for the DEVICE code path.
//
// Links the interpreter against the REAL mc backend (ccgeom_mc.cpp over
// the cascade-port mc_* facade / CascadeKit) — the exact objects the
// iPad app links — and drives the public C API the Swift layer uses:
//   cc_session_create -> cc_execute("box b 10 10 10") -> cc_view_data.
//
// v0.2 shipped with this path never run end-to-end: ccgeom_mc read
// mesh.vertexCount / triangleCount / faceCount AFTER mc_free_mesh(),
// which memsets the MCFacadeMesh struct to zero, so every object came
// back with 0 vertices / 0 triangles / 0 face ranges and the viewer
// rendered nothing ("0 object(s)") while the session held the object.
// The assertions below are exactly the invariants whose violation made
// that failure silent: counts > 0, indices in range, face ranges
// census-ordered and partitioning the index buffer, sane bbox/volume.
//
// Usage: test_view_data_mc [tmpdir]
// Exit status 0 iff every check passes.
// ============================================================================
#include "cc_facade.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

static int g_pass = 0, g_fail = 0;
static void check(bool ok, const std::string& what) {
  if (ok) { ++g_pass; std::printf("  [PASS] %s\n", what.c_str()); }
  else { ++g_fail; std::printf("  [FAIL] %s\n", what.c_str()); }
}
static bool near(double a, double b, double tol) { return std::fabs(a - b) <= tol; }

// Signed volume of a closed triangle mesh: positive iff the winding
// is outward (right-handed convention). A negative value means the
// tessellation is inside-out — the v0.2.2 regression invariant.
static double signedVolume(const CCViewData& d) {
  double v = 0;
  for (int t = 0; t < d.triangleCount; ++t) {
    const float* a = &d.vertices[d.indices[t * 3] * 3];
    const float* b = &d.vertices[d.indices[t * 3 + 1] * 3];
    const float* c = &d.vertices[d.indices[t * 3 + 2] * 3];
    double cx = b[1] * c[2] - b[2] * c[1];
    double cy = b[2] * c[0] - b[0] * c[2];
    double cz = b[0] * c[1] - b[1] * c[0];
    v += (a[0] * cx + a[1] * cy + a[2] * cz) / 6.0;
  }
  return v;
}

int main(int argc, char** argv) {
  (void)argc; (void)argv;
  std::printf("Cascade Console view-data smoke (mc backend / CascadeKit)\n");

  CCSession* s = cc_session_create();
  check(s != nullptr, "cc_session_create");
  if (!s) { std::printf("RESULT: %d pass, %d fail\n", g_pass, g_fail); return 1; }

  char* out = nullptr;
  int rc = cc_execute(s, "box b 10 10 10", &out);
  check(rc == 0, "cc_execute box b 10 10 10 -> rc 0");
  cc_free_string(out); out = nullptr;
  check(cc_object_count(s) == 1, "session holds exactly 1 object");
  check(std::string(cc_object_name(s, 0)) == "b", "object 0 is named 'b'");

  // ---- all-objects view data (the call the app makes after commands)
  CCViewData* objs = nullptr; int n = 0;
  rc = cc_view_data(s, nullptr, 0.5, &objs, &n);
  check(rc == 0, "cc_view_data(all) -> rc 0");
  check(n == 1, "cc_view_data(all) returns 1 object");
  if (rc == 0 && n == 1) {
    const CCViewData& d = objs[0];
    check(std::string(d.name) == "b", "view object name == 'b'");
    // THE v0.2 regression assertions: these were all 0 in the shipped
    // build because the counts were read after mc_free_mesh().
    check(d.vertexCount > 0, "vertexCount > 0 (was 0 in v0.2)");
    check(d.triangleCount > 0, "triangleCount > 0 (was 0 in v0.2)");
    check(d.faceRangeCount == 6, "faceRangeCount == 6 for a box (was 0 in v0.2)");
    check(near(d.volume, 1000.0, 1e-6), "volume == 1000 mm^3");
    check(near(d.bbox[0], 0, 1e-6) && near(d.bbox[1], 0, 1e-6) && near(d.bbox[2], 0, 1e-6) &&
          near(d.bbox[3], 10, 1e-6) && near(d.bbox[4], 10, 1e-6) && near(d.bbox[5], 10, 1e-6),
          "bbox == (0,0,0)..(10,10,10)");

    // Indices must reference real vertices (the Swift adapter unwelds
    // per index corner and would read out of bounds otherwise).
    bool idxOk = d.vertexCount > 0 && d.triangleCount > 0;
    for (int i = 0; i < d.triangleCount * 3 && idxOk; ++i)
      if (d.indices[i] < 0 || d.indices[i] >= d.vertexCount) idxOk = false;
    check(idxOk, "every index < vertexCount");

    // Vertices must be finite and inside the bbox.
    bool vertsOk = idxOk;
    for (int i = 0; i < d.vertexCount * 3 && vertsOk; ++i)
      if (!std::isfinite(d.vertices[i])) vertsOk = false;
    check(vertsOk, "every vertex coordinate is finite");

    // Face ranges: census order, contiguous, partition the index
    // buffer — the invariant the face-label chips rely on.
    bool rangesOk = d.faceRangeCount == 6;
    int cursor = 0;
    for (int f = 0; f < d.faceRangeCount; ++f) {
      if (d.faceRanges[f].faceIndex != f) rangesOk = false;
      if (d.faceRanges[f].indexStart != cursor) rangesOk = false;
      if (d.faceRanges[f].indexCount <= 0) rangesOk = false;
      if (d.faceRanges[f].indexCount % 3 != 0) rangesOk = false;
      cursor += d.faceRanges[f].indexCount;
    }
    if (cursor != d.triangleCount * 3) rangesOk = false;
    check(rangesOk, "face ranges are census-ordered and partition the index buffer");

    // Each range's centroid must be a true box face centre (the label
    // anchor), matching the census the @face commands accept.
    const double centres[6][3] = {{5,5,0},{5,5,10},{5,0,5},{10,5,5},{5,10,5},{0,5,5}};
    bool centroidsOk = d.faceRangeCount == 6;
    for (int f = 0; f < d.faceRangeCount && centroidsOk; ++f) {
      double cx = 0, cy = 0, cz = 0; int cnt = 0;
      for (int k = d.faceRanges[f].indexStart;
           k < d.faceRanges[f].indexStart + d.faceRanges[f].indexCount; ++k) {
        int vi = d.indices[k];
        cx += d.vertices[vi * 3]; cy += d.vertices[vi * 3 + 1]; cz += d.vertices[vi * 3 + 2];
        ++cnt;
      }
      if (!cnt) { centroidsOk = false; break; }
      cx /= cnt; cy /= cnt; cz /= cnt;
      bool matched = false;
      for (auto& c : centres)
        if (near(cx, c[0], 0.6) && near(cy, c[1], 0.6) && near(cz, c[2], 0.6)) matched = true;
      if (!matched) centroidsOk = false;
    }
    check(centroidsOk, "every face-range centroid is a real box face centre");
  }
  cc_free_view_data(objs, n);

  // ---- named view data (cc_view_data with a name)
  objs = nullptr; n = 0;
  rc = cc_view_data(s, "b", 0.5, &objs, &n);
  check(rc == 0 && n == 1 && objs && objs[0].triangleCount > 0,
        "cc_view_data('b') returns triangles");
  cc_free_view_data(objs, n);

  // ---- unknown name must be an honest error, not empty success
  objs = nullptr; n = 0;
  rc = cc_view_data(s, "nope", 0.5, &objs, &n);
  check(rc == 1005, "cc_view_data('nope') -> E1005");
  cc_free_view_data(objs, n);

  // ---- ORIENTATION invariants (v0.2.2) -------------------------------
  // The device verdict on v0.2.1 was "geometry is inverted": the true
  // cause was the Swift camera's left-handed perspective matrix, NOT
  // this data — but the ship gate now pins the data side forever:
  // signed mesh volume must be positive and match the analytic volume
  // on every backend, box face-range normals must point outward, and
  // an asymmetric shape must not come back mirrored.
  std::printf("== orientation invariants ==\n");
  {
    // Box: signed volume + per-face outward normals.
    CCViewData* o = nullptr; int m = 0;
    rc = cc_view_data(s, "b", 0.5, &o, &m);
    check(rc == 0 && m == 1, "orientation: box view data present");
    if (rc == 0 && m == 1) {
      const CCViewData& d = o[0];
      double sv = signedVolume(d);
      check(sv > 0 && near(sv, 1000.0, 1e-3),
            "orientation: box signed mesh volume == +1000 (outward winding)");
      bool outward = d.faceRangeCount == 6;
      for (int f = 0; f < d.faceRangeCount && outward; ++f) {
        double nx = 0, ny = 0, nz = 0, cx = 0, cy = 0, cz = 0; int cnt = 0;
        for (int k = d.faceRanges[f].indexStart;
             k < d.faceRanges[f].indexStart + d.faceRanges[f].indexCount; ++k) {
          const float* p = &d.vertices[d.indices[k] * 3];
          cx += p[0]; cy += p[1]; cz += p[2]; ++cnt;
          if ((k - d.faceRanges[f].indexStart) % 3 == 0 &&
              k + 2 < d.faceRanges[f].indexStart + d.faceRanges[f].indexCount) {
            const float* a = p;
            const float* b = &d.vertices[d.indices[k + 1] * 3];
            const float* c = &d.vertices[d.indices[k + 2] * 3];
            double ux = b[0]-a[0], uy = b[1]-a[1], uz = b[2]-a[2];
            double vx = c[0]-a[0], vy = c[1]-a[1], vz = c[2]-a[2];
            nx += uy*vz - uz*vy; ny += uz*vx - ux*vz; nz += ux*vy - uy*vx;
          }
        }
        if (!cnt) { outward = false; break; }
        cx /= cnt; cy /= cnt; cz /= cnt;
        // Box centre is (5,5,5); outward means normal . (centroid-centre) > 0.
        if (nx * (cx - 5) + ny * (cy - 5) + nz * (cz - 5) <= 0) outward = false;
      }
      check(outward, "orientation: all 6 box face-range normals point outward");
    }
    cc_free_view_data(o, m);
  }
  {
    // Cylinder + asymmetric L prism, created in this same session.
    char* o2 = nullptr;
    cc_execute(s, "cylinder cyl 5 20", &o2); cc_free_string(o2); o2 = nullptr;
    cc_execute(s, "profile L 0,0 30,0 30,10 10,10 10,30 0,30", &o2); cc_free_string(o2); o2 = nullptr;
    cc_execute(s, "extrude Lprof L 12", &o2); cc_free_string(o2); o2 = nullptr;

    CCViewData* o = nullptr; int m = 0;
    rc = cc_view_data(s, "cyl", 0.5, &o, &m);
    check(rc == 0 && m == 1, "orientation: cylinder view data present");
    if (rc == 0 && m == 1) {
      double sv = signedVolume(o[0]);
      // Faceted cylinder under-reads the analytic volume (~1%); the
      // invariant is the SIGN and the magnitude band, not exactness.
      check(sv > 0 && sv > 0.95 * o[0].volume && sv < 1.001 * o[0].volume,
            "orientation: cylinder signed mesh volume > 0, ~analytic");
    }
    cc_free_view_data(o, m);

    o = nullptr; m = 0;
    rc = cc_view_data(s, "Lprof", 0.5, &o, &m);
    check(rc == 0 && m == 1, "orientation: L prism view data present");
    if (rc == 0 && m == 1) {
      const CCViewData& d = o[0];
      double sv = signedVolume(d);
      check(sv > 0 && near(sv, 6000.0, 1e-3),
            "orientation: L prism signed mesh volume == +6000");
      // Mirror check: the L's notch inner corner is at (10,10); a
      // mirrored mesh would put it at (20,10) instead.
      int near1010 = 0, near2010 = 0;
      for (int vi = 0; vi < d.vertexCount; ++vi) {
        double x = d.vertices[vi * 3], y = d.vertices[vi * 3 + 1];
        if (std::fabs(x - 10) < 0.6 && std::fabs(y - 10) < 0.6) ++near1010;
        if (std::fabs(x - 20) < 0.6 && std::fabs(y - 10) < 0.6) ++near2010;
      }
      check(near1010 > 0 && near2010 == 0,
            "orientation: L prism notch at (10,10), not mirrored to (20,10)");
    }
    cc_free_view_data(o, m);
  }

  cc_session_destroy(s);
  std::printf("RESULT: %d pass, %d fail (mc view-data smoke)\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
