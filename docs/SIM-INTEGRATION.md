# Cascade Console — simulation module: integration notes

Status: **host-proven, not yet integrated.** Everything lives in
`simwork/`; nothing in `repo/` or `enginework/` was touched. The
module adds the `sim` command family (linear statics + steady-state
thermal on a voxel hex8 mesh) to the native engine, in the engine's
own style: same error codes (unified table), same result-string
conventions, same three-backend split (direct OCCT / CascadeKit
`mc_*` adapter / analytic mock for host tests).

## Host proof (all numbers measured, this machine)

`./build_sim.sh` builds the same 35-check suite against the mock
backend and against real OCCT geometry, and compile-checks the
`mc_*` adapter. Results (`results/sim_results_*.json`):

| Case | Result | Reference |
|---|---|---|
| Cantilever 100×10×10 steel, 100 N tip, h=2.5 (640 el) | tip **0.192979 mm**, err **3.51%** | Euler–Bernoulli 0.2000 mm |
| Same, h=1.25 (5,120 el) | tip **0.198233 mm**, err **0.88%** | improves under refinement ✓ |
| Max von Mises, coarse / fine | 41.58 / 49.79 MPa (element-centroid values) | outer-fibre analytic 60 MPa — centroid values converge upward, never scaled |
| Pressure 0.1 MPa on top face (= UDL) | tip **0.072974 mm**, err **2.70%** | wL⁴/8EI = 0.075 mm |
| Thermal bar 100 °C → 0 °C | midpoint **50 °C**, deviation **6.8e-13 °C**; max profile deviation 7.1e-13 °C | exact linear profile |
| Thermal, flux but no fixed temperature | **E4003 SIM_SINGULAR** | required behaviour |
| Statics, zero fixed DOFs (solver level) | **E4003 SIM_SINGULAR** (rigid-body-mode check) | required behaviour |
| `sim run` with no material / no fixity | **E4001 / E4002** | unified error table |
| `sim modal`, `sim mesh engine tet` | **E5002 NOT_IMPLEMENTED** | honest, by design |

Both backends pass **35/35**, with identical numbers on the box
cases; the suite also passes against system OCCT 7.6.3
(`CC_OCCT_PREFIX=/usr ./build_sim.sh`). The coarse/fine deflections
match the design docs' Python stand-in (0.1930 / 0.1982 mm) to four
significant figures — independent implementations, same formulation.

Non-box proof (OCCT backend only, `tests/probe_cylinder.cpp`,
output in `results/probe_cylinder_output.txt`): vertical cylinder
r=5 × 100 mm cantilever, 100 N sideways at the top — tip mean
displacement **0.3391 mm** vs Euler–Bernoulli **0.3395 mm**, with
the voxel volume drift (−4.51%) reported in the run output, not
hidden.

## Files to add

Into the engine tree (`Apps/*/…/Core/native/`, wherever
`cc_interpreter.cpp` / `ccgeom_*` land at integration):

| File | Role |
|---|---|
| `include/ccsim.h` | Public sim API: materials, mesh, solvers, field export, session `State`, `execute()` entry, `Host` interface |
| `include/ccsim_backend.h` | Four backend extension functions (point-inside, point↔face distance, face area, face point+normal) |
| `src/ccsim.cpp` | Materials table, voxel mesher, hex8 assembly, masked PCG, rigid-body-mode singularity check, statics + thermal solvers, CCSF/CSV writers |
| `src/ccsim_commands.cpp` | The `sim` grammar, run/result formatting |
| `src/ccsim_backend_occt.cpp` | Direct-OCCT backend extension (host/dev reference) |
| `src/ccsim_backend_mc.cpp` | Device backend extension over `mc_*` |
| `src/ccsim_backend_mock.cpp` | Host-test double extension (never shipped) |
| `tests/test_sim.cpp`, `build_sim.sh` | Host proof (keep with the engine's tests) |

One merge is required in `ccsim_backend_occt.cpp`: it needs the
`TopoDS_Shape` inside the engine's `CCGeomShape`, whose struct is
defined inside `ccgeom_occt.cpp`. The sim file currently mirrors
that one-member struct so it can build standalone (the mirror is
commented as such). At integration, either move these four
functions into `ccgeom_occt.cpp` or extract the struct into a
shared internal header and delete the mirror. Merging into the
same translation unit also fixes error-message flow: the backend
error strings then land in the same `ccgeom_last_error()` storage
the engine uses (in the standalone build the sim layer falls back
to a generic message when that storage is empty; codes are
unaffected).

## Interpreter registration (described, not applied)

In `cc_interpreter.cpp`'s `CCSession`:

1. Add a member `ccsim::State sim;` (sim state is session state,
   like the shape registry).
2. Add a small adapter implementing `ccsim::Host`:
   `object(name)` → `CCSession::object(name)` (already throws the
   unified `CCError{1005,…}` — `ccsim::Error` has the same
   {code, name, message} shape, so catch-and-rethrow is mechanical);
   `num(token)` → the existing `CCSession::num()` (handles `$vars`).
3. In `execute()`'s dispatch if-chain, add one branch beside the
   other command families:
   `if (cmd == "sim") { out = ccsim::execute(session.sim, hostAdapter, args-after-"sim"); goto done; }`
   with `ccsim::Error` caught by the same handler as `CCError`.
4. Do **NOT** add `sim` to `mutatingCommands()` and do **not**
   snapshot sim state: sim setup/results are analysis state, not
   model state. Changing a shape does not clear sim state; the
   per-object setup is keyed by object name and results are
   invalidated whenever that object's material/BCs change (handled
   inside `ccsim_commands.cpp`). If the object is deleted or
   redefined, a stale setup simply re-meshes the current shape on
   the next `sim run` — acceptable, and worth a line in the user
   guide.
