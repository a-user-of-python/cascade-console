# Façade API — how Swift calls Open CASCADE in Cascade Console

## Layer 1 (exists — reuse unchanged)

`~/workspace/cascade-port/Facade/occt_facade.h` (783 lines, OCCT
8.0.1). Conventions inherited: mm units, trailing `int* err`,
`mc_last_error()`, caller owns returned handles (`mc_free_shape`,
`mc_free_mesh`), inputs never consumed, one shared face/edge index
space across census/tessellation/finishing. Its sections:

1. handles/errors/lifecycle · 2. primitives (box, cylinder, sphere,
cone, torus) · 3. profiles (prism, revolve, loft, sweep) ·
4. sketches (`mc_face_from_sketch`, `mc_prism_face`) · 5. booleans
(unite, subtract, intersect) · 6. finishing (fillet, chamfer,
chamfer2, shell, draft) · 6b. `mc_transform` · 7. queries (volume,
face area, bbox, edge count, contains) · 8. selection census
(counts, face/edge info, face plane, face colours) · 9. tessellation
(`mc_tessellate`) · 10. STEP import/export (plain, bodies, XDE with
names/colours) · 11. FEM (own voxel mesher + linear-static solver on
OCCT queries — the one non-pass-through section) · 12. `mc_thread`.

Lessons from that port, applied here: (a) the façade computes
nothing of its own — where OCCT has an operation, wrap it, never
approximate it; (b) catch every OCCT exception at the boundary,
nothing crosses the ABI but error codes + a message string;
(c) opaque handles need a *complete* struct definition or Swift's
ClangImporter cannot name the type; (d) selective edge operations
take an index list in the census space, NULL = all edges — no
separate per-selection functions; (e) LGPL texts ship in-tree,
OCCT sources unmodified.

## Layer 2 (new — sketch in `cc_facade.h`, this folder)

The console session API summarised:

| Function | Purpose |
|---|---|
| `cc_session_create / cc_session_destroy` | one session per document window |
| `cc_execute(session, line, &result)` | run one command line; returns 0 or the numeric CC error code |
| `cc_execute_script(session, path, &result)` | run a .ccs/.txt file; `cc_last_error_line()` gives the failing line |
| `cc_last_error_code / _name / _message / _line` | structured error surface for the UI |
| `cc_object_count / cc_object_name / cc_object_stats` | model browser + inspector data |
| `cc_borrow_shape(session, name)` | escape hatch: the layer-1 handle for a named object, so any `mc_*` function — including ones the interpreter hasn't wrapped yet — is reachable. Borrowed, never freed by the caller, invalidated by the next mutating command |
| `cc_view_data / cc_free_view_data` | tessellation buffers (same layout as the prototype's view JSON) for the Metal viewer |
| `cc_undo / cc_redo / cc_history_count` | snapshot-history control |
| `cc_free_string` | frees result strings |

`cc_facade.h` is syntax-checked as both C11 and C++17 (see
TEST_REPORT.md). It is a *sketch*: signatures and ownership are the
design; the implementation is the C++ port of `python/cc/`.

## Command → layer-1 mapping (prototype subset)

| Command | OCCT / layer-1 call |
|---|---|
| box / cylinder / sphere / cone / torus | `BRepPrimAPI_Make*` → `mc_box` etc. |
| profile + extrude | `BRepBuilderAPI_MakePolygon/MakeFace` + `BRepPrimAPI_MakePrism` → `mc_prism` (polygon form) |
| union / cut / intersect | `BRepAlgoAPI_Fuse/Cut/Common` → `mc_unite/mc_subtract/mc_intersect` |
| fillet / chamfer | `BRepFilletAPI_MakeFillet/MakeChamfer` → `mc_fillet/mc_chamfer` |
| translate / rotate | `gp_Trsf` + `BRepBuilderAPI_Transform` → `mc_transform` |
| volume / area / bbox / counts | `BRepGProp` / `BRepBndLib` / census → `mc_volume/mc_face_area/mc_bbox` + section 8 |
| view | `BRepMesh_IncrementalMesh` → `mc_tessellate` |
| export step / stl | `STEPControl_Writer` / `StlAPI_Writer` → `mc_export_step` (+ STL toolkit on device) |

## Version note

Host proof uses OCCT **7.8** (the cadquery-ocp wheel); the device
build uses **8.0.1** (cascade-port). The wrapped operations are
stable APIs across both; analytic results (volumes/areas) agree to
test tolerance. Anything version-sensitive must be re-verified
against the 8.0.1 build, not assumed.
