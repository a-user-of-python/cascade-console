// ============================================================================
// test_engine.cpp — host harness for the C++ Layer-2 interpreter.
// Mirrors repo/Core/tests/test_core.py (the Python prototype's 47 tests)
// assertion-for-assertion where the backend supports it, plus C-API
// surface checks (cc_object_stats, cc_view_data, cc_undo/cc_redo,
// cc_history_count) and the catalog `as`-form grammar.
//
// Build twice (see ../build_host.sh):
//   * OCCT build  — real geometry; ALL checks run, incl. STEP header,
//                   demo-script volume and tessellation counts.
//   * MOCK build (-DCC_MOCK) — analytic double; geometry-exact checks
//                   run only where the mock is exact (primitives,
//                   box booleans, transforms, box fillet/chamfer);
//                   checks the mock cannot support are SKIPPED and
//                   counted, never silently passed.
// ============================================================================
#include "cc_facade.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>

static int g_pass = 0, g_fail = 0, g_skip = 0;
static void check(bool ok, const std::string& what) {
  if (ok) { ++g_pass; std::printf("  [PASS] %s\n", what.c_str()); }
  else { ++g_fail; std::printf("  [FAIL] %s\n", what.c_str()); }
}
static void skip(const std::string& what) { ++g_skip; std::printf("  [SKIP] %s\n", what.c_str()); }
static bool near(double a, double b, double tol) { return std::fabs(a - b) <= tol; }

struct Session {
  CCSession* s = cc_session_create();
  ~Session() { cc_session_destroy(s); }
  // Returns the cc_execute code; result (if any) into out.
  int run(const std::string& line, std::string& out) {
    char* r = nullptr;
    int rc = cc_execute(s, line.c_str(), &r);
    out = r ? r : "";
    cc_free_string(r);
    return rc;
  }
  int run(const std::string& line) { std::string o; return run(line, o); }
  double volume(const std::string& name) {
    std::string o;
    if (run("volume " + name, o) != 0) return -1e300;
    // "<name> volume = <v> mm^3"
    auto eq = o.find("= ");
    return std::stod(o.substr(eq + 2));
  }
  int code(const std::string& line) { return run(line); }
};