5. Help: append the sim block (the `kUsage` text in
   `ccsim_commands.cpp` is the source) to `kHelpLines` under a
   `sim …` heading, and register `sim` in the catalog as
   app-layer/native (it is not an OCCT command).

Swift side: no changes are needed for the text path — `sim`
results come back through the same `CCResult` text channel as
every other command. The console prints the run summary (mesh
stats + drift warning, PCG line, max displacement + location, max
von Mises + location, safety factor labelled as a linear estimate,
mesh mass) exactly as `ccsim_commands.cpp` formats it.

## Command list (as implemented)

```
sim material list
sim material show <name>
sim material custom <name> <E MPa> <nu> <rho kg/m^3> <k W/(m K)> <yield MPa>
sim material <object> <name>        assign (makes <object> the active sim object)
sim material <name>                 assign to the active object
sim select <object>
sim fix <object> @face <n>                      clamp a face (statics)
sim fix temp <object> @face <n> <degC>          hold a face at a temperature
sim load <object> @face <n> force <fx> <fy> <fz>   total N, spread over the face's nodes
sim load <object> @face <n> pressure <MPa>         inward normal, area from the true face
sim load <object> @face <n> heatflux <W/mm^2>
sim load <object> @face <n> convection <h W/(mm^2 K)> <amb degC>
sim mesh size <mm>                  voxel size (default 2.5)
sim mesh engine hex                 (tet -> E5002, see TetGen note)
sim thermal | sim static            choose what `sim run` solves
sim run [<object>]
sim results                         reprint the last run summaries
sim results view vonmises|temperature|displacement [<path>]   write a CCSF field file
sim results export <path.csv>       per-element values, full precision
sim clear [<object>]                drop an object's sim setup + results
sim modal / transient / fatigue / cfd / buckling / contact    -> E5002 NOT_IMPLEMENTED
```

Face indices are the shared census indices (0-based), the same
ones `faces` / `@face` selection use elsewhere. Built-in materials
(typical published values, labelled as such in output): steel,
stainless-304, aluminium-6061, aluminium-7075, titanium-6al4v,
brass, copper, pla, abs, petg — each with E, ν, ρ, k, yield as
data in `ccsim.cpp`.

## Field data format (CCSF) — viewer colouring

`sim results view …` writes a binary field file for the viewer.
It deliberately mirrors the CCM1 view-data conventions
(little-endian, Z-up, mm, Float32 node positions) so the Swift
viewer can parse it with the same reader discipline:

```
char[4]  "CCSF"
u32      version = 1
u32      fieldKind: 1 = vonMises, 2 = temperature, 3 = displacement
u32      unit length, then unit bytes: "MPa" | "degC" | "mm"
f64      trueMin — the solver's exact minimum over the elements
f64      trueMax — the solver's exact maximum
u32      nodeCount, u32 elementCount
f32      node positions, 3 per node (x, y, z), mesh order
u32      element node indices, 8 per element (hex8, mesh order)
f64      one value per element, mesh order
```

Values: von Mises = per-element centroid value from the solver;
temperature = per-element mean of nodal temperatures;
displacement = per-element mean of nodal |u|. **The colour scale
is the header's trueMin/trueMax — the solver's genuine range.
Never rescale, clip or gamma it** (standing project rule).

Swift display notes:
- Results text: show the run summary verbatim as a monospaced
  block under the command echo — it is already formatted as a
  small table (mesh / PCG / max disp / max VM / safety / mass).
- Colouring option A (simplest, exact): render the CCSF voxel
  mesh itself as coloured boxes/hex faces using the per-element
  values — the mesh in the file IS the analysis mesh, so the
  picture is honest about resolution.
- Colouring option B (prettier): keep the BRep tessellation
  (CCM1) on screen and colour each BRep triangle by the value of
  the voxel element whose centre is nearest the triangle's
  centroid. This is a display sampling of the same data; the
  legend must still show the CCSF header's true min–max.
- Either way the legend shows min/max with the unit from the
  header, and the field name. Displacement colouring is magnitude
  |u| (state that in the legend); the text summary carries the
  signed detail via the max-displacement location.

