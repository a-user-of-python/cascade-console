# Cascade Console — Modern-CAD Extras (non-modeling features)

Agent 6 deliverable, 2026-11-23. Scope: everything a modern CAD has *around*
modeling — simulation, analysis queries, project files, materials/appearance,
rendering/export, print checks, accessibility. Every feature below states
(a) the console commands that expose it, (b) how it is actually implemented,
(c) its honest status/limits. Nothing here is vaporware dressed up: items are
labelled **PROVEN** (prototype run on this host, numbers in `results/`),
**EXISTS** (already implemented in the proven cascade-port façade the app is
built on), **DESIGN** (specified here, not yet built), or **LIMIT** (a real
boundary the user guide must state).

Conventions: units are mm / N / MPa / s / °C everywhere (the façade's units).
Object names are the console's named shapes (`box1`, `shaft`, …). Face
references use the façade's census index space (`@face 12`), shared with
selection, tessellation and FEM face mapping — one index space, no parallel
numbering.

---

## 1. Simulation

### 1.0 The honest headline

**OCCT contains no FEM solver.** It supplies geometry: solid classification,
triangulation (`BRepMesh`), distance/classification queries, mass properties.
The solver is our own code standing on OCCT geometry — exactly how the proven
cascade-port façade already does it (its §11 FEM section, shipped and
device-verified in MetalCAD). Cascade Console inherits that solver core and
extends it. Simulation results are true solver output at true scale or the
command fails with an error code — never a coloured picture with invented
numbers (standing rule: no fake results).

### 1.1 Linear-static stress analysis — EXISTS (core) + DESIGN (tet path)

**Commands**

```
sim material steel                      # or: sim material set shaft aluminium-6061
sim fix @face 3                         # clamp all DOF on a face (repeatable)
sim fix shaft @face 0
sim load @face 7 force 0 0 -500         # total force N on the face, spread over its nodes
sim load @face 7 pressure 2.5           # MPa over the face -> nodal forces by area share
sim mesh size 2.0                       # voxel size (hex path) / target edge (tet path)
sim mesh engine tet                     # DESIGN path, see below; default: hex
sim run                                 # -> SIM result object, error code on failure
sim results                             # max von Mises, max displacement, PCG iters, residual
sim results view vonmises               # colour the viewer mesh by per-element von Mises
sim results view displacement 10        # deformed view at TRUE scale x10, labelled as x10
sim results export results.csv          # per-element table, no rounding games
```

**Implementation — hex path (EXISTS).** Uniform voxel grid over the bounding
box; a cell is kept when its centre classifies inside the solid
(`BRepClass3d_SolidClassifier`); kept cells are hex8 trilinear elements, full
2×2×2 Gauss integration, isotropic linear elasticity; one stiffness matrix
serves the whole mesh (all elements are identical cubes — exact, not a
shortcut); CSR assembly; PCG solve, Jacobi preconditioner, relative residual
tolerance 1e-8, cap 10 000 iterations; element cap 250 000
(`MC_FEM_MAX_ELEMENTS`) so an over-fine request fails fast with
`MC_ERR_INVALID_ARG` instead of running forever. Fixity/loads are defined on
BRep faces and mapped to mesh surface nodes by point-to-face distance
(`BRepExtrema`, < 0.75 × voxel). Under-constrained models fail with
`MC_ERR_FEM_SINGULAR`, never a garbage result. Every run prints mesh volume
vs. true solid volume (`BRepGProp`): drift is the thin-feature warning,
because stair-stepped voxel boundaries can erase features thinner than the
voxel — the user sees the number, not a footnote.

**Verified on this host (PROTOTYPE of the same formulation, Python).**
`prototypes/fem_prototype.py`, steel cantilever 100×10×10 mm, 100 N tip load:

| Check | FEM | Closed-form | Error |
|---|---|---|---|
| Tip deflection, voxel 2.5 mm (640 el) | 0.1930 mm | 0.2000 mm (Euler–Bernoulli) | 3.51 % |
| Tip deflection, voxel 1.25 mm (5 120 el) | 0.1982 mm | 0.2000 mm | 0.88 % |
| Max von Mises (element centroid) | 41.6 MPa | 60.0 MPa outer-fibre analytic | see note |
| Thermal midpoint (see §1.3) | 50.000000000000 °C | 50 °C | ~1e-13 °C max dev |
| First bending frequency (see §1.4) | 827.7 Hz | 815.4 Hz | 1.52 % |

The von Mises row needs its note, and the app must print the equivalent note
with coarse-mesh results: the FEM number is the *centroid* value of the
outermost root element, whose centroid sits 3.75 mm from the neutral axis vs.
5 mm at the outer fibre (bending-only estimate ≈ 45 MPa); 41.6 MPa is the
true centroid output of that mesh, reported as-is, not scaled up to look
right. Convergence behaves as theory says: halving the voxel cut the
deflection error from 3.51 % to 0.88 %.

**Implementation — tet path (DESIGN, the upgrade the brief asks for).**
1. Surface mesh: `BRepMesh_IncrementalMesh` on the solid (deflection +
   angular parameters from `sim mesh` settings).
2. Volume mesh: tetrahedralise the closed surface triangulation. OCCT has
   **no** volume tet mesher — options, in preference order: (a) TetGen
   (AGPL v3 — used the same way in the FEBio project; licence must ship and
   the tet feature is labelled AGPL in About), (b) a constrained-Delaunay
   implementation of our own (large work, later milestone). Until one lands,
   `sim mesh engine tet` must answer with a distinct error
   (`CC_ERR_NOT_IMPLEMENTED`, §QA error scheme) — never silently fall back
   to hex while claiming tet.
3. Element: tet4 (linear, one Gauss point) at first; tet10 is a later
   upgrade and must not be claimed before it exists. Same assembly/PCG core,
   same face-mapping for BCs, same result objects — the viewer colouring and
   CSV export are shared with the hex path.
4. Acceptance gate for shipping the tet path: the same cantilever suite as
   the prototype (deflection within 2 % of Euler–Bernoulli at the reference
   mesh, thermal exact, f1 within 2 %), run in CI on the host build.

**Limits (state in the guide):** linear statics, small displacements,
isotropic materials only. No contact, no plasticity, no buckling, no
large-deformation. Voxel boundaries are stair-stepped (hex path). A result
is only as good as its mesh — the app always reports element count, mesh
volume drift, PCG iterations and final residual alongside the headline
numbers so the user can judge.

### 1.2 Materials library (for simulation + mass)

**Commands:** `material list`, `material show steel`,
`material assign <object> <material>`, `material custom <name> E .. nu .. density .. k ..`
**Implementation:** a JSON library shipped with the app (name, E MPa, ν,
density kg/m³, thermal conductivity W/m·K, yield MPa — yield is *reference
data for the safety-factor readout*, clearly labelled as typical published
values, editable by the user). Starter set: steel (mild, S355), stainless
304, aluminium 6061-T6 / 7075, titanium Ti-6Al-4V, brass, copper, PLA, ABS,
PETG, nylon PA6, oak (orthotropic warning: solver treats as isotropic with
the along-grain E — the assign command prints that warning). Custom materials
live in the project file (§3) so a project is self-contained.
`sim results` also prints `safety factor = yield / max von Mises` when the
material has a yield value, labelled as a linear-static estimate.

### 1.3 Thermal analysis — DESIGN on the proven formulation (prototype verified)

**Commands:** `sim thermal`, `sim fix temp @face 3 100` (Dirichlet °C),
`sim load heatflux @face 7 0.5` (W/mm²), `sim load convection @face 7 h=0.01 amb=20`,
`sim run`, `sim results view temperature`.
**Implementation:** steady-state conduction only (no transient in v1 — say
so). Scalar Laplace problem on the *same* mesh as statics (hex voxels first,
tet when it lands): hex8 conductivity element from the material's k,
Dirichlet faces via the same face→node mapping, heat-flux faces as nodal
sources, convection as a Robin term (h·A diagonal + h·A·T_amb RHS). Solved
with the same PCG core. Prototype (same script as §1.1): beam with 100 °C /
0 °C end faces reproduces the exact linear field — midpoint 50.000000000000 °C,
max deviation from linear 7.7e-13 °C. That is the acceptance test for the
shipped thermal path too.
**Limits:** steady-state, constant k, no radiation, no thermal expansion /
thermo-mechanical coupling in v1.

### 1.4 Modal analysis — DESIGN on the proven formulation (prototype verified)

**Commands:** `sim modal modes 6`, `sim results view mode 2` (animated
deflection in the viewer, amplitude labelled as arbitrary/normalised —
mode shapes have no physical amplitude and the UI must say so).
**Implementation:** same stiffness assembly + lumped mass matrix
(element mass / 8 per node, consistent with the hex8 formulation), smallest
eigenvalues by shift-invert Lanczos (`eigsh`-equivalent in the native core:
LOBPCG or Lanczos on the PCG-preconditioned operator). Fixed faces = the
`sim fix` set. Prototype: first six frequencies of the cantilever computed;
f1 = 827.7 Hz vs. 815.4 Hz analytic (1.52 %); the first two roots are the
degenerate y/z bending pair a square cross-section must produce — a good
sanity signature the CI test asserts. **Limits:** undamped, linear, lumped
mass; frequencies only as good as the mesh (same drift reporting).

### 1.5 What simulation deliberately is not (v1)

No CFD, no transient dynamics, no fatigue life prediction, no topology
optimisation. Each gets `CC_ERR_NOT_IMPLEMENTED` if typed, not a stub
result. (The command catalog reserves the names so scripts fail loudly
instead of silently doing nothing.)

---

## 2. Analysis queries (OCCT-native, exact — not simulation)

### 2.1 Mass properties — PROVEN

`measure <object>` / `measure mass <object>` → volume, surface area,
centre of gravity, inertia matrix, and mass once a material is assigned.
Implementation: `BRepGProp.VolumeProperties / SurfaceProperties` on the
BRep solid (the same calls MetalCAD uses). Prototype P2
(`prototypes/occt_extras_prototype.py`, OCCT 7.8.1.1): 40×20×10 box —
volume 8000.000000 mm³ (error 2.3e-14 %), CoG exact, inertia diagonal
333 333.33 / 1 133 333.33 / 1 333 333.33 mm⁵·(unit density) exact,
surface area 2800 mm² exact. Also `measure distance <a> <b>`,
`measure angle`, `measure radius @face n` — direct OCCT queries.

### 2.2 Interference / clearance — PROVEN

`check interference <a> <b>` → common volume (`BRepAlgoAPI_Common` +
`BRepGProp`); > 0 means the solids overlap, and the overlap solid itself is
kept as `__interference` so `view __interference` shows *where*.
`check clearance <a> <b>` → minimum distance (`BRepExtrema_DistShapeShape`)
plus the witness points. `check clearance all 0.5` → every pair under
0.5 mm, table output. Prototype P2: overlapping boxes → common volume
2000.000000 mm³ (analytic 2000); boxes with a 10 mm gap → min distance
exactly 10.0 mm, common volume 0. **Limit:** boolean common on coincident-
face pairs can be slow/fragile in OCCT — the command runs it on a worker
queue with progress + cancel, and a boolean failure returns
`MC_ERR_OCCT` with words, never a silent "no interference".

### 2.3 Cross-section analysis — PROVEN (method), DESIGN (polish)

`section <object> plane z 12` → creates the section as a named face object:
area, perimeter, centroid, second moments of the section (the numbers a
beam/stress hand-calc needs). Implementation: `BRepAlgoAPI_Section` for the
edges → wire → face, then `BRepGProp` on the face; a `section sweep
<object> z 0 30 2` variant tables area vs. position (finds the weakest
section). Prototype P2 measured the area by the independent slab method
(common with a 0.002 mm slab / thickness): cylinder r10 at z=12 →
314.15926536 mm² vs. π·10² (error 3.3e-11 %). The shipped command uses the
section-face route; the slab route stays as the CI cross-check.

### 2.4 Draft check — PROVEN (primitive), DESIGN (full report)

`check draft <object> dir 0 0 1 min 2` → per-face draft angle vs. the pull
direction, faces under the minimum listed and coloured in the viewer.
Implementation: face normal at face centre (`BRepGProp_Face.Normal`, the
exact call the prototype uses) — draft = 90° − angle(normal, pull dir);
for curved faces, sample a UV grid and report the *minimum* draft on the
face (a single centre sample can lie on a cone/cylinder — the report says
which faces are sampled vs. planar-exact). Prototype P2: cone with
(10−6)/20 taper → 11.30993247°, matching atan(0.2) to all printed digits.

### 2.5 Curvature check — DESIGN, with an OCCT limit stated

`check curvature <object>` → per-face type census first (plane / cylinder /
cone / sphere / torus / freeform, from `BRepAdaptor_Surface`), then for
cylinders/spheres/tori the exact radius; for freeform faces, min/max
principal curvature sampled on a UV grid via `BRepLProp_SLProps` — labelled
*sampled*, with the grid density printed. OCCT gives exact curvature only
through surface evaluation; there is no closed-form "min radius of this
solid" query, and the guide must not pretend otherwise. Primary use:
`check curvature <object> minradius 1.5` flags faces/fillets under a tool
or print radius.

### 2.6 Shape health

`check shape <object>` → `BRepCheck_Analyzer` validity, closed-shell and
solid census, free-edge count, plus `ShapeFix` offered as
`repair shape <object>` (creates a *new* object; the original is never
mutated silently — console philosophy: commands that change geometry say
so and keep the source).

---

## 3. Project files, autosave, crash recovery, script history

**Commands:** `project new/open/save/saveas`, `project info`,
`history`, `history show 14`, `history replay 14`, `undo`/`redo` (script-level).

**Implementation.**
- Project = one folder-as-file (`.ccproj`, a zip): `model.brep` (OCCT
  native BRep — lossless, no mesh approximation), `script.cascade` (the
  full command history that built the model — the project *is* its script),
  `project.json` (materials incl. customs, appearances, sim setups,
  settings snapshot, app + OCCT version strings), `thumbnails/` (last
  viewer render, for the file browser).
- Because the script is saved, "version history" is intrinsic: every
  executed command is appended with a timestamp and a monotonically
  increasing revision number; `history replay n` rebuilds the model by
  replaying commands 1..n into a scratch document (the live model is not
  touched until `history adopt n`). Replay determinism is a CI test:
  replaying a project's script must reproduce its saved BRep volume/area
  to 1e-9 relative.
- Autosave: after every successful mutating command, the script journal is
  appended and flushed (fsync) — the journal *is* the autosave; the BRep
  is re-checkpointed every 25 commands and on backgrounding (iPad) /
  window close (Mac). Cost is trivial because the journal is text.
- Crash recovery: on launch, if a journal exists with no clean-close
  marker, the app offers **Recover** (replays the journal into a recovered
  project, named `… (recovered)`) vs. **Discard** — never auto-overwrites
  the last saved project. A `CC_RECOVERY` log line records which path was
  taken. The recovery offer is part of the first-launch checklist (QA.md).
- Import/export of geometry stays the modeling agents' commands
  (STEP/IGES/STL/BRep); extras own only the project container.

---

## 4. Materials & appearance library

**Commands:** `appearance <object> <name>` (e.g. `brushed-alu`, `red-gloss`),
`appearance <object> color #RRGGBB`, `appearance <object> metalness 0.9 roughness 0.35`,
`appearance list/show`, transparency via `appearance <object> opacity 0.5`.
**Implementation:** appearance is *display-only* data (name, base colour,
metalness, roughness, opacity) stored per-object in `project.json` — it
never touches the BRep. The viewer agent maps it onto the Metal material;
the renderer/screenshot path (§5) uses the same values so a screenshot
matches the live view. Physical material (§1.2) and appearance are
deliberately separate concepts with separate commands — assigning "steel"
the material must not silently repaint the part, and the guide says so.
Starter appearances mirror the physical library names where sensible plus
pure-display ones (glass-clear, carbon, safety-orange…). Both libraries
are user-extensible JSON in the project, and app-level defaults in Settings.

---

## 5. Rendering & screenshot export

**Commands:** `render` (re-render the 3D view), `view screenshot out.png [width height]`,
`view screenshot transparent`, `render turntable out.mp4` — **LIMIT:**
video export is DESIGN/later; v1 screenshots are PNG only and `render
turntable` returns `CC_ERR_NOT_IMPLEMENTED` rather than pretending.
**Implementation:** screenshots render the viewer's exact scene (same
tessellation, same appearances, same section/sim colouring state) offscreen
at the requested pixel size — what you see is literally what you get,
including von Mises colouring after `sim results view`. Default =
current view size ×2 for print legibility, printed in the log line.
Anti-aliasing = the viewer's own pipeline (no second renderer to drift).

