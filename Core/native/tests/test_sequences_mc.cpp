// ============================================================================
// test_sequences_mc.cpp — delete / re-add SEQUENCE matrix on the DEVICE
// code path (v0.4.2).
//
// Device report on v0.4.1: "If I delete a fillet and try again on that
// edge it fails — check all actions like that." The per-command matrix
// (test_matrix_mc.cpp) proves each command once, in isolation; it says
// nothing about the sequences the app actually drives. This binary
// fills that gap: it drives cc_execute exactly the way AppState does —
//
//   addStepFromUI  -> the step's line executes on the LIVE session;
//   deleteStep / applyStepEdit / loadProject
//                  -> the remaining steps REPLAY into a FRESH session,
//                     adopted only when every line succeeds (on failure
//                     the live session must be untouched);
//   after every successful mutation the whole scene is pulled through
//   cc_view_data, as refreshScene does.
//
// — and runs the sequence families for EVERY panel command:
//   S1  create -> delete step -> re-create identical (primitives)
//   S2  create -> delete step -> re-create identical (derived commands,
//       same requested name, same params/edges; re-created geometry
//       must equal first-creation geometry by volume)
//   S3a create A -> create B -> delete B -> re-add B
//   S3b create A -> create B -> delete A (middle, independent) ->
//       re-add A at the end
//   S4  delete a SOURCE step while a dependent exists: the replay
//       must fail cleanly, the live model must be unchanged, and a
//       full replay must still work afterwards
//   S5  edit a step after deleting another (result must match a
//       fresh build of the edited list)
//   S6  undo / redo interleaved with delete / re-add (one session)
//   S7  interpreter `delete` -> re-add -> full replay
// plus the lead repro with a user-typed result name.
//
// The command lines are byte-identical to what the production
// StepLineBuilder emits for the panel's default/representative
// parameters (auto names per CascadeNames; qualified operand refs).
// The Swift half of the same sequences — the production AppState
// object driving a real NativeEngine — runs in the Swift harness
// (Shared/Viewer/Verification/swift-harness), same CI job.
//
// Usage: test_sequences_mc
// Exit status 0 iff every check passes.
// ============================================================================
#include "cc_facade.h"
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static int g_pass = 0, g_fail = 0;
static void check(bool ok, const std::string& label, const std::string& detail = "") {
  if (ok) { g_pass++; printf("PASS  %s\n", label.c_str()); }
  else { g_fail++; printf("FAIL  %s  %s\n", label.c_str(), detail.c_str()); }
}

struct App {
  CCSession* s = nullptr;
  App() { s = cc_session_create(); }
  ~App() { if (s) cc_session_destroy(s); }
  int exec(const std::string& line, std::string* err = nullptr) {
    char* out = nullptr;
    int rc = cc_execute(s, line.c_str(), &out);
    if (out) cc_free_string(out);
    if (rc != 0 && err) *err = std::string(cc_last_error_name(s)) + " / " + cc_last_error_message(s);
    return rc;
  }
  void pullViewData() {  // refreshScene fidelity: tessellate everything
    CCViewData* objs = nullptr; int n = 0;
    cc_view_data(s, nullptr, 0.5, &objs, &n);
    if (objs) cc_free_view_data(objs, n);
  }
  bool add(const std::string& line, std::string* err = nullptr) {
    int rc = exec(line, err);
    if (rc == 0) pullViewData();
    return rc == 0;
  }
  // Replay lines into a fresh session; adopt on full success only.
  bool replay(const std::vector<std::string>& lines, std::string* err = nullptr) {
    CCSession* fresh = cc_session_create();
    for (auto& line : lines) {
      char* out = nullptr;
      int rc = cc_execute(fresh, line.c_str(), &out);
      if (out) cc_free_string(out);
      if (rc != 0) {
        if (err) *err = std::string(cc_last_error_name(fresh)) + " / " + cc_last_error_message(fresh);
        cc_session_destroy(fresh);
        return false;
      }
    }
    cc_session_destroy(s);
    s = fresh;
    pullViewData();
    return true;
  }
  double volume(const std::string& qualified) {
    std::string line = "volume " + qualified;
    char* out = nullptr;
    int rc = cc_execute(s, line.c_str(), &out);
    double v = -1;
    if (rc == 0 && out) {
      const char* eq = strstr(out, "= ");
      if (eq) v = atof(eq + 2);
    }
    if (out) cc_free_string(out);
    return v;
  }
  bool has(const std::string& qualified) {
    for (int i = 0; i < cc_object_count(s); ++i)
      if (qualified == cc_object_name(s, i)) return true;
    for (int i = 0; i < cc_profile_count(s); ++i)
      if (qualified == cc_profile_name(s, i)) return true;
    return false;
  }
};

static bool closeVol(double a, double b) {
  return a > 0 && b > 0 && std::fabs(a - b) <= 1e-6 * std::max(a, b);
}

// The standard source set used by derived-command sequences.
// Lines exactly as StepLineBuilder emits them (auto names).
static const char* kBox = "box box1 10 10 10";
static const char* kBox2 = "box box2 4 4 4 at 3,3,3";
static const char* kProf = "profile sq 0,0 10,0 10,10 0,10";
static const char* kProf2 = "profile sq2 0,0 6,0 6,6 0,6";