## TetGen note

The tet path stays **NOT_IMPLEMENTED** (`sim mesh engine tet`
returns E5002 with a message saying why). TetGen is AGPL v3; the
user's licence decision is still pending, so **no TetGen code is
included, linked or fetched** anywhere in this module. The voxel
hex path is the shipped engine — it is also the formulation the
cascade-port façade §11 solver uses (voxel hex8, PCG, face-mapped
BCs), so the app and the façade stay consistent. If the user
later approves TetGen, the integration point is a second mesh
backend behind `buildMesh`'s interface; nothing in the command
layer changes.

## Relation to the cascade-port façade §11

The façade already contains a device-proven voxel FEM
(`mc_fem_mesh/solve/result_*`) with the same caps (250,000
elements, 8 M-cell scan, PCG rel. tol 1e-8, 0.75×voxel face
mapping). This module implements the same formulation natively in
the engine (the engine cannot call the façade's self-contained
mesh/solver from a named-shape session without duplicating its
mesh ownership). Two deliberate differences, both documented in
the code:

1. **Boundary classification.** `mc_contains` reports boundary
   points as OUTSIDE; `ccgeom_point_inside` counts ON as inside.
   On device (mc backend) a voxel centre landing exactly on a
   face is dropped; the mesh-volume drift line in the run output
   makes the effect visible. Prefer mesh sizes that do not put
   centres exactly on faces for grid-aligned parts.
2. **Assembly.** The façade assembles into a preallocated block
   CSR from its regular grid; this module assembles per-row with
   dedup, which is simpler but slower at the 250 k-element cap.
   If device profiling shows assembly dominating, port the
   façade's block-CSR assembly behind the same interface — the
   solver and results do not change.

Two small façade additions are proposed (facade style, one wrap
each) to remove the mc backend's documented limitations:

- `mc_point_face_distance(shape, face, x, y, z, &dist, &err)` —
  `BRepExtrema_DistShapeShape` between the face and a vertex;
  gives the mc backend exact trimmed-face distances for
  non-planar faces too (today it uses exact point-to-plane
  distance for planar faces — a lower bound — and refuses
  non-planar faces loudly).
- `mc_face_point_normal(shape, face, pointOut, normalOut, &err)`
  — `BRepAdaptor_Surface` D1 at mid-UV with orientation flip;
  lets pressure loads work on non-planar faces on device (today
  they fail loudly with CCGEOM_ERR_OCCT).

## Error mapping (already in the unified table)

- E4001 `SIM_NO_MATERIAL` — `sim run` with no material assigned.
- E4002 `SIM_NO_FIXITY` — statics run with no fixed face.
- E4003 `SIM_SINGULAR` — rigid-body mode survives the fixity
  (energy check before the solve), PCG breakdown, zero free
  diagonal, or a thermal run with no temperature fixed anywhere.
- E4004 `SIM_NO_CONVERGE` — PCG iteration cap (10,000).
- `CC-SIM-005` — warning only (printed, not an error): mesh
  volume drift over 10%.
- E5002 — modal/transient/fatigue/cfd/buckling/contact and the
  tet mesh engine.
- E2001/E2003/E1002/E1003/E1004/E1005/E1006/E3003 — reused from
  the shared ranges for bad parameters, empty meshes, unknown
  commands, arity, bad numbers, unknown names/materials,
  duplicate custom-material names and export failures.

## Licence notes

- The sim module is the project's own code (materials data are
  typical published values). No OCCT source is modified or
  copied; the OCCT backend calls public OCCT APIs, the mc backend
  calls the project's own façade. The OCCT LGPL 2.1 + exception
  texts already ship with the app and cover this use the same way
  they cover the engine.
- TetGen (AGPL v3) is **not** included — see the TetGen note.
- The analytic mock backend is a host-test double and must not
  ship, same rule as the engine's mock.

## Honest gaps

- No device run yet: the mc adapter is compile-checked only;
  CascadeKit linking + on-device numbers are a CI/device step,
  same as the engine's v0.2 path.
- Hex8 elements with ν → 0.5 (rubbers) will lock; no B-bar /
  mixed formulation. Materials with ν ≥ 0.49 should be treated
  as indicative only.
- Von Mises is the per-element centroid value — coarse meshes
  under-report surface peaks (the run output says so). Nodal
  averaging / surface recovery is a later refinement, not in
  this pass.
- Pressure on non-planar faces works with the OCCT backend
  (mid-UV normal); on the mc backend it fails loudly until the
  proposed `mc_face_point_normal` lands.
- Loads landing on fixed-face nodes are reacted there (the
  façade §11 semantics); the pressure-UDL test quantifies the
  effect at ~2.7% for the beam case.
- Thermal expansion / coupled thermo-mechanics, transient,
  modal, fatigue, CFD: NOT_IMPLEMENTED, honestly, per the
  design docs.
