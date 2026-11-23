// ============================================================================
// ccsim_commands.cpp — the `sim` command family: parsing, session
// state handling and result formatting for ccsim. The numerical work
// lives in ccsim.cpp; this file is the language layer, written to the
// interpreter's conventions (same result-string style, same error
// codes — see ccsim.h). Grammar (tokens after `sim`):
//
//   sim material list
//   sim material show <name>
//   sim material custom <name> <E> <nu> <rho> <k> <yield>
//   sim material <object> <name>     assign (makes <object> active)
//   sim material <name>              assign to the active object
//   sim select <object>
//   sim fix [@face <n> | <object> @face <n>]              statics fixity
//   sim fix temp @face <n> <degC>    (object form likewise) thermal
//   sim load [@face <n> | <object> @face <n>] force <fx> <fy> <fz>
//   sim load ... pressure <MPa>
//   sim load ... heatflux <W/mm^2>
//   sim load ... convection <W/(mm^2 K)> <amb degC>
//   sim mesh size <mm>
//   sim mesh engine hex              (tet -> NOT_IMPLEMENTED)
//   sim thermal | sim static         analysis mode for `sim run`
//   sim run [<object>]
//   sim results
//   sim results view vonmises|temperature|displacement [<path.ccsf>]
//   sim results export <path.csv>
//   sim clear [<object>]
//   sim modal ...                    NOT_IMPLEMENTED (reserved)
//
// Face indices are census indices (0-based), the shared index space.
// ============================================================================
#include "ccsim.h"

#include <cmath>
#include <cstdio>
#include <set>

