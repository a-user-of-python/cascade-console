// ============================================================================
// ccsim.h — Cascade Console simulation module (Layer 2 extension).
//
// WHAT THIS IS
// The `sim` command family for the console interpreter: linear-static
// stress analysis and steady-state thermal analysis on a VOXEL HEX8
// mesh of a named solid, with a built-in materials library. The
// formulation is the cascade-port facade section-11 solver (uniform
// voxel grid, cell kept when its centre classifies inside the solid,
// hex8 trilinear elements, full 2x2x2 Gauss integration, CSR assembly,
// PCG with Jacobi preconditioner, rel. tolerance 1e-8, cap 10 000
// iterations, element cap 250 000), re-implemented here against the
// engine's ccgeom backend interface so it runs on every backend the
// interpreter runs on. OCCT contains no FEM solver; this module is
// the project's own numerical code standing on OCCT geometry queries
// (classification for meshing, point-to-face distance for BC mapping).
//
// HONESTY RULES (standing project rule: no fake results)
// - Results are true solver output at true scale. Field exports carry
//   the solver's genuine min-max; nothing is rescaled, clipped or
//   normalised for display anywhere in this module.
// - What is not built answers NOT_IMPLEMENTED (E5002): modal
//   analysis, the tetrahedral mesh path (pending the user's AGPL
//   decision on TetGen — NO TetGen code exists in this module),
//   transient thermal, convection is implemented (Robin term) but
//   radiation / thermo-mechanical coupling are not, and saying so.
// - Under-constrained models fail with E4003 SIM_SINGULAR, detected
//   BEFORE the solve by a rigid-body-mode energy check and during
//   the solve by PCG breakdown — never a garbage result.
//
// ERROR CODES — the unified table (repo/docs/ERROR-CODES.md):
//   E1003 ARITY, E1004 BAD_EXPRESSION, E1005 UNDEFINED_NAME,
//   E2001 INVALID_PARAM, E2002 GEOMETRY_FAILED, E2003 EMPTY_RESULT,
//   E3003 EXPORT_FAILED, E4001 SIM_NO_MATERIAL, E4002 SIM_NO_FIXITY,
//   E4003 SIM_SINGULAR, E4004 SIM_NO_CONVERGE, E5001 INTERNAL,
//   E5002 NOT_IMPLEMENTED. ccsim throws ccsim::Error; the interpreter
//   adapter translates it 1:1 into its own CCError (same numbers).
//
// UNITS — mm, N, MPa (= N/mm^2), degrees C, W/mm^2 heat flux,
// W/(mm^2 K) convection coefficient at the command surface. Material
// conductivity is stored in W/(m K) (the unit datasheets use) and
// converted internally. Density in kg/m^3 (only used for the mesh
// mass readout; modal is not implemented).
//
// THREADING — like the interpreter session, a ccsim::State is NOT
// thread-safe; call it from the console queue only.
// ============================================================================
#pragma once

#include <array>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "ccgeom.h"