struct Case {
  std::string id;
  std::vector<std::string> sourceLines;
  std::string createLine;
  std::string resultName;
};

static std::vector<Case> cases() {
  std::vector<Case> v;
  auto add = [&](const char* id, std::vector<std::string> src, const char* line, const char* res) {
    v.push_back(Case{id, src, line, res});
  };
  add("fillet-edges", {kBox}, "fillet fillet1 box:box1 1 edges 3", "fillet:fillet1");
  add("fillet-all", {kBox}, "fillet fillet1 box:box1 1", "fillet:fillet1");
  add("chamfer-edges", {kBox}, "chamfer chamfer1 box:box1 1 edges 0,1", "chamfer:chamfer1");
  add("chamfer-all", {kBox}, "chamfer chamfer1 box:box1 1", "chamfer:chamfer1");
  add("shell", {kBox}, "shell shell1 box:box1 2", "shell:shell1");
  add("translate", {kBox}, "translate translate1 box:box1 5 0 0", "translate:translate1");
  add("rotate", {kBox}, "rotate rotate1 box:box1 0 0 1 90", "rotate:rotate1");
  add("rotate-about", {kBox}, "rotate rotate1 box:box1 0 0 1 90 about 5,5,0", "rotate:rotate1");
  add("mirror", {kBox}, "mirror mirror1 box:box1 yz 0", "mirror:mirror1");
  add("mirror-off", {kBox}, "mirror mirror1 box:box1 xy 10", "mirror:mirror1");
  add("pattern-linear", {kBox}, "pattern pattern1 box:box1 linear 3 15 0 0", "pattern:pattern1");
  add("pattern-circular", {kBox}, "pattern pattern1 box:box1 circular 4 360 z", "pattern:pattern1");
  add("copy", {kBox}, "copy copy1 box:box1", "copy:copy1");
  add("extrude", {kProf}, "extrude extrude1 profile:sq 5", "extrude:extrude1");
  add("revolve", {kProf}, "revolve revolve1 profile:sq 360", "revolve:revolve1");
  add("loft", {kProf, kProf2}, "loft loft1 profile:sq@0 profile:sq2@10", "loft:loft1");
  add("loft-ruled", {kProf, kProf2}, "loft loft1 profile:sq@0 profile:sq2@10 ruled", "loft:loft1");
  add("sweep", {kProf2}, "sweep sweep1 profile:sq2 0,0,0 0,0,30", "sweep:sweep1");
  add("union", {kBox, kBox2}, "union union1 box:box1 box:box2", "union:union1");
  add("cut", {kBox, kBox2}, "cut cut1 box:box1 box:box2", "cut:cut1");
  add("intersect", {kBox, kBox2}, "intersect intersect1 box:box1 box:box2", "intersect:intersect1");
  return v;
}

