// ============================================================================
// test_matrix_mc.cpp — PER-COMMAND test matrix on the DEVICE code path.
//
// The user's ship gate for v0.2.1 (2026-11-23): "a test on each command
// before you give me the next version". This binary links the
// interpreter against the REAL mc backend (ccgeom_mc.cpp +
// ccsim_backend_mc.cpp over the CI-patched cascade-port mc_* facade /
// CascadeKit) — the exact objects the iPad app links — and drives
// every command NativeEngine advertises in knownCommands through
// cc_execute, asserting a real invariant per command (analytic
// volumes, session state, file contents, error codes), never just
// rc == 0. The same command lines and expected values as the host
// suite (tests/test_engine.cpp) are reused wherever the grammar is
// shared, so a failure here means the DEVICE backend diverges from
// the host-proven behaviour — exactly what shipped broken in v0.2
// (view data empty; export-stl untested on this backend).
//
// Usage: test_matrix_mc <tmpdir> [demo.ccs path]
// Exit status 0 iff every check passes. Every check prints its
// command + invariant so the CI log IS the matrix report.
// ============================================================================
#include "cc_facade.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <sys/stat.h>

static int g_pass = 0, g_fail = 0;
static void check(bool ok, const std::string& what) {
  if (ok) { ++g_pass; std::printf("  [PASS] %s\n", what.c_str()); }
  else { ++g_fail; std::printf("  [FAIL] %s\n", what.c_str()); }
}
static bool near(double a, double b, double tol) { return std::fabs(a - b) <= tol; }
static bool fileExists(const std::string& p) { struct stat st; return ::stat(p.c_str(), &st) == 0; }
static long fileSize(const std::string& p) { struct stat st; return ::stat(p.c_str(), &st) == 0 ? (long)st.st_size : -1; }
static std::string fileContents(const std::string& p) {
  std::ifstream f(p, std::ios::binary);
  return std::string((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

struct Session {
  CCSession* s = cc_session_create();
  ~Session() { cc_session_destroy(s); }
  int run(const std::string& line, std::string& out) {
    char* r = nullptr;
    int rc = cc_execute(s, line.c_str(), &r);
    out = r ? r : "";
    cc_free_string(r);
    return rc;
  }
  int run(const std::string& line) { std::string o; return run(line, o); }
  int code(const std::string& line) { return run(line); }
  double volume(const std::string& name) {
    std::string o;
    if (run("volume " + name, o) != 0) return -1e300;
    auto eq = o.find("= ");
    return std::stod(o.substr(eq + 2));
  }
};

static const double PI = 3.14159265358979323846;
static std::string g_tmp;
static std::string T(const std::string& name) { return g_tmp + "/" + name; }

int main(int argc, char** argv) {
  g_tmp = argc > 1 ? argv[1] : "/tmp/cc_matrix_mc";
  const char* demoPath = argc > 2 ? argv[2] : nullptr;
  std::printf("Cascade Console per-command matrix (mc backend / CascadeKit)\n");
  std::printf("tmpdir: %s\n", g_tmp.c_str());

  // ---- primitives: analytic volumes --------------------------------
  std::printf("== primitives ==\n");
  { Session i;
    check(i.run("box b 10 20 30") == 0, "box: rc 0");
    check(near(i.volume("b"), 6000.0, 1e-6), "box: volume == 6000 (10*20*30)");
    double vol, area, bb[6]; int f, e;
    check(cc_object_stats(i.s, "b", &vol, &area, bb, &f, &e) == 0, "box: cc_object_stats rc 0");
    check(near(bb[0], 0, 1e-9) && near(bb[3], 10, 1e-9) && near(bb[4], 20, 1e-9) && near(bb[5], 30, 1e-9),
          "box: bbox == (0,0,0)..(10,20,30)");
    check(f == 6 && e == 12, "box: faces/edges == 6/12");
    check(near(area, 2200.0, 1e-6), "box: area == 2200");
  }
  { Session i;
    check(i.run("cylinder c 5 10") == 0, "cylinder: rc 0");
    check(near(i.volume("c"), PI * 25 * 10, 1e-3), "cylinder: volume == pi*25*10");
    check(i.run("sphere s 5") == 0, "sphere: rc 0");
    check(near(i.volume("s"), 4.0 / 3 * PI * 125, 1e-3), "sphere: volume == 4/3*pi*125");
    check(i.run("cone k 6 3 9") == 0, "cone: rc 0");
    check(near(i.volume("k"), PI * 9 / 3 * (36 + 18 + 9), 1e-3), "cone: volume == pi*h/3*(R^2+Rr+r^2)");
    check(i.run("torus t 10 3") == 0, "torus: rc 0");
    check(near(i.volume("t"), 2 * PI * PI * 10 * 9, 1e-2), "torus: volume == 2*pi^2*R*r^2");
    check(i.run("box p 10 10 10 at 100,50,-5") == 0, "box at: rc 0");
    double vol, area, bb[6]; int f, e;
    cc_object_stats(i.s, "p", &vol, &area, bb, &f, &e);
    check(near(bb[0], 100, 1e-9) && near(bb[1], 50, 1e-9) && near(bb[2], -5, 1e-9) && near(bb[5], 5, 1e-9),
          "box at: placement 100,50,-5 honoured");
    check(i.run("box 10 20 30 as bb") == 0, "box (catalog 'as' form): rc 0");
    check(near(i.volume("bb"), 6000.0, 1e-4), "box (catalog form): volume == 6000");
  }

  // ---- profile + extrude -------------------------------------------
  std::printf("== profile / extrude ==\n");
  { Session i;
    check(i.run("profile p 0,0 40,0 40,20 0,20") == 0, "profile: rc 0");
    check(i.run("extrude e p 10") == 0, "extrude: rc 0");
    check(near(i.volume("e"), 8000.0, 1e-4), "extrude: volume == 40*20*10 == 8000");
  }

  // ---- booleans: volume invariants on overlapping boxes ------------
  std::printf("== booleans ==\n");
  { Session i;
    i.run("box a 10 20 30");
    i.run("box b 10 20 30 at 5,0,0");
    check(i.run("union u a b") == 0, "union: rc 0");
    check(near(i.volume("u"), 9000.0, 1e-4), "union: volume == 9000 (6000+6000-3000)");
    check(i.run("cut c a b") == 0, "cut: rc 0");
    check(near(i.volume("c"), 3000.0, 1e-4), "cut: volume == 3000");
    check(i.run("intersect x a b") == 0, "intersect: rc 0");
    check(near(i.volume("x"), 3000.0, 1e-4), "intersect: volume == 3000");
    check(near(i.volume("a"), 6000.0, 1e-4) && near(i.volume("b"), 6000.0, 1e-4),
          "booleans: inputs unchanged");
    check(i.run("fuse a b as fu") == 0, "fuse (catalog form): rc 0");
    check(near(i.volume("fu"), 9000.0, 1e-4), "fuse: volume == 9000");
    check(i.run("common a b as cm") == 0, "common (catalog form): rc 0");
    check(near(i.volume("cm"), 3000.0, 1e-4), "common: volume == 3000");
    check(i.run("cut a minus b as ct") == 0, "cut (catalog 'minus' form): rc 0");
    check(near(i.volume("ct"), 3000.0, 1e-4), "cut minus: volume == 3000");
  }

  // ---- fillet / chamfer: volume decreases in the proven band -------
  std::printf("== fillet / chamfer ==\n");
  { Session i;
    i.run("box b 10 20 30");
    check(i.run("fillet f b 1") == 0, "fillet: rc 0");
    double v = i.volume("f");
    check(v < 6000.0 && v > 5900.0, "fillet: volume decreases into (5900, 6000)");
    check(near(v, 5949.8348, 1e-3), "fillet: volume == host-proven 5949.8348");
    check(i.run("chamfer ch b 1") == 0, "chamfer: rc 0");
    v = i.volume("ch");
    check(v < 6000.0 && v > 5000.0, "chamfer: volume decreases into (5000, 6000)");
    check(near(v, 5885.3333, 1e-3), "chamfer: volume == host-proven 5885.3333");
    check(i.code("fillet bad b 1 edges 99") == 2005, "fillet: bad edge index -> E2005");
  }

  // ---- transforms ----------------------------------------------------
  std::printf("== translate / rotate ==\n");
  { Session i;
    i.run("box b 10 20 30");
    check(i.run("translate m b 100 0 0") == 0, "translate: rc 0");
    check(near(i.volume("m"), 6000.0, 1e-4), "translate: volume preserved");
    double vol, area, bb[6]; int f, e;
    cc_object_stats(i.s, "m", &vol, &area, bb, &f, &e);
    check(near(bb[0], 100.0, 1e-4), "translate: bbox xmin moves to 100");
    check(i.run("rotate r b 0 0 1 90") == 0, "rotate: rc 0");
    cc_object_stats(i.s, "r", &vol, &area, bb, &f, &e);
    check(near(bb[3] - bb[0], 20.0, 1e-3) && near(bb[4] - bb[1], 10.0, 1e-3) && near(bb[5] - bb[2], 30.0, 1e-3),
          "rotate: 90 deg about Z swaps X/Y extents");
    check(i.code("rotate z b 0 0 0 45") == 2001, "rotate: zero axis -> E2001");
  }

  // ---- session-state commands ---------------------------------------
  std::printf("== copy / duplicate / rename / delete / list / info / clear ==\n");
  { Session i;
    i.run("box a 1 1 1");
    check(i.run("copy c a") == 0, "copy: rc 0 (copy <new> <src>)");
    check(near(i.volume("c"), 1.0, 1e-9), "copy: clone has volume 1");
    check(i.run("duplicate a as dup") == 0, "duplicate: rc 0 (duplicate <src> as <new>)");
    check(near(i.volume("dup"), 1.0, 1e-9), "duplicate: clone has volume 1 (mc_clone_shape path)");
    check(i.run("rename d c") == 0, "rename: rc 0 (rename <new> <old>)");
    std::string out;
    check(i.run("info d", out) == 0 && out.find("faces 6") != std::string::npos,
          "info: reports faces 6 for the renamed box");
    check(i.run("rename dup as rn") == 0, "rename (catalog 'as' form): rc 0");
    check(i.run("list", out) == 0 &&
          out.find("object  a:") != std::string::npos &&
          out.find("object  rn:") != std::string::npos,
          "list: names the session objects");
    check(i.run("delete d") == 0, "delete: rc 0");
    check(i.code("info d") == 1005, "delete: info on deleted name -> E1005");
    check(cc_object_count(i.s) == 2, "delete: session count drops to 2 (a, rn)");
    check(i.run("clear") == 0, "clear: rc 0");
    check(cc_object_count(i.s) == 0, "clear: session is empty afterwards");
  }

  // ---- measure -------------------------------------------------------
  std::printf("== volume / measure-volume / info ==\n");
  { Session i;
    i.run("box b 10 20 30");
    std::string out;
    check(i.run("volume b", out) == 0 && out.find("6000") != std::string::npos,
          "volume: output states 6000");
    check(i.run("measure-volume b", out) == 0 && out.find("6000.000000") != std::string::npos,
          "measure-volume: output states 6000.000000");
    check(i.run("info b", out) == 0 && out.find("area 2200") != std::string::npos,
          "info: output states area 2200");
  }

  // ---- variables ------------------------------------------------------
  std::printf("== set / show-vars ==\n");
  { Session i;
    check(i.run("set w = 12") == 0, "set: rc 0");
    check(i.run("box b $w 2*$w $w/2") == 0, "set: variables usable in expressions");
    check(near(i.volume("b"), 12.0 * 24 * 6, 1e-4), "set: expression volume == 1728");
    std::string vars;
    i.run("show-vars", vars);
    check(vars.find("w = 12.0") != std::string::npos, "show-vars: lists 'w = 12.0'");
    check(i.code("box z $nope 1 1") == 1004, "set: undefined variable -> E1004");
  }

  // ---- undo / redo / history ------------------------------------------
  std::printf("== undo / redo / history ==\n");
  { Session i;
    i.run("box a 1 1 1");
    i.run("box b 2 2 2");
    check(i.run("undo") == 0, "undo: rc 0");
    check(i.code("info b") == 1005 && i.run("info a") == 0, "undo: removes b, keeps a");
    check(i.run("redo") == 0, "redo: rc 0");
    check(i.run("info b") == 0, "redo: restores b");
    std::string h;
    check(i.run("history", h) == 0 && h.find("box a 1 1 1") != std::string::npos,
          "history: lists executed command lines");
    check(cc_history_count(i.s) >= 4, "history: cc_history_count tracks lines");
    Session j;
    check(j.code("undo") == 1007, "undo: empty stack -> E1007");
  }

  // ---- echo / help ------------------------------------------------------
  std::printf("== echo / help ==\n");
  { Session i;
    std::string out;
    check(i.run("echo hello cascade", out) == 0 && out == "hello cascade",
          "echo: returns the text verbatim");
    check(i.run("help", out) == 0 && out.find("box") != std::string::npos &&
          out.find("export step|stl") != std::string::npos,
          "help: lists the command grammar");
  }

  // ---- shape-history: E5002 by design -----------------------------------
  std::printf("== shape-history ==\n");
  { Session i;
    i.run("box b 1 1 1");
    check(i.code("shape-history b") == 5002, "shape-history: E5002 NOT_IMPLEMENTED by design");
  }

  // ---- run (script file) --------------------------------------------------
  std::printf("== run ==\n");
  { Session i;
    { std::ofstream f(T("matrix_script.ccs"));
      f << "box a 10 10 10\nbox b 5 5 5 at 100,0,0\nunion u a b\n"; }
    check(i.run("run " + T("matrix_script.ccs")) == 0, "run: rc 0 on a script file");
    check(near(i.volume("u"), 1125.0, 1e-4), "run: script union volume == 1125");
    check(i.code("run " + T("no_such_script.ccs")) == 3001, "run: missing file -> E3001");
  }

  // ---- exports: real files, real contents ---------------------------------
  std::printf("== export-step / export-stl / export ==\n");
  { Session i;
    i.run("box u 10 10 10");
    std::string r;
    check(i.run("export-step u " + T("u.step"), r) == 0, "export-step: rc 0");
    check(fileExists(T("u.step")) && fileSize(T("u.step")) > 0, "export-step: file written, non-empty");
    check(fileContents(T("u.step")).find("ISO-10303-21") != std::string::npos,
          "export-step: file carries the ISO-10303-21 STEP header");
    check(i.run("export-stl u " + T("u.stl"), r) == 0, "export-stl: rc 0 (mc_export_stl)");
    check(fileExists(T("u.stl")) && fileSize(T("u.stl")) > 100, "export-stl: file written, non-trivial size");
    std::string stl = fileContents(T("u.stl"));
    check(stl.rfind("solid", 0) == 0 && stl.find("facet") != std::string::npos,
          "export-stl: ASCII STL with 'solid' header and facet records");
    check(i.run("export stl " + T("one.stl") + " u", r) == 0, "export stl <path> <name>: rc 0");
    check(fileExists(T("one.stl")) && fileSize(T("one.stl")) > 100,
          "export stl <path> <name>: named target written to the path as given");
    check(i.run("export step " + T("one.step") + " u", r) == 0, "export step <path> <name>: rc 0");
    check(fileContents(T("one.step")).find("ISO-10303-21") != std::string::npos,
          "export step <path> <name>: STEP header present");
    // Multi-target form: no name -> one file per object, _<name> inserted.
    i.run("box v 5 5 5 at 50,0,0");
    check(i.run("export stl " + T("multi.stl"), r) == 0, "export stl <path> (all objects): rc 0");
    check(fileExists(T("multi_u.stl")) && fileExists(T("multi_v.stl")),
          "export stl (all): per-target files multi_u.stl + multi_v.stl written");
    check(r.find("multi_u.stl") != std::string::npos && r.find("multi_v.stl") != std::string::npos,
          "export stl (all): result names both written files");
    // Honest failure: an unwritable destination must error, not fake success.
    check(i.run("export-stl u " + T("no_such_dir/x.stl"), r) != 0,
          "export-stl: unwritable path -> error (no fake success)");
    check(std::string(cc_last_error_name(i.s)) == "EXPORT_FAILED",
          "export-stl: unwritable path reports EXPORT_FAILED");
  }

  // ---- view (engine JSON form) + cc_view_data ------------------------------
  std::printf("== view / cc_view_data ==\n");
  { Session i;
    i.run("box a 10 10 10");
    i.run("box b 5 5 5 at 100,0,0");
    i.run("union u a b");
    std::string r;
    check(i.run("view " + T("view.json"), r) == 0, "view: rc 0 writing JSON");
    std::string vdoc = fileContents(T("view.json"));
    check(vdoc.find("cascade-console-view") != std::string::npos, "view: JSON format tag present");
    // The mc tessellation must contain real triangles in the JSON too:
    // find a "triangleCount": N with N > 0.
    bool anyTris = false;
    for (size_t p = vdoc.find("\"triangleCount\": "); p != std::string::npos;
         p = vdoc.find("\"triangleCount\": ", p + 1)) {
      long n = std::strtol(vdoc.c_str() + p + 17, nullptr, 10);
      if (n > 0) anyTris = true;
    }
    check(anyTris, "view: JSON reports triangleCount > 0 (mc tessellation is real)");
    CCViewData* objs = nullptr; int n = 0;
    check(cc_view_data(i.s, nullptr, 0.5, &objs, &n) == 0 && n == 3, "cc_view_data: 3 objects");
    bool allTris = n == 3, idxOk = n == 3;
    for (int k = 0; k < n; ++k) {
      if (objs[k].triangleCount <= 0 || objs[k].vertexCount <= 0) allTris = false;
      for (int t = 0; t < objs[k].triangleCount * 3; ++t)
        if (objs[k].indices[t] < 0 || objs[k].indices[t] >= objs[k].vertexCount) idxOk = false;
    }
    check(allTris, "cc_view_data: every object has vertices and triangles");
    check(idxOk, "cc_view_data: every index < vertexCount (adapter unweld invariant)");
    cc_free_view_data(objs, n);
  }

  // ---- sim subset: cantilever through cc_execute ----------------------------
  std::printf("== sim subset ==\n");
  { Session i;
    check(i.run("box beam 100 10 10") == 0, "sim: beam box created");
    // Discover the root/tip census faces from the view data itself —
    // the same census the face labels show and @face accepts — instead
    // of assuming an enumeration order.
    CCViewData* objs = nullptr; int n = 0;
    check(cc_view_data(i.s, "beam", 0.5, &objs, &n) == 0 && n == 1, "sim: beam view data");
    int rootFace = -1, tipFace = -1;
    if (n == 1) {
      const CCViewData& d = objs[0];
      double bestLo = 1e300, bestHi = -1e300;
      for (int f = 0; f < d.faceRangeCount; ++f) {
        double cx = 0; int cnt = 0;
        for (int k = d.faceRanges[f].indexStart;
             k < d.faceRanges[f].indexStart + d.faceRanges[f].indexCount; ++k) {
          cx += d.vertices[d.indices[k] * 3]; ++cnt;
        }
        if (!cnt) continue;
        cx /= cnt;
        if (cx < bestLo) { bestLo = cx; rootFace = d.faceRanges[f].faceIndex; }
        if (cx > bestHi) { bestHi = cx; tipFace = d.faceRanges[f].faceIndex; }
      }
    }
    cc_free_view_data(objs, n);
    check(rootFace >= 0 && tipFace >= 0 && rootFace != tipFace,
          "sim: root/tip faces identified from census centroids");
    check(i.run("sim material beam steel") == 0, "sim material: rc 0");
    check(i.run("sim select beam") == 0, "sim select: rc 0");
    check(i.run("sim fix beam @face " + std::to_string(rootFace)) == 0, "sim fix: rc 0");
    check(i.run("sim load beam @face " + std::to_string(tipFace) + " force 0 0 -100") == 0,
          "sim load: rc 0");
    std::string out;
    check(i.run("sim run beam", out) == 0, "sim run: rc 0 (cantilever solves on mc backend)");
    double deflCoarse = -1;
    auto mp = out.find("max displacement: ");
    if (mp != std::string::npos) deflCoarse = std::strtod(out.c_str() + mp + 18, nullptr);
    std::printf("  [data] sim coarse max displacement: %.6f mm (EB 0.2000)\n", deflCoarse);
    check(deflCoarse > 0.190 && deflCoarse < 0.210,
          "sim run: max displacement within 5% of Euler-Bernoulli 0.2000 mm");
    check(i.run("sim mesh size 1.25") == 0, "sim mesh size: rc 0");
    check(i.run("sim run beam", out) == 0, "sim run (fine mesh): rc 0");
    double deflFine = -1;
    mp = out.find("max displacement: ");
    if (mp != std::string::npos) deflFine = std::strtod(out.c_str() + mp + 18, nullptr);
    std::printf("  [data] sim fine   max displacement: %.6f mm (EB 0.2000)\n", deflFine);
    check(deflFine > 0.190 && deflFine < 0.210 && deflFine > deflCoarse,
          "sim run (fine): deflection refines toward theory");
    check(i.code("sim modal") == 5002, "sim modal: E5002 NOT_IMPLEMENTED (honest)");
  }

  // ---- demo script (full pipeline) ------------------------------------------
  if (demoPath) {
    std::printf("== demo script ==\n");
    Session i;
    char* out = nullptr;
    int rc = cc_execute_script(i.s, demoPath, &out);
    cc_free_string(out);
    check(rc == 0, "demo.ccs: runs clean through cc_execute_script");
    if (rc == 0)
      check(near(i.volume("part3"), 30937.339, 0.01),
            "demo.ccs: part3 volume == host-proven 30937.339");
  }

  std::printf("RESULT: %d pass, %d fail (mc per-command matrix)\n", g_pass, g_fail);
  return g_fail == 0 ? 0 : 1;
}
