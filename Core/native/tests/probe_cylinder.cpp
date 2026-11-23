// Non-box robustness probe (OCCT backend only): vertical cylinder
// cantilever r=5, h=100 (axis Z), steel, base fixed, 100 N sideways
// at the top face. EB for a solid circular section: I = pi r^4/4 =
// 490.87 mm^4, delta = P L^3 / (3 E I) = 100*1e6/(3*2e5*490.87)
// = 0.3395 mm. Voxel stair-stepping makes this approximate — the
// point is: meshing, curved-face mapping and the solve all work and
// the drift is reported, not hidden.
#include "ccsim.h"
#include "ccsim_backend.h"
#include "ccgeom.h"
#include <cmath>
#include <cstdio>
#include <map>
#include <sstream>
struct H : ccsim::Host {
  std::map<std::string, CCGeomShape*>& reg;
  explicit H(std::map<std::string, CCGeomShape*>& r) : reg(r) {}
  CCGeomShape* object(const std::string& n) override {
    auto it = reg.find(n);
    if (it == reg.end()) throw ccsim::Error{1005, "UNDEFINED_NAME", "no " + n};
    return it->second;
  }
  double num(const std::string& t) override { return std::stod(t); }
};
static int findFace(CCGeomShape* s, double x, double y, double z) {
  int faces = 0, edges = 0, e = 0;
  ccgeom_counts(s, &faces, &edges, &e);
  for (int i = 0; i < faces; ++i) {
    int fe = 0;
    double d = ccgeom_point_face_distance(s, i, x, y, z, &fe);
    if (fe == 0 && d < 1e-4) return i;
  }
  return -1;
}
int main() {
  int e = 0;
  std::map<std::string, CCGeomShape*> reg;
  CCGeomShape* cyl = ccgeom_cylinder(5, 100, &e);
  reg["rod"] = cyl;
  int base = findFace(cyl, 0, 0, 0);       // bottom disc (point at centre)
  int topF = findFace(cyl, 0, 0, 100);
  std::printf("faces: base=%d top=%d\n", base, topF);
  ccsim::State st; H host(reg);
  auto run = [&](const std::string& line) {
    std::vector<std::string> toks; std::istringstream iss(line); std::string t;
    while (iss >> t) toks.push_back(t);
    toks.erase(toks.begin());
    try { return ccsim::execute(st, host, toks); }
    catch (const ccsim::Error& er) { return std::string("ERROR ") + std::to_string(er.code) + " " + er.message; }
  };
  std::printf("%s\n", run("sim material rod steel").c_str());
  std::printf("%s\n", run("sim fix rod @face " + std::to_string(base)).c_str());
  std::printf("%s\n", run("sim load rod @face " + std::to_string(topF) + " force 100 0 0").c_str());
  std::printf("%s\n", run("sim run rod").c_str());
  if (st.lastStatics) {
    double sum = 0; int n = 0;
    for (size_t i = 0; i < st.lastStatics->mesh.nodes.size(); ++i)
      if (std::fabs(st.lastStatics->mesh.nodes[i][2] - 100.0) < 1e-9) {
        sum += st.lastStatics->displacement[3 * i]; ++n;
      }
    std::printf("tip mean x-displacement: %.4f mm over %d nodes (EB 0.3395)\n",
                n ? sum / n : 0.0, n);
  }
  return 0;
}