namespace ccsim {

// ---- errors ------------------------------------------------------------------
struct Error {
  int code;
  std::string name;
  std::string message;
};

// ---- host interface (implemented by the interpreter adapter) -----------------
// The sim module never touches the interpreter's internals. The
// adapter (see INTEGRATION.md for its ~40 lines) resolves names and
// numbers with the session's own helpers, so `sim` lines accept
// exactly the same $variable / expression syntax as every other
// command, and unknown objects fail with the session's E1005.
struct Host {
  virtual ~Host() = default;
  // Borrowed handle for a named object; throws Error(E1005) if absent.
  virtual CCGeomShape* object(const std::string& name) = 0;
  // Evaluate a numeric token (may contain $vars / expressions);
  // throws Error(E1004) on failure.
  virtual double num(const std::string& token) = 0;
};

// ---- materials ---------------------------------------------------------------
struct Material {
  std::string name;
  double E = 0;         // MPa
  double nu = 0;        // Poisson's ratio
  double rho = 0;       // kg/m^3
  double k = 0;         // W/(m K)
  double yield = 0;     // MPa, typical published value (0 = none listed)
  bool custom = false;  // user-defined via `sim material custom`
};

// The built-in library. Values are typical published datasheet
// values, labelled as such in every listing — reference data for a
// linear estimate, not a certification.
const std::vector<Material>& materialLibrary();
const Material* findMaterial(const std::string& name);  // library only

// ---- voxel mesh ----------------------------------------------------------------
struct VoxelMesh {
  double h = 0;                       // voxel size (mm)
  double origin[3] = {0, 0, 0};       // bbox min of the source shape
  int cells[3] = {0, 0, 0};           // grid cells per axis
  std::vector<std::array<double, 3>> nodes;   // compact node coords
  std::vector<std::array<int, 8>> elements;   // hex8, standard order:
  // bottom face CCW seen from below [(0,0,0),(1,0,0),(1,1,0),(0,1,0)]
  // in cell-corner units, then the same four on the top face.
  double solidVolume = 0;             // backend (true) volume, mm^3
  double meshVolume() const { return (double)elements.size() * h * h * h; }
};

// Build the voxel mesh of a shape at voxel size h. Throws Error:
// E2001 (h <= 0, grid scan over the 8,000,000-cell cap, element cap
// 250 000 exceeded), E2003 (no solid / no cell centre inside),
// E2002 (backend failure, backend message preserved).
VoxelMesh buildMesh(CCGeomShape* shape, double h);

// Mesh nodes lying on census face `faceIndex`: point-to-face distance
// below 0.75 * mesh.h (the facade section-11 rule). Throws Error.
std::vector<int> nodesOnFace(CCGeomShape* shape, const VoxelMesh& mesh,
                             int faceIndex);

// ---- boundary conditions -------------------------------------------------------
struct ForceLoad { int face; double fx, fy, fz; };        // total N on the face
struct PressureLoad { int face; double pressure; };       // MPa, inward normal
struct TempFix { int face; double tempC; };               // Dirichlet
struct HeatFlux { int face; double q; };                  // W/mm^2, + = into solid
struct Convection { int face; double hCoeff; double tAmb; };  // W/(mm^2 K), degC

// ---- results -------------------------------------------------------------------
struct StaticsResult {
  std::string objectName;
  Material material;
  VoxelMesh mesh;
  std::vector<double> displacement;      // 3 per node, mm
  std::vector<double> elementVonMises;   // per element, MPa (centroid)
  double maxVonMises = 0; int maxVonMisesElement = -1;
  std::array<double, 3> maxVonMisesLocation{{0, 0, 0}};  // element centroid
  double maxDisplacement = 0; int maxDisplacementNode = -1;
  std::array<double, 3> maxDisplacementLocation{{0, 0, 0}};
  int pcgIterations = 0; double pcgRelResidual = 0;
};

struct ThermalResult {
  std::string objectName;
  Material material;
  VoxelMesh mesh;
  std::vector<double> temperature;       // per node, degC
  std::vector<double> elementTemperature;  // per element mean of nodes, degC
  double minTemp = 0, maxTemp = 0;
  int pcgIterations = 0; double pcgRelResidual = 0;
};

// Solve linear statics on an already-built mesh. `fixedNodes` are
// clamped in all three directions. Loads are total forces per face,
// spread evenly over the face's mapped nodes (facade section-11
// rule); pressure loads act along the inward face normal with total
// magnitude pressure * face area. Throws Error: E4003 (rigid-body
// mode left, or PCG breakdown), E4004 (iteration cap), E2001 (a load
// face maps to no mesh nodes / bad material constants).
StaticsResult solveStatics(CCGeomShape* shape, const VoxelMesh& mesh,
                           const Material& mat,
                           const std::vector<int>& fixedFaces,
                           const std::vector<ForceLoad>& forces,
                           const std::vector<PressureLoad>& pressures);

// Solve steady-state conduction on an already-built mesh. At least
// one TempFix is required (checked by the caller-visible path here:
// no Dirichlet node at all -> E4003, the temperature field is only
// defined up to a constant). Throws Error as above.
ThermalResult solveThermal(CCGeomShape* shape, const VoxelMesh& mesh,
                           const Material& mat,
                           const std::vector<TempFix>& tempFixes,
                           const std::vector<HeatFlux>& fluxes,
                           const std::vector<Convection>& convection);

// ---- field export (CCSF) ---------------------------------------------------------
// CCSF is the sim companion to the viewer's CCM1 mesh format: same
// conventions (little-endian, magic + UInt32 version + counts, Z-up
// mm model space), but data-shaped, not GPU-shaped: values are the
// solver's Float64 output, unmodified. Layout:
//   char[4] "CCSF", u32 version=1, u32 fieldKind (1 vonMises MPa,
//   2 temperature degC, 3 displacementMagnitude mm — per-element mean
//   of nodal magnitudes), u32 unitByteLen + unit UTF-8 bytes,
//   f64 trueMin, f64 trueMax (the genuine solver min-max),
//   u32 nodeCount, u32 elementCount,
//   nodes: nodeCount * 3 * f32 (mm), elements: elementCount * 8 *
//   u32 node indices (hex8 order as VoxelMesh), values:
//   elementCount * f64, in mesh element order.
// A viewer colours either this voxel mesh directly, or a BRep
// tessellation by sampling the value of the voxel element whose
// centre is nearest each triangle's centroid (see INTEGRATION.md).
enum class FieldKind : unsigned { VonMises = 1, Temperature = 2, Displacement = 3 };
bool writeFieldFile(const std::string& path, FieldKind kind,
                    const VoxelMesh& mesh, const std::vector<double>& values,
                    std::string* errOut);

// Per-element CSV: element, cx, cy, cz, <value column>. Full
// precision (12 significant digits). Returns false + errOut on I/O
// failure.
bool writeCsv(const std::string& path, const std::string& valueHeader,
              const VoxelMesh& mesh, const std::vector<double>& values,
              std::string* errOut);

// ---- session state + command entry point -----------------------------------------
struct ObjectSim {
  std::string materialName;  // "" = none assigned
  std::vector<int> fixedFaces;
  std::vector<ForceLoad> forces;
  std::vector<PressureLoad> pressures;
  std::vector<TempFix> tempFixes;
  std::vector<HeatFlux> heatFluxes;
  std::vector<Convection> convections;
};

struct State {
  std::map<std::string, ObjectSim> objects;   // by console object name
  std::map<std::string, Material> customMaterials;
  std::string activeObject;                   // "" = none yet
  double meshSize = 2.5;                      // mm, `sim mesh size`
  bool thermalMode = false;                   // `sim thermal` / `sim static`
  // Last results (kept for `sim results*`); labelled with their
  // object name + mesh size in every printout, and cleared when the
  // object's sim setup changes.
  std::unique_ptr<StaticsResult> lastStatics;
  std::unique_ptr<ThermalResult> lastThermal;
  const Material* materialOf(const ObjectSim& os) const;  // library or custom
};

// Execute one `sim ...` line. `args` are the tokens AFTER `sim`.
// Returns the human-readable result text (same style as the
// interpreter's other commands). Throws ccsim::Error on failure.
// NOT undoable and NOT a geometry mutation: the interpreter adapter
// must not put `sim` in its mutating-commands set (INTEGRATION.md).
std::string execute(State& st, Host& host, const std::vector<std::string>& args);

}  // namespace ccsim