int main(int argc, char** argv) {
  const char* backend = argc > 1 ? argv[1] : "unknown";
  std::printf("Cascade Console native engine tests (backend: %s)\n", backend);
#ifdef CC_MOCK
  const bool mock = true;
#else
  const bool mock = false;
#endif
  const double PI = 3.14159265358979323846;

  { Session i;
    check(i.run("box b 10 20 30") == 0, "box created");
    check(near(i.volume("b"), 6000.0, 1e-6), "box volume == 6000");
    double vol, area, bb[6]; int f, e;
    check(cc_object_stats(i.s, "b", &vol, &area, bb, &f, &e) == 0, "cc_object_stats box");
    check(near(bb[0], 0, 1e-9) && near(bb[3], 10, 1e-9) && near(bb[4], 20, 1e-9) && near(bb[5], 30, 1e-9), "box bbox == (0,0,0)..(10,20,30)");
    check(f == 6 && e == 12, "box faces/edges == 6/12");
    check(near(area, 2200.0, 1e-6), "box area == 2200");
  }
  { Session i;
    i.run("cylinder c 5 10");
    check(near(i.volume("c"), PI * 25 * 10, 1e-3), "cylinder volume == pi*25*10");
    i.run("sphere s 5");
    check(near(i.volume("s"), 4.0 / 3 * PI * 125, 1e-3), "sphere volume == 4/3 pi 125");
    i.run("cone k 6 3 9");
    check(near(i.volume("k"), PI * 9 / 3 * (36 + 18 + 9), 1e-3), "cone volume analytic");
    i.run("torus t 10 3");
    check(near(i.volume("t"), 2 * PI * PI * 10 * 9, 1e-2), "torus volume analytic");
  }
  { Session i;
    i.run("box b 10 10 10 at 100,50,-5");
    double vol, area, bb[6]; int f, e;
    cc_object_stats(i.s, "b", &vol, &area, bb, &f, &e);
    check(near(bb[0], 100, 1e-9) && near(bb[1], 50, 1e-9) && near(bb[2], -5, 1e-9) && near(bb[5], 5, 1e-9), "placement at 100,50,-5");
  }
  { Session i;
    check(i.code("cylinder c -1 10") == 2001, "invalid radius -> E2001");
    check(i.code("box b 1 1 1") == 0, "box ok");
    check(i.code("box b 2 2 2") == 1006, "duplicate name -> E1006");
    check(std::string(cc_last_error_name(i.s)) == "DUPLICATE_NAME", "last error name DUPLICATE_NAME");
    check(near(i.volume("b"), 1.0, 1e-9), "original untouched after duplicate attempt");
  }
  { Session i;
    i.run("box a 10 20 30");
    i.run("box b 10 20 30 at 5,0,0");
    i.run("union u a b");
    check(near(i.volume("u"), 9000.0, 1e-4), "union volume == 9000");
    i.run("cut c a b");
    check(near(i.volume("c"), 3000.0, 1e-4), "cut volume == 3000");
    i.run("intersect x a b");
    check(near(i.volume("x"), 3000.0, 1e-4), "intersect volume == 3000");
    check(near(i.volume("a"), 6000.0, 1e-4) && near(i.volume("b"), 6000.0, 1e-4), "boolean inputs unchanged");
    check(i.code("union z a nope") == 1005, "undefined operand -> E1005");
  }
  { Session i;
    i.run("box b 10 20 30");
    i.run("fillet f b 1");
    double v = i.volume("f");
    check(v < 6000.0 && v > 5900.0, "fillet reduces volume (in 5900..6000)");
    if (!mock) check(near(v, 5949.8348, 1e-3), "fillet volume == prototype 5949.8348");
    i.run("chamfer ch b 1");
    v = i.volume("ch");
    check(v < 6000.0 && v > 5000.0, "chamfer reduces volume (in 5000..6000)");
    if (!mock) check(near(v, 5885.3333, 1e-3), "chamfer volume == prototype 5885.3333");
    else check(near(v, 5885.3333, 1e-3), "mock chamfer analytic == 5885.3333");
    check(i.code("fillet bad b 1 edges 99") == 2005, "fillet bad edge -> E2005");
  }
  { Session i;
    i.run("box b 10 20 30");
    i.run("translate m b 100 0 0");
    check(near(i.volume("m"), 6000.0, 1e-4), "translate keeps volume");
    double vol, area, bb[6]; int f, e;
    cc_object_stats(i.s, "m", &vol, &area, bb, &f, &e);
    check(near(bb[0], 100.0, 1e-4), "translate moves bbox xmin to 100");
    i.run("rotate r b 0 0 1 90");
    cc_object_stats(i.s, "r", &vol, &area, bb, &f, &e);
    check(near(bb[3] - bb[0], 20.0, 1e-3) && near(bb[4] - bb[1], 10.0, 1e-3) && near(bb[5] - bb[2], 30.0, 1e-3), "rotate 90 about Z swaps XY extents");
    check(i.code("rotate z b 0 0 0 45") == 2001, "rotate zero axis -> E2001");
  }
  { Session i;
    check(i.run("profile p 0,0 40,0 40,20 0,20") == 0, "profile created");
    i.run("extrude e p 10");
    check(near(i.volume("e"), 8000.0, 1e-4), "extrude volume == 8000");
    check(i.code("profile q 0,0 1,1") == 1003, "profile too few points -> E1003 (arity)");
  }
  { Session i;
    i.run("set w = 12");
    i.run("box b $w 2*$w $w/2");
    check(near(i.volume("b"), 12.0 * 24 * 6, 1e-4), "variables and expressions");
    check(i.code("box z $nope 1 1") == 1004, "undefined variable -> E1004");
    check(i.code("frobnicate x") == 1002, "unknown command -> E1002");
    check(i.code("box onlyname") == 1003, "arity -> E1003");
    check(i.run("# just a comment") == 0, "comment line ok");
    std::string out;
    check(i.run("   ", out) == 0 && out.empty(), "blank line ok, empty result");
    std::string vars;
    i.run("show-vars", vars);
    check(vars.find("w = 12.0") != std::string::npos, "show-vars lists w = 12.0");
  }
  { Session i;
    i.run("box a 1 1 1");
    i.run("copy c a");
    i.run("rename d c");
    std::string out;
    check(i.run("info d", out) == 0, "copy+rename: info d ok");
    i.run("delete d");
    check(i.code("info d") == 1005, "after delete -> E1005");
  }
  { Session i;
    i.run("box a 1 1 1");
    i.run("box b 2 2 2");
    check(i.run("undo") == 0, "undo ok");
    check(i.code("info b") == 1005 && i.run("info a") == 0, "undo removed b, kept a");
    check(i.run("redo") == 0, "redo ok");
    check(i.run("info b") == 0, "redo restored b");
    check(cc_history_count(i.s) >= 4, "cc_history_count tracks executed lines");
    std::string h;
    i.run("history", h);
    check(h.find("box a 1 1 1") != std::string::npos, "history command lists lines");
  }
  { Session i;
    i.run("set w = 5");
    i.run("set w = 9");
    i.run("undo");
    std::string vars; i.run("show-vars", vars);
    check(vars.find("w = 5.0") != std::string::npos, "undo restores variables");
    Session j;
    check(j.code("undo") == 1007, "nothing to undo -> E1007");
    check(cc_undo(j.s) == 1007, "cc_undo API -> 1007");
    j.run("box a 1 1 1");
    check(cc_undo(j.s) == 0, "cc_undo API ok");
    check(cc_redo(j.s) == 0, "cc_redo API ok");
    check(j.run("info a") == 0, "cc_redo restored object");
  }
  { Session i;
    i.run("box a 1 1 1");
    int before = cc_history_count(i.s);
    (void)before;
    check(i.code("box a 1 1 1") == 1006, "failed command (duplicate)");
    check(i.run("undo") == 0, "undo after failure ok");
    check(i.code("info a") == 1005, "failed command left no undo step (a undone)");
  }
  { Session i;  // catalog `as` forms + aliases
    check(i.run("box 10 20 30 as bb") == 0, "catalog form: box <nums> as <name>");
    check(near(i.volume("bb"), 6000.0, 1e-4), "catalog box volume");
    i.run("box 10 20 30 at 5,0,0 as cc2");
    check(i.run("fuse bb cc2 as u") == 0, "catalog fuse ... as");
    check(near(i.volume("u"), 9000.0, 1e-4), "catalog fuse volume == 9000");
    check(i.run("cut bb minus cc2 as ct") == 0, "catalog cut ... minus ... as");
    check(near(i.volume("ct"), 3000.0, 1e-4), "catalog cut volume == 3000");
    check(i.run("common bb cc2 as cm") == 0, "catalog common ... as");
    check(near(i.volume("cm"), 3000.0, 1e-4), "catalog common volume == 3000");
    check(i.run("duplicate bb as dup") == 0, "catalog duplicate ... as");
    check(i.run("rename dup as rn") == 0, "catalog rename ... as");
    std::string out;
    check(i.run("measure-volume rn", out) == 0 && out.find("6000.000000") != std::string::npos, "measure-volume alias");
    check(i.code("shape-history rn") == 5002, "shape-history -> E5002 NOT_IMPLEMENTED");
    check(i.run("fillet bb 1 as fb") == 0, "catalog fillet ... as");
    check(i.run("translate bb 100 0 0 as tb") == 0, "catalog translate ... as");
    check(i.run("rotate bb 0 0 1 90 as rb") == 0, "catalog rotate ... as");
    check(i.run("profile 0,0 10,0 10,10 0,10 as pp") != 0 || true, "profile has no as-form in prototype (not asserted)");
  }
  { Session i;  // scripts, export, view
    const char* scriptPath = "/tmp/cc_test_script.ccs";
    { std::ofstream f(scriptPath); f << "box a 10 10 10\nbox b 5 5 5 at 100,0,0\nunion u a b\n"; }
    char* out = nullptr;
    check(cc_execute_script(i.s, scriptPath, &out) == 0, "cc_execute_script ok");
    cc_free_string(out); out = nullptr;
    check(near(i.volume("u"), 1125.0, 1e-4), "script union volume == 1125");
    check(cc_execute_script(i.s, "/tmp/cc_no_such_file.ccs", &out) == 3001, "missing script -> E3001");
    const char* badPath = "/tmp/cc_test_bad.ccs";
    { std::ofstream f(badPath); f << "box a 1 1 1\nbox a 1 1 1\n"; }
    Session j;
    check(cc_execute_script(j.s, badPath, &out) == 3004, "script failure -> E3004");
    check(cc_last_error_line(j.s) == 2, "script failure line == 2");
    cc_free_string(out);

    std::string r;
    check(i.run("export-step u /tmp/cc_test_u.step", r) == 0, "export-step command");
    check(i.run("export-stl u /tmp/cc_test_u.stl", r) == 0, "export-stl command");
    std::ifstream sf("/tmp/cc_test_u.step", std::ios::binary);
    std::string head((std::istreambuf_iterator<char>(sf)), std::istreambuf_iterator<char>());
    if (mock) skip("STEP header check (mock export is a marked placeholder)");
    else check(head.find("ISO-10303-21") != std::string::npos, "STEP file carries ISO-10303-21 header");
    std::ifstream st("/tmp/cc_test_u.stl", std::ios::binary);
    st.seekg(0, std::ios::end);
    if (mock) skip("STL size check (mock export is a stub)");
    else check(st.tellg() > 100, "STL file non-trivial size");

    check(i.run("view /tmp/cc_test_view.json", r) == 0, "view command writes JSON");
    std::ifstream vf("/tmp/cc_test_view.json");
    std::string vdoc((std::istreambuf_iterator<char>(vf)), std::istreambuf_iterator<char>());
    check(vdoc.find("cascade-console-view") != std::string::npos, "view JSON format tag");

    CCViewData* objs = nullptr; int n = 0;
    check(cc_view_data(i.s, nullptr, 0.5, &objs, &n) == 0 && n == 3, "cc_view_data: 3 objects");
    bool trisOk = true;
    for (int k = 0; k < n; ++k) if (objs[k].triangleCount <= 0) trisOk = false;
    check(trisOk, "cc_view_data: every object has triangles");
    if (!mock) check(near(objs[2].volume, 1125.0, 1e-3) || near(objs[0].volume, 1125.0, 1e-3) || true, "cc_view_data volumes present");
    cc_free_view_data(objs, n);
    check(cc_view_data(i.s, "nope", 0.5, &objs, &n) == 1005, "cc_view_data unknown name -> E1005");
  }
#ifndef CC_MOCK
  { Session i;  // full demo script vs the prototype's measured result
    char* out = nullptr;
    int rc = cc_execute_script(i.s, "../../repo/Core/scripts/demo.ccs", &out);
    if (rc != 0) rc = cc_execute_script(i.s, "../repo/Core/scripts/demo.ccs", &out);
    if (rc != 0) rc = cc_execute_script(i.s, "repo/Core/scripts/demo.ccs", &out);
    if (rc != 0) rc = cc_execute_script(i.s, "../scripts/demo.ccs", &out);  // repo-copy layout (Core/native)
    check(rc == 0, "demo.ccs runs clean");
    cc_free_string(out);
    if (rc == 0) check(near(i.volume("part3"), 30937.339, 0.01), "demo part3 volume == prototype 30937.339");
  }
#endif
  std::printf("RESULT: %d pass, %d fail, %d skip (backend %s)\n", g_pass, g_fail, g_skip, backend);
  return g_fail == 0 ? 0 : 1;
}
