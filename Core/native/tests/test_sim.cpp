// ============================================================================
// test_sim.cpp — host proof for the ccsim module. The SAME test
// binary is built twice: once against the engine's analytic mock
// backend (+ ccsim_backend_mock.cpp) and once against real OCCT
// geometry (ccgeom_occt.cpp + ccsim_backend_occt.cpp). Face indices
// are never assumed: each backend's faces are discovered by probing
// point-to-face distance at a point known to lie on the face, so the
// mock's documented test-double face order and the OCCT census order
// are both handled by the same code.
//
// Acceptance cases (numbers, not vibes):
//  * steel cantilever 100x10x10 mm, 100 N tip force: tip deflection
//    vs Euler-Bernoulli PL^3/(3EI) = 0.2000 mm at h=2.5 (640
//    elements) and h=1.25 (5,120) — must be within 5% at coarse and
//    improve under refinement. (The Python stand-in in the design
//    docs got 0.1930 / 0.1982 mm with a direct solver.)
//  * pressure 0.1 MPa on the top face (= 100 N UDL): tip deflection
//    vs wL^4/(8EI) = 0.075 mm.
//  * thermal bar, 100 degC one end / 0 other: midpoint = 50 degC,
//    profile linear — deviation reported, asserted small.
//  * singular systems produce E4003 SIM_SINGULAR (thermal with heat
//    flux but no temperature fixity; statics with no fixed DOFs at
//    the solver level) — never a crash, never fake numbers.
//  * command-level setup errors: E4001 no material, E4002 no
//    fixity, E5002 for modal / tet (honest NOT_IMPLEMENTED).
//  * CCSF field file round-trips with the solver's true min-max.
// ============================================================================
#include "ccsim.h"
#include "ccsim_backend.h"
#include "ccgeom.h"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace {

int g_pass = 0, g_fail = 0;
void check(bool ok, const std::string& name) {
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", name.c_str());
  if (ok) ++g_pass; else ++g_fail;
}

struct TestHost : ccsim::Host {
  std::map<std::string, CCGeomShape*>& reg;
  explicit TestHost(std::map<std::string, CCGeomShape*>& r) : reg(r) {}
  CCGeomShape* object(const std::string& name) override {
    auto it = reg.find(name);
    if (it == reg.end())
      throw ccsim::Error{1005, "UNDEFINED_NAME",
                         "'" + name + "' is not defined."};
    return it->second;
  }
  double num(const std::string& token) override {
    std::string t = token;
    if (!t.empty() && t[0] == '$') t = t.substr(1);
    try {
      size_t used = 0;
      double v = std::stod(t, &used);
      if (used != t.size()) throw std::invalid_argument("trailing");
      return v;
    } catch (...) {
      throw ccsim::Error{1004, "BAD_NUMBER",
                         "'" + token + "' is not a number."};
    }
  }
};

struct Runner {
  ccsim::State state;
  TestHost host;
  explicit Runner(std::map<std::string, CCGeomShape*>& reg) : host(reg) {}
  // Run one console line; returns output text. On a ccsim::Error,
  // returns "" and sets errCode.
  std::string run(const std::string& line, int* errCode = nullptr) {
    if (errCode) *errCode = 0;
    std::vector<std::string> toks;
    std::istringstream iss(line);
    std::string t;
    while (iss >> t) toks.push_back(t);
    try {
      if (toks.empty() || toks[0] != "sim")
        throw ccsim::Error{1002, "UNKNOWN_COMMAND", "test runner: not a sim line"};
      toks.erase(toks.begin());
      return ccsim::execute(state, host, toks);
    } catch (const ccsim::Error& e) {
      if (errCode) *errCode = e.code;
      return "";
    }
  }
};

int findFace(CCGeomShape* s, double x, double y, double z) {
  int faces = 0, edges = 0, e = CCGEOM_OK;
  ccgeom_counts(s, &faces, &edges, &e);
  for (int i = 0; i < faces; ++i) {
    int fe = CCGEOM_OK;
    double d = ccgeom_point_face_distance(s, i, x, y, z, &fe);
    if (fe == CCGEOM_OK && d < 1e-6) return i;
  }
  return -1;
}

// Mean z-displacement of the nodes lying in the plane x = xtip.
double tipDeflection(const ccsim::StaticsResult& r, double xtip) {
  double sum = 0;
  int n = 0;
  for (size_t i = 0; i < r.mesh.nodes.size(); ++i) {
    if (std::fabs(r.mesh.nodes[i][0] - xtip) < 1e-9) {
      sum += r.displacement[3 * i + 2];
      ++n;
    }
  }
  return n ? -sum / n : 0.0;  // load is -z; report positive magnitude
}

