// ============================================================================
// ccsim.cpp — Cascade Console simulation core: materials library,
// voxel mesher, hex8 FEM (linear statics + steady-state thermal),
// PCG solver, result field writers.
//
// The formulation mirrors the cascade-port facade section 11 (the
// project's proven solver): uniform voxel grid over the bbox, cell
// kept when its CENTRE is inside the solid, hex8 trilinear elements
// with full 2x2x2 Gauss integration, one stiffness matrix for the
// whole mesh (all elements are identical cubes — exact), CSR
// assembly, PCG with Jacobi preconditioner, rel. tol 1e-8, cap
// 10 000 iterations, caps: 8,000,000 grid cells scanned,
// 250,000 kept elements (MC_FEM_MAX_ELEMENTS).
//
// Differences from the facade original, all deliberate and noted in
// INTEGRATION.md: (1) geometry comes through the engine's ccgeom
// interface + ccsim_backend.h instead of mc_* directly, so the same
// code runs on the host OCCT backend in tests; (2) thermal is added
// (the facade has none) on the same mesh + PCG core; (3) singularity
// is detected BEFORE solving by a rigid-body-mode energy check (the
// facade relies on PCG behaviour alone) — belt and braces, both are
// implemented here.
// ============================================================================
#include "ccsim.h"
#include "ccsim_backend.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>