---

## 6. Print / 3D-print export checks

**Commands:** `print check <object>`, run automatically (report only, never
blocking) on every STL export:
- **Watertight:** closed shell + solid census on the BRep (`TopAbs` shell
  closed flag + `BRepCheck`) and, for the exported STL, edge-manifoldness
  of the triangulation. PROVEN method in prototype P3
  (`prototypes/printcheck_prototype.py`, trimesh stand-in for the mesh-side
  check): closed box → watertight `true`; same mesh minus 2 faces → `false`.
- **Wall thickness estimate:** sample points on the surface (the
  triangulation's face centres), distance to the nearest *other* surface
  via `BRepExtrema_DistShapeShape` point-to-shape queries (batched, worker
  queue); report min + 5th-percentile + a viewer heat view. Labelled
  **estimate** everywhere: it is a sampled surface-to-surface distance, not
  an exact medial-axis computation — thin spots *between* samples can be
  missed, and the report prints the sample count so the user can raise it
  (`print check <object> samples 20000`). Prototype P3: hollow box, true
  wall 1.0 mm → estimated min 1.0 mm, median 1.0 mm (12 face-centre samples).
- **Overhang / build volume:** faces whose normal angle to the build plate
  exceeds a setting (default 45°) listed by area %; bounding box vs. the
  selected printer's volume (Settings: printer presets, e.g. 180×180×180)
  with a plain pass/fail. Both are pure OCCT queries on the existing mesh.
- **Units warning:** STL is unitless — export always logs the assumed mm
  scale line (learned the hard way on earlier projects: never silently
  rescale, never assume).

---

## 7. Accessibility & app settings (extras-owned surface)

Settings screen sections (all persisted, all mirrored by console commands
so nothing is mouse-only): 
- **Display:** UI text size follows the system setting (Dynamic Type /
  macOS text size) — respected, never overridden or artificially inflated;
  high-contrast toggle (forces the high-contrast palette in console +
  viewer), reduce-transparency toggle (Liquid Glass falls back to solid
  surfaces — glass is decoration, never the only carrier of meaning),
  colour-blind-safe simulation palette toggle (viridis instead of
  blue-red for von Mises/temperature — the default palette is *also*
  checked so red/green is never the only signal: results always have
  numeric readouts).
- **Console:** font size/family (monospaced), command echo verbosity,
  confirm-before-destructive (default on for `delete`, `project discard`).
- **Accessibility:** full keyboard operation of console + command palette
  on both platforms; VoiceOver labels on every Liquid Glass button (icon
  buttons get text labels, never icon-only meaning); viewer is never the
  only output — every visual result (interference, draft, sim) has a text
  table equivalent, which the console prints automatically.
- **Units & precision:** display decimals setting affects *display only*;
  stored/exported values are always full precision (a wrong-looking
  rounded number must never become a wrong exported number).
- **Privacy:** no accounts, no network features in the app at all —
  stated in Settings > About, true by construction (CI gate in QA.md
  greps the shipped binary for network symbols/endpoints).

---

## 8. Honest limitations summary (for the user guide, verbatim-worthy)

1. OCCT has no FEM solver and no volume tet mesher; simulation is our own
   linear solver on OCCT geometry. Hex/voxel path ships first (proven
   formulation); tet path ships only when it passes the same beam suite.
2. Simulation = linear statics, steady-state thermal, undamped modal.
   Isotropic materials, small displacements. Nothing else is claimed.
3. Von Mises readouts are per-element centroid values; coarse meshes
   under-report peak stress. The app prints mesh data with every result
   and the convergence behaviour is documented (3.51 % → 0.88 % deflection
   error when the voxel halves, on the reference beam).
4. Wall thickness and freeform curvature are sampled estimates, printed
   with their sample counts.
5. Screenshots are PNG; no video export in v1.
6. Appearance is display-only; physical material assignment is separate.

## 9. Prototype inventory (all run 2026-11-23 on this host)

| ID | File | Proves | Result file |
|---|---|---|---|
| P1 | `prototypes/fem_prototype.py` | hex8 statics + thermal + modal vs. closed-form | `results/fem_prototype_results.json` |
| P1b | `prototypes/convergence.py` | mesh convergence of tip deflection | `results/convergence_results.json` |
| P2 | `prototypes/occt_extras_prototype.py` | mass props, interference, clearance, section area, draft (real OCCT 7.8.1.1) | `results/occt_extras_results.json` |
| P3 | `prototypes/printcheck_prototype.py` | watertight discrimination, wall-thickness estimator core | `results/printcheck_results.json` |

P1/P1b are Python stand-ins for the native solver core (same formulation as
the façade's §11); P2 runs the actual OCCT kernel the app ships.