namespace ccsim {
namespace {

std::string fmt(double v) {
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%.6g", v);
  return buf;
}
std::string fmtF(double v, int prec) {
  char buf[64];
  std::snprintf(buf, sizeof(buf), "%.*f", prec, v);
  return buf;
}
Error arity(const std::string& m) { return Error{1003, "ARITY", "'sim': " + m}; }
Error notImplemented(const std::string& what) {
  return Error{5002, "NOT_IMPLEMENTED", what + " is not in this build."};
}

const char* kUsage =
  "sim commands:\n"
  "  sim material list | show <name> | custom <name> <E> <nu> <rho> <k> <yield>\n"
  "  sim material <object> <name> — assign a material (makes it the active object)\n"
  "  sim select <object>\n"
  "  sim fix <object> @face <n> — clamp a face (statics)\n"
  "  sim fix temp <object> @face <n> <degC> — hold a face at a temperature\n"
  "  sim load <object> @face <n> force <fx> <fy> <fz> | pressure <MPa>\n"
  "  sim load <object> @face <n> heatflux <W/mm^2> | convection <h> <ambC>\n"
  "  sim mesh size <mm> | sim mesh engine hex\n"
  "  sim thermal | sim static — choose what 'sim run' solves\n"
  "  sim run [<object>] | sim results | sim results view <field> [path] | sim results export <path>\n"
  "  sim clear [<object>]";

void invalidateResults(State& st, const std::string& obj) {
  if (st.lastStatics && st.lastStatics->objectName == obj) st.lastStatics.reset();
  if (st.lastThermal && st.lastThermal->objectName == obj) st.lastThermal.reset();
}

// Resolve the object for a command: explicit name wins, else active.
std::string needObject(State& st, Host& host, const std::string& explicitName) {
  std::string name = explicitName.empty() ? st.activeObject : explicitName;
  if (name.empty())
    throw arity("name an object (or assign a material first to make one active).");
  (void)host.object(name);  // throws E1005 if it does not exist
  st.activeObject = name;
  return name;
}

// Parse [@face <n> | <object> @face <n>] starting at pos; returns the
// face index and sets objOut ("" when the active object is meant).
int parseFaceRef(State& st, Host& host, const std::vector<std::string>& a,
                 size_t& pos, std::string& objOut) {
  objOut.clear();
  if (pos < a.size() && a[pos] != "@face") { objOut = a[pos]; ++pos; }
  if (pos >= a.size() || a[pos] != "@face")
    throw arity("expected '@face <n>' — write e.g. 'sim fix part @face 3'.");
  ++pos;
  if (pos >= a.size()) throw arity("'@face' needs a face index.");
  double v = host.num(a[pos]);
  ++pos;
  if (std::fabs(v - std::llround(v)) > 1e-9)
    throw Error{2001, "INVALID_PARAM", "face index must be a whole number."};
  return (int)std::llround(v);
}

std::string driftLine(const VoxelMesh& mesh) {
  double mv = mesh.meshVolume();
  double drift = mesh.solidVolume > 0
                     ? 100.0 * (mv - mesh.solidVolume) / mesh.solidVolume
                     : 0.0;
  std::string s = "mesh: " + std::to_string(mesh.elements.size()) +
                  " elements, " + std::to_string(mesh.nodes.size()) +
                  " nodes, voxel " + fmt(mesh.h) + " mm; mesh volume " +
                  fmt(mv) + " mm^3 vs solid " + fmt(mesh.solidVolume) +
                  " mm^3 (drift " + fmtF(drift, 2) + "%)";
  if (std::fabs(drift) > 10.0)
    s += "\nWARN CC-SIM-005: mesh volume drift over 10% — features thinner "
         "than the voxel may be lost in the analysis mesh.";
  return s;
}

std::string formatStatics(const StaticsResult& r) {
  std::string s = "sim run: " + r.objectName + " (" + r.material.name +
                  ") — linear statics\n" + driftLine(r.mesh);
  s += "\nPCG: " + std::to_string(r.pcgIterations) + " iterations, rel "
       "residual " + fmt(r.pcgRelResidual);
  s += "\nmax displacement: " + fmt(r.maxDisplacement) + " mm at (" +
       fmt(r.maxDisplacementLocation[0]) + ", " +
       fmt(r.maxDisplacementLocation[1]) + ", " +
       fmt(r.maxDisplacementLocation[2]) + ")";
  s += "\nmax von Mises: " + fmt(r.maxVonMises) + " MPa at element " +
       std::to_string(r.maxVonMisesElement) + " centroid (" +
       fmt(r.maxVonMisesLocation[0]) + ", " + fmt(r.maxVonMisesLocation[1]) +
       ", " + fmt(r.maxVonMisesLocation[2]) +
       ") — per-element centroid value; coarse meshes under-report surface "
       "peaks, refine to converge";
  if (r.material.yield > 0)
    s += "\nsafety factor vs yield (" + fmt(r.material.yield) +
         " MPa, typical published value): " +
         fmt(r.material.yield / r.maxVonMises) +
         " — linear-static estimate only";
  double massKg = r.mesh.meshVolume() * r.material.rho * 1e-9;
  s += "\nmesh mass: " + fmt(massKg) + " kg (mesh volume x density)";
  return s;
}

std::string formatThermal(const ThermalResult& r) {
  std::string s = "sim run: " + r.objectName + " (" + r.material.name +
                  ") — steady-state thermal\n" + driftLine(r.mesh);
  s += "\nPCG: " + std::to_string(r.pcgIterations) + " iterations, rel "
       "residual " + fmt(r.pcgRelResidual);
  s += "\ntemperature: min " + fmt(r.minTemp) + " degC, max " +
       fmt(r.maxTemp) + " degC";
  return s;
}

std::string doMaterial(State& st, Host& host, const std::vector<std::string>& a) {
  // a[0] == "material"
  if (a.size() >= 2 && a[1] == "list") {
    std::string s = "materials (typical published values — reference data "
                    "for a linear estimate):";
    for (const auto& m : materialLibrary())
      s += "\n  " + m.name + " — E " + fmt(m.E) + " MPa, nu " + fmt(m.nu) +
           ", rho " + fmt(m.rho) + " kg/m^3, k " + fmt(m.k) +
           " W/(m K), yield " + fmt(m.yield) + " MPa";
    for (const auto& kv : st.customMaterials)
      s += "\n  " + kv.first + " — E " + fmt(kv.second.E) + " MPa, nu " +
           fmt(kv.second.nu) + ", rho " + fmt(kv.second.rho) +
           " kg/m^3, k " + fmt(kv.second.k) + " W/(m K), yield " +
           fmt(kv.second.yield) + " MPa (custom)";
    return s;
  }
  if (a.size() >= 2 && a[1] == "show") {
    if (a.size() != 3) throw arity("write: sim material show <name>");
    ObjectSim probe; probe.materialName = a[2];
    const Material* m = st.materialOf(probe);
    if (!m)
      throw Error{1005, "UNDEFINED_NAME",
                  "No material named '" + a[2] + "' exists. 'sim material "
                  "list' shows the library."};
    return m->name + ": E = " + fmt(m->E) + " MPa, nu = " + fmt(m->nu) +
           ", density = " + fmt(m->rho) + " kg/m^3, conductivity = " +
           fmt(m->k) + " W/(m K), yield = " + fmt(m->yield) +
           " MPa (typical published value)";
  }
  if (a.size() >= 2 && a[1] == "custom") {
    if (a.size() != 8)
      throw arity("write: sim material custom <name> <E MPa> <nu> "
                  "<rho kg/m^3> <k W/(m K)> <yield MPa>");
    Material m;
    m.name = a[2];
    m.E = host.num(a[3]); m.nu = host.num(a[4]); m.rho = host.num(a[5]);
    m.k = host.num(a[6]); m.yield = host.num(a[7]);
    m.custom = true;
    if (!(m.E > 0) || !(m.nu > -1.0 && m.nu < 0.5) || !(m.rho > 0) || !(m.k >= 0))
      throw Error{2001, "INVALID_PARAM",
                  "custom material needs E > 0, -1 < nu < 0.5, rho > 0, k >= 0."};
    if (findMaterial(m.name))
      throw Error{1006, "DUPLICATE_NAME",
                  "'" + m.name + "' is a built-in material name — pick "
                  "another name for the custom material."};
    st.customMaterials[m.name] = m;
    return "Custom material '" + m.name + "' defined (E " + fmt(m.E) +
           " MPa). It lives in this session's sim state.";
  }
  // assign: material <object> <name> | material <name>
  std::string objName, matName;
  if (a.size() == 3) { objName = a[1]; matName = a[2]; }
  else if (a.size() == 2) { matName = a[1]; }
  else throw arity("write: sim material <object> <name> (or 'list' / 'show' / 'custom').");
  ObjectSim probe; probe.materialName = matName;
  if (!st.materialOf(probe))
    throw Error{1005, "UNDEFINED_NAME",
                "No material named '" + matName + "' exists. 'sim material "
                "list' shows the library."};
  std::string name = needObject(st, host, objName);
  st.objects[name].materialName = matName;
  invalidateResults(st, name);
  return name + " material = " + matName + " (active sim object: " + name + ")";
}

std::string doRun(State& st, Host& host, const std::vector<std::string>& a) {
  if (a.size() > 2) throw arity("write: sim run [<object>]");
  std::string name = needObject(st, host, a.size() == 2 ? a[1] : "");
  CCGeomShape* shape = host.object(name);
  ObjectSim& os = st.objects[name];
  const Material* mat = st.materialOf(os);
  if (!mat)
    throw Error{4001, "SIM_NO_MATERIAL",
                "sim run: '" + name + "' has no material. Assign one: "
                "'sim material " + name + " steel'."};
  if (!st.thermalMode) {
    if (os.fixedFaces.empty())
      throw Error{4002, "SIM_NO_FIXITY",
                  "sim run: '" + name + "' has no fixed face. Fix one: "
                  "'sim fix " + name + " @face <n>'."};
    if (os.forces.empty() && os.pressures.empty())
      throw Error{2001, "INVALID_PARAM",
                  "sim run: '" + name + "' has no load. Add one: 'sim load " +
                  name + " @face <n> force <fx> <fy> <fz>'."};
  }
  VoxelMesh mesh = buildMesh(shape, st.meshSize);
  if (st.thermalMode) {
    ThermalResult r = solveThermal(shape, mesh, *mat, os.tempFixes,
                                   os.heatFluxes, os.convections);
    r.objectName = name;
    st.lastThermal.reset(new ThermalResult(std::move(r)));
    return formatThermal(*st.lastThermal);
  }
  StaticsResult r = solveStatics(shape, mesh, *mat, os.fixedFaces, os.forces,
                                 os.pressures);
  r.objectName = name;
  st.lastStatics.reset(new StaticsResult(std::move(r)));
  return formatStatics(*st.lastStatics);
}

std::string doResults(State& st, Host& host, const std::vector<std::string>& a) {
  (void)host;
  if (a.size() == 1) {
    if (!st.lastStatics && !st.lastThermal)
      throw Error{2001, "INVALID_PARAM",
                  "no sim results yet — run 'sim run' first."};
    std::string s;
    if (st.lastStatics) s += formatStatics(*st.lastStatics);
    if (st.lastThermal) {
      if (!s.empty()) s += "\n";
      s += formatThermal(*st.lastThermal);
    }
    return s;
  }
  if (a[1] == "view") {
    if (a.size() < 3 || a.size() > 4)
      throw arity("write: sim results view vonmises|temperature|displacement [<path>]");
    const std::string& field = a[2];
    FieldKind kind;
    std::vector<double> values;
    const VoxelMesh* mesh = nullptr;
    std::string obj;
    if (field == "vonmises") {
      if (!st.lastStatics)
        throw Error{2001, "INVALID_PARAM", "no statics results — run 'sim run' first."};
      kind = FieldKind::VonMises;
      values = st.lastStatics->elementVonMises;
      mesh = &st.lastStatics->mesh;
      obj = st.lastStatics->objectName;
    } else if (field == "temperature") {
      if (!st.lastThermal)
        throw Error{2001, "INVALID_PARAM", "no thermal results — run 'sim thermal' then 'sim run'."};
      kind = FieldKind::Temperature;
      values = st.lastThermal->elementTemperature;
      mesh = &st.lastThermal->mesh;
      obj = st.lastThermal->objectName;
    } else if (field == "displacement") {
      if (!st.lastStatics)
        throw Error{2001, "INVALID_PARAM", "no statics results — run 'sim run' first."};
      kind = FieldKind::Displacement;
      const auto& r = *st.lastStatics;
      values.assign(r.mesh.elements.size(), 0.0);
      for (size_t ei = 0; ei < r.mesh.elements.size(); ++ei) {
        double s = 0;
        for (int i = 0; i < 8; ++i) {
          int nd = r.mesh.elements[ei][i];
          double dx = r.displacement[3*nd], dy = r.displacement[3*nd+1],
                 dz = r.displacement[3*nd+2];
          s += std::sqrt(dx*dx + dy*dy + dz*dz);
        }
        values[ei] = s / 8.0;
      }
      mesh = &r.mesh;
      obj = r.objectName;
    } else {
      throw arity("unknown field '" + field + "' — use vonmises, temperature or displacement.");
    }
    std::string path = a.size() == 4 ? a[3] : obj + "_" + field + ".ccsf";
    std::string err;
    if (!writeFieldFile(path, kind, *mesh, values, &err))
      throw Error{3003, "EXPORT_FAILED", "sim results view: " + err};
    double mn = values.empty() ? 0 : values[0], mx = mn;
    for (double v : values) { mn = std::min(mn, v); mx = std::max(mx, v); }
    return "Wrote " + path + " (" + std::to_string(values.size()) +
           " element values, true range " + fmt(mn) + " .. " + fmt(mx) +
           " — the colour scale is this genuine solver min-max, unscaled).";
  }
  if (a[1] == "export") {
    if (a.size() != 3) throw arity("write: sim results export <path.csv>");
    std::string err;
    if (st.thermalMode && st.lastThermal) {
      if (!writeCsv(a[2], "temperature_degC", st.lastThermal->mesh,
                    st.lastThermal->elementTemperature, &err))
        throw Error{3003, "EXPORT_FAILED", "sim results export: " + err};
      return "Wrote " + a[2] + " (per-element temperature, full precision).";
    }
    if (st.lastStatics) {
      if (!writeCsv(a[2], "vonmises_MPa", st.lastStatics->mesh,
                    st.lastStatics->elementVonMises, &err))
        throw Error{3003, "EXPORT_FAILED", "sim results export: " + err};
      return "Wrote " + a[2] + " (per-element von Mises, full precision).";
    }
    if (st.lastThermal) {
      if (!writeCsv(a[2], "temperature_degC", st.lastThermal->mesh,
                    st.lastThermal->elementTemperature, &err))
        throw Error{3003, "EXPORT_FAILED", "sim results export: " + err};
      return "Wrote " + a[2] + " (per-element temperature, full precision).";
    }
    throw Error{2001, "INVALID_PARAM", "no sim results yet — run 'sim run' first."};
  }
  throw arity("write: sim results [view <field> [path] | export <path>]");
}

}  // namespace

std::string execute(State& st, Host& host, const std::vector<std::string>& a) {
  if (a.empty()) return kUsage;
  const std::string& sub = a[0];
  static const std::set<std::string> kReserved = {
    "modal", "transient", "fatigue", "cfd", "buckling", "contact"};
  if (kReserved.count(sub))
    throw notImplemented("'sim " + sub + "' — simulation in this build is "
                         "linear statics + steady-state thermal on the "
                         "voxel mesh");
  if (sub == "material") return doMaterial(st, host, a);
  if (sub == "select") {
    if (a.size() != 2) throw arity("write: sim select <object>");
    return "Active sim object: " + needObject(st, host, a[1]);
  }
  if (sub == "fix") {
    size_t pos = 1;
    bool temp = false;
    // 'temp' may come before or after the object name in our grammar:
    // fix temp @face.. | fix <obj> temp @face.. | fix <obj> @face..
    std::string obj;
    if (pos < a.size() && a[pos] == "temp") { temp = true; ++pos; }
    if (pos < a.size() && a[pos] != "@face") {
      obj = a[pos]; ++pos;
      if (pos < a.size() && a[pos] == "temp") { temp = true; ++pos; }
    }
    if (pos >= a.size() || a[pos] != "@face")
      throw arity("expected '@face <n>' — write e.g. 'sim fix part @face 3'.");
    ++pos;
    if (pos >= a.size()) throw arity("'@face' needs a face index.");
    double fv = host.num(a[pos]);
    ++pos;
    if (std::fabs(fv - std::llround(fv)) > 1e-9)
      throw Error{2001, "INVALID_PARAM", "face index must be a whole number."};
    int face = (int)std::llround(fv);
    std::string name = needObject(st, host, obj);
    ObjectSim& os = st.objects[name];
    if (temp) {
      if (pos >= a.size()) throw arity("write: sim fix temp @face <n> <degC>");
      double t = host.num(a[pos]);
      ++pos;
      if (pos != a.size()) throw arity("write: sim fix temp @face <n> <degC>");
      for (auto& tf : os.tempFixes)
        if (tf.face == face) { tf.tempC = t; invalidateResults(st, name);
          return name + ": face " + std::to_string(face) + " held at " + fmt(t) + " degC."; }
      os.tempFixes.push_back(TempFix{face, t});
      invalidateResults(st, name);
      return name + ": face " + std::to_string(face) + " held at " + fmt(t) + " degC.";
    }
    if (pos != a.size()) throw arity("write: sim fix [<object>] @face <n>");
    for (int f : os.fixedFaces)
      if (f == face) return name + ": face " + std::to_string(face) + " already fixed.";
    os.fixedFaces.push_back(face);
    invalidateResults(st, name);
    return name + ": face " + std::to_string(face) + " fixed (all DOF).";
  }
  if (sub == "load") {
    size_t pos = 1;
    std::string obj;
    int face = parseFaceRef(st, host, a, pos, obj);
    std::string name = needObject(st, host, obj);
    ObjectSim& os = st.objects[name];
    if (pos >= a.size()) throw arity("write: sim load @face <n> force|pressure|heatflux|convection ...");
    const std::string& kind = a[pos++];
    if (kind == "force") {
      if (pos + 3 != a.size()) throw arity("write: sim load @face <n> force <fx> <fy> <fz> (total N on the face)");
      ForceLoad L{face, host.num(a[pos]), host.num(a[pos + 1]), host.num(a[pos + 2])};
      os.forces.push_back(L);
      invalidateResults(st, name);
      return name + ": force (" + fmt(L.fx) + ", " + fmt(L.fy) + ", " +
             fmt(L.fz) + ") N on face " + std::to_string(face) + ".";
    }
    if (kind == "pressure") {
      if (pos + 1 != a.size()) throw arity("write: sim load @face <n> pressure <MPa>");
      PressureLoad P{face, host.num(a[pos])};
      if (!(P.pressure >= 0))
        throw Error{2001, "INVALID_PARAM", "pressure must be >= 0 (it acts along the inward face normal)."};
      os.pressures.push_back(P);
      invalidateResults(st, name);
      return name + ": pressure " + fmt(P.pressure) + " MPa on face " +
             std::to_string(face) + " (inward normal).";
    }
    if (kind == "heatflux") {
      if (pos + 1 != a.size()) throw arity("write: sim load @face <n> heatflux <W/mm^2>");
      HeatFlux H{face, host.num(a[pos])};
      os.heatFluxes.push_back(H);
      invalidateResults(st, name);
      return name + ": heat flux " + fmt(H.q) + " W/mm^2 into face " +
             std::to_string(face) + ".";
    }
    if (kind == "convection") {
      if (pos + 2 != a.size()) throw arity("write: sim load @face <n> convection <h W/(mm^2 K)> <amb degC>");
      Convection C{face, host.num(a[pos]), host.num(a[pos + 1])};
      if (!(C.hCoeff > 0))
        throw Error{2001, "INVALID_PARAM", "convection coefficient must be > 0."};
      os.convections.push_back(C);
      invalidateResults(st, name);
      return name + ": convection h=" + fmt(C.hCoeff) + " W/(mm^2 K), amb " +
             fmt(C.tAmb) + " degC on face " + std::to_string(face) + ".";
    }
    throw arity("unknown load kind '" + kind + "' — use force, pressure, heatflux or convection.");
  }
  if (sub == "mesh") {
    if (a.size() >= 2 && a[1] == "size") {
      if (a.size() != 3) throw arity("write: sim mesh size <mm>");
      double h = host.num(a[2]);
      if (!(h > 0)) throw Error{2001, "INVALID_PARAM", "mesh size must be greater than zero."};
      st.meshSize = h;
      return "Sim mesh size = " + fmt(h) + " mm (voxel hex8).";
    }
    if (a.size() >= 2 && a[1] == "engine") {
      if (a.size() != 3) throw arity("write: sim mesh engine hex");
      if (a[2] == "hex" || a[2] == "voxel")
        return "Sim mesh engine = hex (voxel) — the shipped path.";
      if (a[2] == "tet")
        throw notImplemented("'sim mesh engine tet' — the tetrahedral path "
                             "needs a volume tet mesher; TetGen (AGPL) is "
                             "awaiting the user's licence decision. The "
                             "voxel hex path is the shipped engine");
      throw arity("unknown mesh engine '" + a[2] + "' — use hex.");
    }
    throw arity("write: sim mesh size <mm> | sim mesh engine hex");
  }
  if (sub == "thermal") {
    st.thermalMode = true;
    return "Sim mode = steady-state thermal ('sim run' solves temperature).";
  }
  if (sub == "static") {
    st.thermalMode = false;
    return "Sim mode = linear statics ('sim run' solves stress).";
  }
  if (sub == "run") return doRun(st, host, a);
  if (sub == "results") return doResults(st, host, a);
  if (sub == "clear") {
    if (a.size() > 2) throw arity("write: sim clear [<object>]");
    std::string name = a.size() == 2 ? a[1] : st.activeObject;
    if (name.empty()) throw arity("no active sim object to clear.");
    st.objects.erase(name);
    invalidateResults(st, name);
    return "Cleared sim setup + results for '" + name + "'.";
  }
  throw Error{1002, "UNKNOWN_COMMAND",
              "Unknown sim command '" + sub + "'.\n" + std::string(kUsage)};
}

}  // namespace ccsim