namespace ccsim {
namespace {

// ---- error helpers -------------------------------------------------------------
Error geomError(int ccgeomErr, const std::string& what) {
  std::string why = ccgeom_last_error();
  if (why.empty())
    why = "backend error (ccgeom code " + std::to_string(ccgeomErr) + ")";
  if (ccgeomErr == CCGEOM_ERR_INVALID_ARG)
    return Error{2001, "INVALID_PARAM", why};
  if (ccgeomErr == CCGEOM_ERR_EMPTY)
    return Error{2003, "EMPTY_RESULT", what + " produced an empty shape."};
  return Error{2002, "GEOMETRY_FAILED",
               what + " failed inside Open CASCADE: " + why};
}
template <typename F>
auto geomCall(const char* what, F&& fn) -> decltype(fn(nullptr)) {
  int e = CCGEOM_OK;
  auto r = fn(&e);
  if (e != CCGEOM_OK) throw geomError(e, what);
  return r;
}

// ---- hex8 element ----------------------------------------------------------------
// Node signs in the standard hex8 order (VoxelMesh comment).
const double kSigns[8][3] = {{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},
                             {-1,-1, 1},{1,-1, 1},{1,1, 1},{-1,1, 1}};

// dN/d(x,y,z) at natural coords (a,b,c) for a cubic element of side h.
void gradN(double a, double b, double c, double h, double dN[8][3]) {
  for (int i = 0; i < 8; ++i) {
    double sx = kSigns[i][0], sy = kSigns[i][1], sz = kSigns[i][2];
    dN[i][0] = sx * (1 + sy * b) * (1 + sz * c) / 8.0 * (2.0 / h);
    dN[i][1] = (1 + sx * a) * sy * (1 + sz * c) / 8.0 * (2.0 / h);
    dN[i][2] = (1 + sx * a) * (1 + sy * b) * sz / 8.0 * (2.0 / h);
  }
}

// Isotropic constitutive matrix (Voigt, engineering shear strains).
void constitutive(double E, double nu, double C[6][6]) {
  double f = E / ((1 + nu) * (1 - 2 * nu));
  double d = (1 - 2 * nu) / 2.0;
  for (int i = 0; i < 6; ++i) for (int j = 0; j < 6; ++j) C[i][j] = 0;
  C[0][0] = C[1][1] = C[2][2] = f * (1 - nu);
  C[0][1] = C[0][2] = C[1][0] = C[1][2] = C[2][0] = C[2][1] = f * nu;
  C[3][3] = C[4][4] = C[5][5] = f * d;
}

// B matrix (6x24, node-major DOFs) from gradN.
void bMatrix(const double dN[8][3], double B[6][24]) {
  for (int i = 0; i < 6; ++i) for (int j = 0; j < 24; ++j) B[i][j] = 0;
  for (int i = 0; i < 8; ++i) {
    B[0][3*i]   = dN[i][0];
    B[1][3*i+1] = dN[i][1];
    B[2][3*i+2] = dN[i][2];
    B[3][3*i]   = dN[i][1]; B[3][3*i+1] = dN[i][0];
    B[4][3*i+1] = dN[i][2]; B[4][3*i+2] = dN[i][1];
    B[5][3*i]   = dN[i][2]; B[5][3*i+2] = dN[i][0];
  }
}

// Element stiffness for a cubic hex8 of side h (statics, 24x24).
void hex8Ke(double h, double E, double nu, double Ke[24][24]) {
  double C[6][6]; constitutive(E, nu, C);
  for (int i = 0; i < 24; ++i) for (int j = 0; j < 24; ++j) Ke[i][j] = 0;
  const double g = 1.0 / std::sqrt(3.0);
  const double gp[2] = {-g, g};
  double detJ = h * h * h / 8.0;
  for (double a : gp) for (double b : gp) for (double c : gp) {
    double dN[8][3]; gradN(a, b, c, h, dN);
    double B[6][24]; bMatrix(dN, B);
    // Ke += B^T C B * detJ (weights are 1)
    double CB[6][24];
    for (int i = 0; i < 6; ++i)
      for (int j = 0; j < 24; ++j) {
        double s = 0; for (int k = 0; k < 6; ++k) s += C[i][k] * B[k][j];
        CB[i][j] = s;
      }
    for (int i = 0; i < 24; ++i)
      for (int j = 0; j < 24; ++j) {
        double s = 0; for (int k = 0; k < 6; ++k) s += B[k][i] * CB[k][j];
        Ke[i][j] += s * detJ;
      }
  }
}

// Element conductivity for a cubic hex8 of side h (thermal, 8x8),
// conductivity k in W/(mm K).
void hex8KeThermal(double h, double k, double Ke[8][8]) {
  for (int i = 0; i < 8; ++i) for (int j = 0; j < 8; ++j) Ke[i][j] = 0;
  const double g = 1.0 / std::sqrt(3.0);
  const double gp[2] = {-g, g};
  double detJ = h * h * h / 8.0;
  for (double a : gp) for (double b : gp) for (double c : gp) {
    double dN[8][3]; gradN(a, b, c, h, dN);
    for (int i = 0; i < 8; ++i)
      for (int j = 0; j < 8; ++j) {
        double s = 0; for (int m = 0; m < 3; ++m) s += dN[i][m] * dN[j][m];
        Ke[i][j] += k * s * detJ;
      }
  }
}

// ---- CSR matrix ------------------------------------------------------------------
struct Csr {
  int n = 0;
  std::vector<int> rowPtr, col, diagIdx;
  std::vector<double> val;
  void matvec(const std::vector<double>& x, std::vector<double>& y) const {
    for (int i = 0; i < n; ++i) {
      double s = 0;
      for (int k = rowPtr[i]; k < rowPtr[i + 1]; ++k) s += val[k] * x[col[k]];
      y[i] = s;
    }
  }
  double diag(int i) const { return val[diagIdx[i]]; }
};

// Assemble a CSR matrix from per-element dense blocks. dofOfNode maps
// a mesh node to its first DOF (dofsPerNode = 1 or 3). Accumulation
// is per-row with linear dedup search (row nnz is small: <= 27 nodes
// * dofsPerNode); rows are sorted when the CSR is finalised.
template <int DOFS>
Csr assemble(const VoxelMesh& mesh, const double* keFlat) {
  const int nDof = (int)mesh.nodes.size() * DOFS;
  std::vector<std::vector<std::pair<int, double>>> rows(nDof);
  const int ed = 8 * DOFS;
  for (const auto& el : mesh.elements) {
    int dofs[24];
    for (int i = 0; i < 8; ++i)
      for (int d = 0; d < DOFS; ++d) dofs[DOFS * i + d] = DOFS * el[i] + d;
    for (int a = 0; a < ed; ++a) {
      auto& row = rows[dofs[a]];
      for (int b = 0; b < ed; ++b) {
        double v = keFlat[a * ed + b];
        if (v == 0.0) continue;
        int c = dofs[b];
        bool found = false;
        for (auto& pr : row) if (pr.first == c) { pr.second += v; found = true; break; }
        if (!found) row.push_back({c, v});
      }
    }
  }
  Csr A; A.n = nDof;
  A.rowPtr.assign(nDof + 1, 0);
  for (int i = 0; i < nDof; ++i) {
    auto& row = rows[i];
    std::sort(row.begin(), row.end(),
              [](const std::pair<int, double>& a, const std::pair<int, double>& b) {
                return a.first < b.first;
              });
    A.rowPtr[i + 1] = A.rowPtr[i] + (int)row.size();
    for (auto& pr : row) { A.col.push_back(pr.first); A.val.push_back(pr.second); }
  }
  A.diagIdx.assign(nDof, -1);
  for (int i = 0; i < nDof; ++i)
    for (int k = A.rowPtr[i]; k < A.rowPtr[i + 1]; ++k)
      if (A.col[k] == i) { A.diagIdx[i] = k; break; }
  return A;
}

// ---- PCG with masked (Dirichlet) DOFs ---------------------------------------------
// Solves A x = b over the free DOFs. x enters with the fixed DOFs'
// prescribed values (0 for statics, the fixed temperatures for
// thermal) and leaves with the full solution. Fixed DOFs are masked
// out of every Krylov vector, which is exactly elimination for the
// homogeneous part plus the standard -K_fc x_c correction via the
// initial residual. Throws E4003 on breakdown / zero diagonal,
// E4004 on iteration cap.
struct PcgOutcome { int iterations; double relResidual; };
PcgOutcome pcgSolve(const Csr& A, const std::vector<double>& b,
                    const std::vector<char>& fixed, std::vector<double>& x,
                    const char* kind) {
  const int n = A.n;
  auto mask = [&](std::vector<double>& v) {
    for (int i = 0; i < n; ++i) if (fixed[i]) v[i] = 0.0;
  };
  std::vector<double> r(n), z(n), p(n), Ap(n);
  A.matvec(x, Ap);
  for (int i = 0; i < n; ++i) r[i] = b[i] - Ap[i];
  mask(r);
  // Convergence scale: the effective right-hand side is b - A x0,
  // whose norm is ||r0|| — with pure Dirichlet loading b itself is
  // zero while r0 is not (an earlier version returned x0 unsolved
  // for exactly that case; the thermal linear test caught it).
  double r0norm = 0;
  for (double v : r) r0norm += v * v;
  r0norm = std::sqrt(r0norm);
  double bnorm = 0;
  { std::vector<double> bm = b; mask(bm);
    for (double v : bm) bnorm += v * v;
    bnorm = std::sqrt(bnorm); }
  const double scale = std::max(bnorm, r0norm);
  if (r0norm == 0.0) return PcgOutcome{0, 0.0};  // x0 already solves it
  std::vector<double> minv(n, 0.0);
  for (int i = 0; i < n; ++i) {
    if (fixed[i]) continue;
    double d = A.diag(i);
    if (!(d > 0.0))
      throw Error{4003, "SIM_SINGULAR",
                  std::string(kind) + ": a free node is disconnected (zero "
                  "stiffness on its diagonal) — the mesh has an isolated "
                  "region or the model is not fixed enough."};
    minv[i] = 1.0 / d;
  }
  for (int i = 0; i < n; ++i) z[i] = minv[i] * r[i];
  mask(z);
  p = z;
  double rsold = 0; for (int i = 0; i < n; ++i) rsold += r[i] * z[i];
  const double tol = 1e-8;
  const int cap = 10000;
  double relres = 1.0;
  for (int it = 1; it <= cap; ++it) {
    A.matvec(p, Ap);
    mask(Ap);
    double pAp = 0; for (int i = 0; i < n; ++i) pAp += p[i] * Ap[i];
    if (!(pAp > 0.0) || !std::isfinite(pAp))
      throw Error{4003, "SIM_SINGULAR",
                  std::string(kind) + ": the stiffness matrix is singular "
                  "(PCG broke down) — the model is not fixed enough to "
                  "stand still. Add or widen a fixed face."};
    double alpha = rsold / pAp;
    for (int i = 0; i < n; ++i) { x[i] += alpha * p[i]; r[i] -= alpha * Ap[i]; }
    mask(r);
    double rn = 0; for (double v : r) rn += v * v;
    relres = std::sqrt(rn) / scale;
    if (relres <= tol) return PcgOutcome{it, relres};
    for (int i = 0; i < n; ++i) z[i] = minv[i] * r[i];
    mask(z);
    double rsnew = 0; for (int i = 0; i < n; ++i) rsnew += r[i] * z[i];
    double beta = rsnew / rsold;
    for (int i = 0; i < n; ++i) p[i] = z[i] + beta * p[i];
    mask(p);
    rsold = rsnew;
  }
  throw Error{4004, "SIM_NO_CONVERGE",
              std::string(kind) + ": PCG hit the 10000-iteration cap "
              "(relative residual " + std::to_string(relres) + "). Try a "
              "coarser mesh ('sim mesh size')."};
}

// Rigid-body-mode energy check (statics): for each of the 6 rigid
// modes (translations, rotations about the fixed nodes' centroid),
// zero the fixed DOFs and measure phi^T K phi. A mode that survives
// with ~zero energy is unconstrained -> the system is singular.
void checkRigidModes(const Csr& A, const VoxelMesh& mesh,
                     const std::vector<char>& fixedDof) {
  const int nNodes = (int)mesh.nodes.size();
  std::vector<std::array<double, 3>> fixedPts;
  for (int i = 0; i < nNodes; ++i)
    if (fixedDof[3 * i]) fixedPts.push_back(mesh.nodes[i]);
  if (fixedPts.empty()) return;  // caller guarantees fixity exists
  std::array<double, 3> c{{0, 0, 0}};
  for (auto& p : fixedPts) for (int d = 0; d < 3; ++d) c[d] += p[d];
  for (int d = 0; d < 3; ++d) c[d] /= (double)fixedPts.size();
  double maxDiag = 0;
  for (int i = 0; i < A.n; ++i) if (!fixedDof[i]) maxDiag = std::max(maxDiag, A.diag(i));
  std::vector<double> phi(A.n), Kphi(A.n);
  for (int mode = 0; mode < 6; ++mode) {
    for (int i = 0; i < nNodes; ++i) {
      double v[3] = {0, 0, 0};
      if (mode < 3) {
        v[mode] = 1.0;
      } else {
        double w[3] = {0, 0, 0}; w[mode - 3] = 1.0;
        double r[3] = {mesh.nodes[i][0] - c[0], mesh.nodes[i][1] - c[1],
                       mesh.nodes[i][2] - c[2]};
        v[0] = w[1] * r[2] - w[2] * r[1];
        v[1] = w[2] * r[0] - w[0] * r[2];
        v[2] = w[0] * r[1] - w[1] * r[0];
      }
      for (int d = 0; d < 3; ++d) phi[3 * i + d] = fixedDof[3 * i + d] ? 0.0 : v[d];
    }
    double phiSq = 0; for (double v : phi) phiSq += v * v;
    if (phiSq == 0.0) continue;  // mode fully prescribed — fine
    A.matvec(phi, Kphi);
    double q = 0; for (int i = 0; i < A.n; ++i) q += phi[i] * Kphi[i];
    if (!(q > 1e-8 * maxDiag * phiSq))
      throw Error{4003, "SIM_SINGULAR",
                  "the model can still move as a rigid body (mode " +
                  std::to_string(mode + 1) + " of 6 is unconstrained) — "
                  "the fixed faces do not hold it still. Fix a wider "
                  "face or another face as well."};
  }
}

}  // namespace

// ---- materials -------------------------------------------------------------------
const std::vector<Material>& materialLibrary() {
  static const std::vector<Material> kLib = {
    // name, E MPa, nu, rho kg/m^3, k W/(m K), yield MPa (typical)
    {"steel",          200000, 0.30, 7850,  50.0, 355},
    {"stainless-304",  193000, 0.29, 8000,  16.0, 215},
    {"aluminium-6061",  68900, 0.33, 2700, 167.0, 276},
    {"aluminium-7075",  71700, 0.33, 2810, 130.0, 503},
    {"titanium-6al4v", 113800, 0.34, 4430,   6.7, 880},
    {"brass",           97000, 0.34, 8500, 109.0, 200},
    {"copper",         117000, 0.34, 8960, 401.0,  70},
    {"pla",              3500, 0.36, 1240,  0.13,  50},
    {"abs",              2300, 0.35, 1050,  0.17,  40},
    {"petg",             2100, 0.38, 1270,  0.20,  50},
  };
  return kLib;
}
const Material* findMaterial(const std::string& name) {
  for (const auto& m : materialLibrary()) if (m.name == name) return &m;
  return nullptr;
}
const Material* State::materialOf(const ObjectSim& os) const {
  if (os.materialName.empty()) return nullptr;
  auto it = customMaterials.find(os.materialName);
  if (it != customMaterials.end()) return &it->second;
  return findMaterial(os.materialName);
}

// ---- mesher ------------------------------------------------------------------------
VoxelMesh buildMesh(CCGeomShape* shape, double h) {
  if (!shape) throw Error{2001, "INVALID_PARAM", "sim mesh: no shape."};
  if (!(h > 0))
    throw Error{2001, "INVALID_PARAM",
                "sim mesh size must be greater than zero."};
  double bb[6];
  geomCall("bbox", [&](int* e) { return ccgeom_bbox(shape, bb, e); });
  double trueVol = geomCall("volume", [&](int* e) { return ccgeom_volume(shape, e); });
  VoxelMesh mesh;
  mesh.h = h;
  mesh.solidVolume = trueVol;
  for (int d = 0; d < 3; ++d) mesh.origin[d] = bb[d];
  long long total = 1;
  for (int d = 0; d < 3; ++d) {
    double span = bb[d + 3] - bb[d];
    long long n = (long long)std::ceil(span / h - 1e-9);
    if (n < 1) n = 1;
    mesh.cells[d] = (int)n;
    total *= n;
    if (total > 8000000)
      throw Error{2001, "INVALID_PARAM",
                  "sim mesh size is too fine: the grid scan would exceed "
                  "8,000,000 cells. Use a larger 'sim mesh size'."};
  }
  const int nx = mesh.cells[0], ny = mesh.cells[1], nz = mesh.cells[2];
  std::vector<std::array<int, 8>> elems;
  for (int k = 0; k < nz; ++k)
    for (int j = 0; j < ny; ++j)
      for (int i = 0; i < nx; ++i) {
        double cx = bb[0] + (i + 0.5) * h;
        double cy = bb[1] + (j + 0.5) * h;
        double cz = bb[2] + (k + 0.5) * h;
        int inside = geomCall("classify", [&](int* e) {
          return ccgeom_point_inside(shape, cx, cy, cz, e);
        });
        if (inside) {
          if ((long long)elems.size() >= 250000)
            throw Error{2001, "INVALID_PARAM",
                        "sim mesh would keep more than 250,000 elements "
                        "(the solver cap). Use a larger 'sim mesh size'."};
          elems.push_back({i, j, k, 0, 0, 0, 0, 0});  // grid corners, fixed below
        }
      }
  if (elems.empty())
    throw Error{2003, "EMPTY_RESULT",
                "sim mesh kept no elements — no voxel centre fell inside "
                "the solid. Use a smaller 'sim mesh size' or check the "
                "object is a solid."};
  // Compact the nodes: grid corner (i,j,k) -> node id, assigned on use.
  const int gx = nx + 1, gy = ny + 1;
  std::vector<int> nodeId((size_t)(nx + 1) * (ny + 1) * (nz + 1), -1);
  auto gridNode = [&](int i, int j, int k) -> int {
    size_t idx = ((size_t)k * gy + j) * gx + i;
    int id = nodeId[idx];
    if (id < 0) {
      id = (int)mesh.nodes.size();
      nodeId[idx] = id;
      mesh.nodes.push_back({bb[0] + i * h, bb[1] + j * h, bb[2] + k * h});
    }
    return id;
  };
  mesh.elements.reserve(elems.size());
  for (auto& e : elems) {
    int i = e[0], j = e[1], k = e[2];
    mesh.elements.push_back({gridNode(i, j, k),     gridNode(i + 1, j, k),
                             gridNode(i + 1, j + 1, k), gridNode(i, j + 1, k),
                             gridNode(i, j, k + 1), gridNode(i + 1, j, k + 1),
                             gridNode(i + 1, j + 1, k + 1), gridNode(i, j + 1, k + 1)});
  }
  return mesh;
}

std::vector<int> nodesOnFace(CCGeomShape* shape, const VoxelMesh& mesh,
                             int faceIndex) {
  int faces = 0, edges = 0;
  geomCall("counts", [&](int* e) { return ccgeom_counts(shape, &faces, &edges, e); });
  if (faceIndex < 0 || faceIndex >= faces)
    throw Error{2001, "INVALID_PARAM",
                "face index " + std::to_string(faceIndex) + " is out of "
                "range — the object has " + std::to_string(faces) + " faces "
                "(indices 0.." + std::to_string(faces - 1) + ")."};
  const double thresh = 0.75 * mesh.h;
  std::vector<int> out;
  for (int i = 0; i < (int)mesh.nodes.size(); ++i) {
    const auto& p = mesh.nodes[i];
    double d = geomCall("face distance", [&](int* e) {
      return ccgeom_point_face_distance(shape, faceIndex, p[0], p[1], p[2], e);
    });
    if (d >= 0 && d < thresh) out.push_back(i);
  }
  return out;
}

// ---- statics -----------------------------------------------------------------------
StaticsResult solveStatics(CCGeomShape* shape, const VoxelMesh& mesh,
                           const Material& mat,
                           const std::vector<int>& fixedFaces,
                           const std::vector<ForceLoad>& forces,
                           const std::vector<PressureLoad>& pressures) {
  if (!(mat.E > 0) || !(mat.nu > -1.0 && mat.nu < 0.5))
    throw Error{2001, "INVALID_PARAM",
                "material '" + mat.name + "' has unusable constants "
                "(need E > 0 and -1 < nu < 0.5)."};
  const int nNodes = (int)mesh.nodes.size();
  const int nDof = 3 * nNodes;
  // Map BC faces to nodes.
  std::vector<char> fixed(nDof, 0);
  std::vector<int> fixedNodes;
  for (int f : fixedFaces) {
    auto ns = nodesOnFace(shape, mesh, f);
    if (ns.empty())
      throw Error{2001, "INVALID_PARAM",
                  "fixed face " + std::to_string(f) + " maps to no mesh "
                  "nodes — refine the mesh or pick another face."};
    for (int nd : ns) {
      if (!fixed[3 * nd]) { fixedNodes.push_back(nd); }
      fixed[3 * nd] = fixed[3 * nd + 1] = fixed[3 * nd + 2] = 1;
    }
  }
  std::vector<double> rhs(nDof, 0.0);
  auto applyLoad = [&](int face, double fx, double fy, double fz,
                       const char* what) {
    auto ns = nodesOnFace(shape, mesh, face);
    if (ns.empty())
      throw Error{2001, "INVALID_PARAM",
                  std::string(what) + " face " + std::to_string(face) +
                  " maps to no mesh nodes — refine the mesh or pick "
                  "another face."};
    double share = 1.0 / (double)ns.size();
    for (int nd : ns) {
      rhs[3 * nd] += fx * share;
      rhs[3 * nd + 1] += fy * share;
      rhs[3 * nd + 2] += fz * share;
    }
  };
  for (const auto& L : forces) applyLoad(L.face, L.fx, L.fy, L.fz, "load");
  for (const auto& P : pressures) {
    double area = geomCall("face area", [&](int* e) {
      return ccgeom_face_area(shape, P.face, e);
    });
    if (!(area > 0))
      throw Error{2001, "INVALID_PARAM",
                  "pressure face " + std::to_string(P.face) + " has no area."};
    double pt[3], nrm[3];
    geomCall("face normal", [&](int* e) {
      return ccgeom_face_point_normal(shape, P.face, pt, nrm, e);
    });
    double total = P.pressure * area;  // N, directed along -normal (inward)
    applyLoad(P.face, -total * nrm[0], -total * nrm[1], -total * nrm[2],
              "pressure load");
  }
  // Assemble + solve.
  double Ke[24][24];
  hex8Ke(mesh.h, mat.E, mat.nu, Ke);
  Csr A = assemble<3>(mesh, &Ke[0][0]);
  checkRigidModes(A, mesh, fixed);
  std::vector<double> x(nDof, 0.0);
  PcgOutcome oc = pcgSolve(A, rhs, fixed, x, "statics");
  // Results.
  StaticsResult r;
  r.material = mat;
  r.mesh = mesh;
  r.displacement = x;
  r.pcgIterations = oc.iterations;
  r.pcgRelResidual = oc.relResidual;
  double C[6][6]; constitutive(mat.E, mat.nu, C);
  r.elementVonMises.assign(mesh.elements.size(), 0.0);
  double dNc[8][3]; gradN(0, 0, 0, mesh.h, dNc);
  double B[6][24]; bMatrix(dNc, B);
  for (size_t ei = 0; ei < mesh.elements.size(); ++ei) {
    const auto& el = mesh.elements[ei];
    double ue[24];
    for (int i = 0; i < 8; ++i)
      for (int d = 0; d < 3; ++d) ue[3 * i + d] = x[3 * el[i] + d];
    double strain[6] = {0, 0, 0, 0, 0, 0};
    for (int i = 0; i < 6; ++i) {
      double s = 0; for (int j = 0; j < 24; ++j) s += B[i][j] * ue[j];
      strain[i] = s;
    }
    double sig[6] = {0, 0, 0, 0, 0, 0};
    for (int i = 0; i < 6; ++i) {
      double s = 0; for (int j = 0; j < 6; ++j) s += C[i][j] * strain[j];
      sig[i] = s;
    }
    double vm = std::sqrt(0.5 * ((sig[0] - sig[1]) * (sig[0] - sig[1]) +
                                 (sig[1] - sig[2]) * (sig[1] - sig[2]) +
                                 (sig[2] - sig[0]) * (sig[2] - sig[0]) +
                                 6.0 * (sig[3] * sig[3] + sig[4] * sig[4] +
                                        sig[5] * sig[5])));
    r.elementVonMises[ei] = vm;
    if (vm > r.maxVonMises) {
      r.maxVonMises = vm;
      r.maxVonMisesElement = (int)ei;
      std::array<double, 3> c{{0, 0, 0}};
      for (int i = 0; i < 8; ++i)
        for (int d = 0; d < 3; ++d) c[d] += mesh.nodes[el[i]][d] / 8.0;
      r.maxVonMisesLocation = c;
    }
  }
  r.maxDisplacement = 0;
  for (int i = 0; i < nNodes; ++i) {
    double m = std::sqrt(x[3*i]*x[3*i] + x[3*i+1]*x[3*i+1] + x[3*i+2]*x[3*i+2]);
    if (m > r.maxDisplacement) {
      r.maxDisplacement = m;
      r.maxDisplacementNode = i;
      r.maxDisplacementLocation = mesh.nodes[i];
    }
  }
  return r;
}

// ---- thermal -------------------------------------------------------------------------
ThermalResult solveThermal(CCGeomShape* shape, const VoxelMesh& mesh,
                           const Material& mat,
                           const std::vector<TempFix>& tempFixes,
                           const std::vector<HeatFlux>& fluxes,
                           const std::vector<Convection>& convection) {
  if (!(mat.k > 0))
    throw Error{2001, "INVALID_PARAM",
                "material '" + mat.name + "' has no thermal conductivity "
                "(k must be > 0 for a thermal run)."};
  const int nNodes = (int)mesh.nodes.size();
  // Dirichlet nodes.
  std::map<int, double> dirichlet;
  for (const auto& tf : tempFixes) {
    auto ns = nodesOnFace(shape, mesh, tf.face);
    if (ns.empty())
      throw Error{2001, "INVALID_PARAM",
                  "temperature face " + std::to_string(tf.face) + " maps "
                  "to no mesh nodes — refine the mesh or pick another face."};
    for (int nd : ns) dirichlet[nd] = tf.tempC;
  }
  if (dirichlet.empty())
    throw Error{4003, "SIM_SINGULAR",
                "thermal: no temperature is fixed anywhere ('sim fix "
                "temp @face <n> <degC>') — the temperature field would "
                "only be defined up to a constant."};
  std::vector<char> fixed(nNodes, 0);
  std::vector<double> x(nNodes, 0.0);
  for (auto& kv : dirichlet) { fixed[kv.first] = 1; x[kv.first] = kv.second; }
  std::vector<double> rhs(nNodes, 0.0);
  // Assemble conductivity (k converted W/(m K) -> W/(mm K)).
  double Ke[8][8];
  hex8KeThermal(mesh.h, mat.k / 1000.0, Ke);
  Csr A = assemble<1>(mesh, &Ke[0][0]);
  // Neumann / Robin terms.
  for (const auto& hf : fluxes) {
    auto ns = nodesOnFace(shape, mesh, hf.face);
    if (ns.empty())
      throw Error{2001, "INVALID_PARAM",
                  "heatflux face " + std::to_string(hf.face) + " maps to "
                  "no mesh nodes — refine the mesh or pick another face."};
    double area = geomCall("face area", [&](int* e) {
      return ccgeom_face_area(shape, hf.face, e);
    });
    double per = hf.q * area / (double)ns.size();  // W per node
    for (int nd : ns) rhs[nd] += per;
  }
  for (const auto& cv : convection) {
    auto ns = nodesOnFace(shape, mesh, cv.face);
    if (ns.empty())
      throw Error{2001, "INVALID_PARAM",
                  "convection face " + std::to_string(cv.face) + " maps "
                  "to no mesh nodes — refine the mesh or pick another face."};
    double area = geomCall("face area", [&](int* e) {
      return ccgeom_face_area(shape, cv.face, e);
    });
    double aNode = area / (double)ns.size();
    for (int nd : ns) {
      // Robin term: h*A on the diagonal, h*A*T_amb on the RHS. The
      // diagonal of a CSR row is added in place via diagIdx.
      A.val[A.diagIdx[nd]] += cv.hCoeff * aNode;
      rhs[nd] += cv.hCoeff * aNode * cv.tAmb;
    }
  }
  PcgOutcome oc = pcgSolve(A, rhs, fixed, x, "thermal");
  ThermalResult r;
  r.material = mat;
  r.mesh = mesh;
  r.temperature = x;
  r.pcgIterations = oc.iterations;
  r.pcgRelResidual = oc.relResidual;
  r.minTemp = r.maxTemp = x.empty() ? 0 : x[0];
  for (double t : x) { r.minTemp = std::min(r.minTemp, t); r.maxTemp = std::max(r.maxTemp, t); }
  r.elementTemperature.assign(mesh.elements.size(), 0.0);
  for (size_t ei = 0; ei < mesh.elements.size(); ++ei) {
    double s = 0;
    for (int i = 0; i < 8; ++i) s += x[mesh.elements[ei][i]];
    r.elementTemperature[ei] = s / 8.0;
  }
  return r;
}

// ---- field writers ---------------------------------------------------------------------
namespace {
void putU32(std::FILE* f, unsigned v) {
  unsigned char b[4] = {(unsigned char)(v & 0xff), (unsigned char)((v >> 8) & 0xff),
                        (unsigned char)((v >> 16) & 0xff), (unsigned char)((v >> 24) & 0xff)};
  std::fwrite(b, 1, 4, f);
}
void putF64(std::FILE* f, double v) { std::fwrite(&v, 8, 1, f); }
void putF32(std::FILE* f, float v) { std::fwrite(&v, 4, 1, f); }
}  // namespace

bool writeFieldFile(const std::string& path, FieldKind kind,
                    const VoxelMesh& mesh, const std::vector<double>& values,
                    std::string* errOut) {
  if (values.size() != mesh.elements.size()) {
    if (errOut) *errOut = "field value count does not match element count";
    return false;
  }
  std::FILE* f = std::fopen(path.c_str(), "wb");
  if (!f) { if (errOut) *errOut = "cannot open '" + path + "' for writing"; return false; }
  double mn = values.empty() ? 0 : values[0], mx = mn;
  for (double v : values) { mn = std::min(mn, v); mx = std::max(mx, v); }
  const char* unit = kind == FieldKind::VonMises ? "MPa"
                     : kind == FieldKind::Temperature ? "degC" : "mm";
  std::fwrite("CCSF", 1, 4, f);
  putU32(f, 1);
  putU32(f, (unsigned)kind);
  putU32(f, (unsigned)std::strlen(unit));
  std::fwrite(unit, 1, std::strlen(unit), f);
  putF64(f, mn);
  putF64(f, mx);
  putU32(f, (unsigned)mesh.nodes.size());
  putU32(f, (unsigned)mesh.elements.size());
  for (const auto& p : mesh.nodes)
    for (int d = 0; d < 3; ++d) putF32(f, (float)p[d]);
  for (const auto& el : mesh.elements)
    for (int i = 0; i < 8; ++i) putU32(f, (unsigned)el[i]);
  for (double v : values) putF64(f, v);
  bool ok = std::ferror(f) == 0;
  std::fclose(f);
  if (!ok && errOut) *errOut = "write failed for '" + path + "'";
  return ok;
}

bool writeCsv(const std::string& path, const std::string& valueHeader,
              const VoxelMesh& mesh, const std::vector<double>& values,
              std::string* errOut) {
  if (values.size() != mesh.elements.size()) {
    if (errOut) *errOut = "value count does not match element count";
    return false;
  }
  std::FILE* f = std::fopen(path.c_str(), "w");
  if (!f) { if (errOut) *errOut = "cannot open '" + path + "' for writing"; return false; }
  std::fprintf(f, "element,cx,cy,cz,%s\n", valueHeader.c_str());
  for (size_t ei = 0; ei < mesh.elements.size(); ++ei) {
    std::array<double, 3> c{{0, 0, 0}};
    for (int i = 0; i < 8; ++i)
      for (int d = 0; d < 3; ++d) c[d] += mesh.nodes[mesh.elements[ei][i]][d] / 8.0;
    std::fprintf(f, "%zu,%.12g,%.12g,%.12g,%.12g\n", ei, c[0], c[1], c[2],
                 values[ei]);
  }
  bool ok = std::ferror(f) == 0;
  std::fclose(f);
  if (!ok && errOut) *errOut = "write failed for '" + path + "'";
  return ok;
}

}  // namespace ccsim