int main() {
  std::string err;
  // ---- S2: create -> delete step -> re-create identical -------------
  for (auto& c : cases()) {
    App app;
    bool ok = true;
    for (auto& l : c.sourceLines) ok = ok && app.add(l, &err);
    ok = ok && app.add(c.createLine, &err);
    double v1 = app.volume(c.resultName);
    ok = ok && v1 > 0;
    ok = ok && app.replay(c.sourceLines, &err);   // delete the derived step
    ok = ok && !app.has(c.resultName);
    ok = ok && app.add(c.createLine, &err);       // re-create identical
    double v2 = app.volume(c.resultName);
    check(ok && closeVol(v1, v2), "S2 delete+re-add " + c.id,
          "err=" + err + " v1=" + std::to_string(v1) + " v2=" + std::to_string(v2));
  }
  // ---- S1: primitives create -> delete -> re-create -----------------
  struct Prim { const char* id; const char* line; const char* res; };
  std::vector<Prim> prims = {
    {"box", "box box1 10 10 10", "box:box1"},
    {"cylinder", "cylinder cylinder1 5 12", "cylinder:cylinder1"},
    {"sphere", "sphere sphere1 6", "sphere:sphere1"},
    {"cone", "cone cone1 6 2 10", "cone:cone1"},
    {"torus", "torus torus1 10 3", "torus:torus1"},
    {"profile", "profile sq 0,0 10,0 10,10 0,10", "profile:sq"},
  };
  for (auto& p : prims) {
    App app;
    bool ok = app.add(p.line, &err);
    double v1 = std::string(p.id) == "profile" ? 1 : app.volume(p.res);
    ok = ok && app.replay({}, &err);            // delete the only step
    ok = ok && !app.has(p.res);
    ok = ok && app.add(p.line, &err);           // re-create identical
    double v2 = std::string(p.id) == "profile" ? 1 : app.volume(p.res);
    check(ok && closeVol(v1, v2), std::string("S1 delete+re-add prim ") + p.id, "err=" + err);
  }
  // ---- S3a: A -> B -> delete B -> re-add B --------------------------
  {
    App app;
    bool ok = app.add(kBox, &err);
    ok = ok && app.add("fillet fillet1 box:box1 1 edges 3", &err);
    ok = ok && app.add("chamfer chamfer1 box:box1 1 edges 0", &err);
    double vb = app.volume("chamfer:chamfer1");
    ok = ok && app.replay({kBox, "fillet fillet1 box:box1 1 edges 3"}, &err);
    ok = ok && app.add("chamfer chamfer1 box:box1 1 edges 0", &err);
    check(ok && closeVol(vb, app.volume("chamfer:chamfer1")), "S3a delete last + re-add", "err=" + err);
  }
  // ---- S3b: A -> B -> delete A (middle, independent) -> re-add A ----
  {
    App app;
    bool ok = app.add(kBox, &err);
    ok = ok && app.add("translate translate1 box:box1 5 0 0", &err);
    ok = ok && app.add("fillet fillet1 box:box1 1 edges 3", &err);
    double va = app.volume("translate:translate1");
    ok = ok && app.replay({kBox, "fillet fillet1 box:box1 1 edges 3"}, &err);
    ok = ok && app.add("translate translate1 box:box1 5 0 0", &err);
    check(ok && closeVol(va, app.volume("translate:translate1")), "S3b delete middle + re-add at end", "err=" + err);
  }
  // ---- S4: delete SOURCE step with a dependent ----------------------
  {
    App app;
    bool ok = app.add(kBox, &err);
    ok = ok && app.add("fillet fillet1 box:box1 1 edges 3", &err);
    double vBefore = app.volume("fillet:fillet1");
    std::string rerr;
    bool replayOk = app.replay({"fillet fillet1 box:box1 1 edges 3"}, &rerr);
    check(!replayOk && !rerr.empty(), "S4 delete source: replay fails cleanly", "rerr=" + rerr);
    check(app.has("fillet:fillet1") && closeVol(vBefore, app.volume("fillet:fillet1")),
          "S4 delete source: live model unchanged after failed replay");
    check(app.replay({kBox, "fillet fillet1 box:box1 1 edges 3"}, &err),
          "S4 full replay still works after", "err=" + err);
  }
  // ---- S5: edit a step after deleting another -----------------------
  {
    App app;
    bool ok = app.add(kBox, &err);
    ok = ok && app.add("fillet fillet1 box:box1 1 edges 3", &err);
    ok = ok && app.add("chamfer chamfer1 box:box1 1 edges 0", &err);
    ok = ok && app.replay({kBox, "chamfer chamfer1 box:box1 2 edges 0"}, &err);
    double vEdit = app.volume("chamfer:chamfer1");
    App ref;
    bool rok = ref.add(kBox, &err) && ref.add("chamfer chamfer1 box:box1 2 edges 0", &err);
    check(ok && rok && closeVol(vEdit, ref.volume("chamfer:chamfer1")),
          "S5 edit after delete matches fresh build", "err=" + err);
  }
  // ---- S6: undo/redo interleaved with delete/re-add (one session) ---
  {
    App app;
    bool ok = app.add(kBox, &err);
    ok = ok && app.add("fillet fillet1 box:box1 1 edges 3", &err);
    double v1 = app.volume("fillet:fillet1");
    ok = ok && app.exec("undo") == 0;
    ok = ok && !app.has("fillet:fillet1");
    ok = ok && app.exec("redo") == 0;
    ok = ok && app.has("fillet:fillet1");
    ok = ok && app.exec("undo") == 0;
    ok = ok && app.add("fillet fillet1 box:box1 1 edges 3", &err);
    check(ok && closeVol(v1, app.volume("fillet:fillet1")), "S6 undo/redo interleave + re-add", "err=" + err);
  }
  // ---- S7: interpreter delete, re-add, then full replay -------------
  {
    App app;
    bool ok = app.add(kBox, &err);
    ok = ok && app.add("fillet fillet1 box:box1 1 edges 3", &err);
    double v1 = app.volume("fillet:fillet1");
    ok = ok && app.exec("delete fillet:fillet1") == 0;
    ok = ok && app.add("fillet fillet1 box:box1 1 edges 3", &err);
    ok = ok && closeVol(v1, app.volume("fillet:fillet1"));
    ok = ok && app.replay({kBox, "fillet fillet1 box:box1 1 edges 3"}, &err);
    check(ok && closeVol(v1, app.volume("fillet:fillet1")), "S7 interpreter delete + re-add + replay", "err=" + err);
  }
  // ---- LEAD with a user-typed result name ---------------------------
  {
    App app;
    bool ok = app.add("box cube 10 10 10", &err);
    ok = ok && app.add("fillet round1 box:cube 1 edges 3", &err);
    double v1 = app.volume("fillet:round1");
    ok = ok && app.replay({"box cube 10 10 10"}, &err);
    ok = ok && app.add("fillet round1 box:cube 1 edges 3", &err);
    check(ok && closeVol(v1, app.volume("fillet:round1")), "LEAD named-result delete+re-add", "err=" + err);
  }
  printf("RESULT: %d pass, %d fail (mc sequence matrix)\n", g_pass, g_fail);
  return g_fail ? 1 : 0;
}