std::string jnum(double v) {
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%.10g", v);
  return buf;
}

}  // namespace

int main(int argc, char** argv) {
  const char* label = argc > 1 ? argv[1] : "backend";
  std::printf("== ccsim host proof [%s backend] ==\n", label);
  int e = CCGEOM_OK;

  std::map<std::string, CCGeomShape*> reg;
  CCGeomShape* beam = ccgeom_box(100, 10, 10, &e);
  check(beam && e == CCGEOM_OK, "setup: box beam created");
  reg["beam"] = beam;
  reg["beam2"] = ccgeom_box(100, 10, 10, &e);
  reg["tbar"] = ccgeom_box(100, 10, 10, &e);
  reg["cbar"] = ccgeom_box(100, 10, 10, &e);
  reg["beam3"] = ccgeom_box(100, 10, 10, &e);

  int root = findFace(beam, 0, 5, 5);
  int tip = findFace(beam, 100, 5, 5);
  int top = findFace(beam, 50, 5, 10);
  check(root >= 0 && tip >= 0 && top >= 0 && root != tip && root != top &&
        tip != top, "setup: root/tip/top faces discovered by probing");

  std::string json = "{\n";
  json += "  \"backend\": \"" + std::string(label) + "\",\n";

  // ---- A. command grammar + setup errors -------------------------------
  {
    Runner r(reg);
    int ec = 0;
    std::string out = r.run("sim material list");
    check(out.find("steel") != std::string::npos, "A1 material list");
    out = r.run("sim material show steel");
    check(out.find("200000") != std::string::npos, "A2 material show steel");
    r.run("sim run beam", &ec);
    check(ec == 4001, "A3 run with no material -> E4001 SIM_NO_MATERIAL");
    r.run("sim material beam steel");
    r.run("sim run beam", &ec);
    check(ec == 4002, "A4 run with no fixity -> E4002 SIM_NO_FIXITY");
    r.run("sim fix beam @face " + std::to_string(root));
    r.run("sim run beam", &ec);
    check(ec == 2001, "A5 run with no load -> E2001");
    r.run("sim modal", &ec);
    check(ec == 5002, "A6 sim modal -> E5002 NOT_IMPLEMENTED");
    r.run("sim mesh engine tet", &ec);
    check(ec == 5002, "A7 mesh engine tet -> E5002 NOT_IMPLEMENTED");
    r.run("sim bogus", &ec);
    check(ec == 1002, "A8 unknown sim command -> E1002");
    out = r.run("sim material custom unobtanium 1000 0.3 1000 1 10");
    check(out.find("unobtanium") != std::string::npos, "A9 custom material");
    r.run("sim material beam3 unobtanium");
    r.run("sim fix beam3 @face " + std::to_string(root));
    r.run("sim load beam3 @face " + std::to_string(tip) + " force 0 0 -100");
    out = r.run("sim run beam3", &ec);
    check(ec == 0 && r.state.lastStatics &&
          tipDeflection(*r.state.lastStatics, 100.0) > 1.0,
          "A10 custom material runs (soft -> large deflection)");
  }

  // ---- B. cantilever acceptance -----------------------------------------
  double deflCoarse = 0, deflFine = 0, vmCoarse = 0;
  {
    Runner r(reg);
    r.run("sim material beam steel");
    r.run("sim fix beam @face " + std::to_string(root));
    r.run("sim load beam @face " + std::to_string(tip) + " force 0 0 -100");
    int ec = 0;
    std::string out = r.run("sim run beam", &ec);
    check(ec == 0 && r.state.lastStatics, "B1 cantilever coarse run");
    const auto& res = *r.state.lastStatics;
    check(res.mesh.elements.size() == 640 && res.mesh.nodes.size() == 1025,
          "B2 coarse mesh is 640 elements / 1025 nodes");
    deflCoarse = tipDeflection(res, 100.0);
    vmCoarse = res.maxVonMises;
    double errPct = 100.0 * std::fabs(deflCoarse - 0.2) / 0.2;
    std::printf("  [data] coarse h=2.5: tip defl %.6f mm (EB 0.2000, err "
                "%.2f%%), max VM %.3f MPa, max disp %.6f mm, PCG %d iters "
                "res %.3g\n", deflCoarse, errPct, vmCoarse,
                res.maxDisplacement, res.pcgIterations, res.pcgRelResidual);
    check(errPct <= 5.0, "B3 coarse tip deflection within 5% of EB");
    check(vmCoarse > 25.0 && vmCoarse < 62.0,
          "B4 coarse max von Mises in the sane band (centroid values)");
    check(res.pcgRelResidual < 1e-6, "B5 PCG converged");
    json += "  \"cantilever_coarse\": {\"elements\": 640, \"tip_deflection_mm\": " +
            jnum(deflCoarse) + ", \"err_pct_vs_EB\": " + jnum(errPct) +
            ", \"max_vonmises_MPa\": " + jnum(vmCoarse) +
            ", \"max_displacement_mm\": " + jnum(res.maxDisplacement) +
            ", \"pcg_iterations\": " + std::to_string(res.pcgIterations) + "},\n";

    r.run("sim mesh size 1.25");
    out = r.run("sim run beam", &ec);
    check(ec == 0 && r.state.lastStatics, "B6 cantilever fine run");
    const auto& resF = *r.state.lastStatics;
    check(resF.mesh.elements.size() == 5120, "B7 fine mesh is 5120 elements");
    deflFine = tipDeflection(resF, 100.0);
    double errF = 100.0 * std::fabs(deflFine - 0.2) / 0.2;
    std::printf("  [data] fine   h=1.25: tip defl %.6f mm (err %.2f%%), max "
                "VM %.3f MPa\n", deflFine, errF, resF.maxVonMises);
    check(errF < errPct, "B8 refinement improves the deflection");
    check(errF <= 5.0, "B9 fine tip deflection within 5% of EB");
    json += "  \"cantilever_fine\": {\"elements\": 5120, \"tip_deflection_mm\": " +
            jnum(deflFine) + ", \"err_pct_vs_EB\": " + jnum(errF) +
            ", \"max_vonmises_MPa\": " + jnum(resF.maxVonMises) + "},\n";

    // ---- F. field export (uses the fine statics result) -----------------
    out = r.run("sim results view vonmises test_vonmises.ccsf", &ec);
    check(ec == 0, "F1 results view writes CCSF");
    std::ifstream f("test_vonmises.ccsf", std::ios::binary);
    check(f.good(), "F2 CCSF file exists");
    auto rd32 = [&]() { uint32_t v; f.read((char*)&v, 4); return v; };
    auto rdF64 = [&]() { double v; f.read((char*)&v, 8); return v; };
    char magic[4] = {0, 0, 0, 0};
    f.read(magic, 4);
    uint32_t ver = rd32(), kind = rd32(), ulen = rd32();
    std::string unit(ulen, ' ');
    f.read(&unit[0], ulen);
    double fmin = rdF64(), fmax = rdF64();
    uint32_t nc = rd32(), elc = rd32();
    double trueMin = resF.elementVonMises[0], trueMax = trueMin;
    for (double v : resF.elementVonMises) {
      trueMin = std::min(trueMin, v); trueMax = std::max(trueMax, v);
    }
    check(std::memcmp(magic, "CCSF", 4) == 0 && ver == 1 && kind == 1 &&
          unit == "MPa" && nc == resF.mesh.nodes.size() &&
          elc == resF.mesh.elements.size() && fmin == trueMin &&
          fmax == trueMax,
          "F3 CCSF header carries the solver's true min-max + counts");
    f.seekg((std::streamoff)(nc * 12 + elc * 32), std::ios::cur);
    bool valsOk = true;
    for (size_t i = 0; i < elc; ++i) {
      double v = rdF64();
      if (v != resF.elementVonMises[i] || v < fmin || v > fmax) valsOk = false;
    }
    check(valsOk, "F4 CCSF values are the exact per-element solver values");
    out = r.run("sim results export test_vm.csv", &ec);
    std::ifstream csv("test_vm.csv");
    std::string firstLine;
    std::getline(csv, firstLine);
    size_t lines = 1;
    std::string l;
    while (std::getline(csv, l)) ++lines;
    check(ec == 0 && firstLine == "element,cx,cy,cz,vonmises_MPa" &&
          lines == elc + 1, "F5 CSV export: header + one row per element");
  }

  // ---- C. pressure = UDL --------------------------------------------------
  {
    Runner r(reg);
    r.run("sim material beam2 steel");
    r.run("sim fix beam2 @face " + std::to_string(root));
    r.run("sim load beam2 @face " + std::to_string(top) + " pressure 0.1");
    int ec = 0;
    r.run("sim run beam2", &ec);
    check(ec == 0 && r.state.lastStatics, "C1 pressure run");
    double d = tipDeflection(*r.state.lastStatics, 100.0);
    double errPct = 100.0 * std::fabs(d - 0.075) / 0.075;
    std::printf("  [data] pressure 0.1 MPa UDL: tip defl %.6f mm (analytic "
                "0.075, err %.2f%%)\n", d, errPct);
    check(errPct <= 12.0, "C2 pressure tip deflection near UDL analytic");
    json += "  \"pressure_udl\": {\"tip_deflection_mm\": " + jnum(d) +
            ", \"err_pct_vs_analytic\": " + jnum(errPct) + "},\n";
  }

  // ---- D. thermal ---------------------------------------------------------
  double midDev = -1;
  {
    Runner r(reg);
    r.run("sim material tbar steel");
    r.run("sim thermal");
    r.run("sim fix temp tbar @face " + std::to_string(root) + " 100");
    r.run("sim fix temp tbar @face " + std::to_string(tip) + " 0");
    int ec = 0;
    r.run("sim run tbar", &ec);
    check(ec == 0 && r.state.lastThermal, "D1 thermal linear run");
    if (!r.state.lastThermal) {
      check(false, "D2-D4 skipped (no thermal result)");
      goto thermal_done;
    }
    {
    const auto& tr = *r.state.lastThermal;
    double midSum = 0; int midN = 0; double maxDev = 0;
    for (size_t i = 0; i < tr.mesh.nodes.size(); ++i) {
      double x = tr.mesh.nodes[i][0];
      double lin = 100.0 - x;  // 100 at x=0 -> 0 at x=100
      maxDev = std::max(maxDev, std::fabs(tr.temperature[i] - lin));
      if (std::fabs(x - 50.0) < 1e-9) { midSum += tr.temperature[i]; ++midN; }
    }
    double mid = midN ? midSum / midN : -1;
    midDev = std::fabs(mid - 50.0);
    std::printf("  [data] thermal: midpoint %.12f degC (exact 50), max "
                "deviation from linear %.3g degC, range %.6f..%.6f\n",
                mid, maxDev, tr.minTemp, tr.maxTemp);
    check(midN == 25 && midDev < 1e-4, "D2 thermal midpoint is 50 degC");
    check(maxDev < 1e-3, "D3 thermal profile is linear throughout");
    check(std::fabs(tr.minTemp) < 1e-9 && std::fabs(tr.maxTemp - 100.0) < 1e-9,
          "D4 thermal range is exactly the imposed 0..100");
    json += "  \"thermal_linear\": {\"midpoint_C\": " + jnum(mid) +
            ", \"midpoint_deviation_C\": " + jnum(midDev) +
            ", \"max_profile_deviation_C\": " + jnum(maxDev) + "},\n";
    }
    thermal_done:
    // convection smoke: root held at 100, tip convects to 20 degC air
    Runner r2(reg);
    r2.run("sim material cbar steel");
    r2.run("sim thermal");
    r2.run("sim fix temp cbar @face " + std::to_string(root) + " 100");
    r2.run("sim load cbar @face " + std::to_string(tip) +
           " convection 0.001 20");
    r2.run("sim run cbar", &ec);
    check(ec == 0 && r2.state.lastThermal &&
          r2.state.lastThermal->minTemp > 20.0 &&
          r2.state.lastThermal->minTemp < 100.0 &&
          std::fabs(r2.state.lastThermal->maxTemp - 100.0) < 1e-9,
          "D5 convection pulls the free end toward ambient, root stays 100");
  }

  // ---- E. singular systems -> E4003, never a crash ------------------------
  {
    Runner r(reg);
    r.run("sim material tbar steel");
    r.run("sim thermal");
    r.run("sim load tbar @face " + std::to_string(tip) + " heatflux 0.01");
    int ec = 0;
    r.run("sim run tbar", &ec);
    check(ec == 4003, "E1 thermal, flux but no temperature fixity -> E4003");

    // Solver-level: statics with NO fixed faces at all.
    ccsim::State st;
    TestHost host(reg);
    (void)st; (void)host;
    const ccsim::Material* steel = ccsim::findMaterial("steel");
    ccsim::VoxelMesh mesh = ccsim::buildMesh(beam, 2.5);
    bool threw4003 = false;
    try {
      ccsim::ForceLoad fl{tip, 0, 0, -100};
      (void)ccsim::solveStatics(beam, mesh, *steel, {}, {fl}, {});
    } catch (const ccsim::Error& err) {
      threw4003 = (err.code == 4003);
    }
    check(threw4003, "E2 statics with zero fixed DOFs -> E4003 SIM_SINGULAR");
  }

  json += "  \"pass\": " + std::to_string(g_pass) +
          ", \"fail\": " + std::to_string(g_fail) + "\n}\n";
  if (argc > 2) {
    std::ofstream jf(argv[2]);
    jf << json;
  }
  std::printf("== %d passed, %d failed [%s] ==\n", g_pass, g_fail, label);
  for (auto& kv : reg) ccgeom_free(kv.second);
  return g_fail == 0 ? 0 : 1;
}
