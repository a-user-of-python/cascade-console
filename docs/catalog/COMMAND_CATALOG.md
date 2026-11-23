# Cascade Console — OCCT Command Catalog

Agent 1 deliverable. Working name: **Cascade Console** — a text-command 3D CAD app for Mac + iPad powered by Open CASCADE Technology (OCCT). Every command below names the **real OCCT class and toolkit** that implements it. Where a command is an app-level loop/convenience over several OCCT calls, or app/viewer state with no OCCT class, it says so in its description — nothing in this catalog is presented as an OCCT feature when it is not one.

Machine-readable twin: `catalog.json` in this folder (fields: `command`, `args`, `occt_class`, `category`, plus `toolkit`, `description`, `example`). Other agents should consume the JSON, not scrape this file.

**Command count: 251** across 16 categories.

## Conventions

- Units: millimetres internally. OCCT itself works in mm; `UnitsAPI`/`UnitsMethods` (TKernel) convert on import/export and for the `units` command. Angles are degrees at the command line, radians inside OCCT (`gp_Trsf`, `Geom_*`).
- Every shape-producing command accepts a trailing `as <name>`; without it, the result replaces the first argument where that is the natural reading (e.g. `fillet body1 ...` edits `body1`), and the console prints the new name, type, volume/area and validity.
- Sub-shape selectors use one shared index space everywhere: `face(4) of body1`, `edge(7) of body1`, `solid(2) of assembly1` — the same indexing as the census in `faces`/`edges`/`solids` (this mirrors the cascade-port façade's shared index space rule).
- Points are `x y z`; a plane is `x y z nx ny nz` (point + normal); an axis is `ax ay az dx dy dz` (point + direction).
- `$var` substitutes a session variable set with `set`.
- Errors: OCCT exceptions (`Standard_Failure` and subclasses) must be caught at the façade boundary and reported with the OCCT error string plus a distinct app error code per command — never a crash, never a silent empty shape. A builder that returns `IsDone()==false` is a failed command, not a result.
- Booleans/features record `BRepTools_History`; `shape-history <name>` exposes generated/modified/deleted sub-shapes (renamed at integration — bare `history` is the session command log; see repo INTEGRATION-NOTES.md).

## OCCT toolkit map (real, OCCT 8.0.1)

OCCT is organised in modules → toolkits (libraries, `TK*`) → packages → classes. This is the full module list in the local reference tree (`~/workspace/cascade-port/OCCT/src/`), which is OCCT **8.0.1**:

| Module | Toolkits | What lives there |
|---|---|---|
| FoundationClasses | TKernel, TKMath | `gp_*` geometry, math solvers, `Precision`, `UnitsAPI`, collections, OSD |
| ModelingData | TKG2d, TKG3d, TKGeomBase, TKBRep | `Geom_*`/`Geom2d_*` curves & surfaces, adaptors, `TopoDS_*` topology, `BRep_Tool` |
| ModelingAlgorithms | TKGeomAlgo, TKTopAlgo, TKPrim, TKBO, TKBool, TKHLR, TKFillet, TKOffset, TKFeat, TKMesh, TKXMesh*, TKShHealing, TKExpress | intersections/projections, BRep builders & `BRepGProp`, primitives, boolean engine, HLR, fillet/chamfer, offset/pipe/loft/thick-solid, local features, tessellation, healing, expression interpreter |
| Visualization | TKService, TKV3d, TKOpenGl*, TKMeshVS | `AIS`/`V3d` viewer, `Graphic3d`. **Cascade Console does NOT use OCCT's OpenGL viewer** — the app renders tessellation in its own Metal viewer; TKService/TKV3d enter only as data-class dependencies of XCAF visual materials |
| ApplicationFramework | TKCDF, TKLCAF, TKCAF, TKBinL, TKXmlL, TKBin, TKXml, TKStdL, TKStd, TKTObj*, TKBinTObj*, TKXmlTObj*, TKVCAF | OCAF documents (`TDocStd`), attributes, undo transactions, binary/XML persistence, XCAF presentation |
| DataExchange | TKXSBase, TKDE, TKDESTEP, TKDEIGES, TKDESTL, TKDEGLTF, TKDEOBJ*, TKDEVRML, TKDEPLY, TKRWMesh, TKXCAF | STEP (AP203/214/242), IGES, STL, glTF, OBJ, VRML, PLY readers/writers; XCAF document tools (colours, materials, GD&T, notes, views, assembly) |

\* Present in upstream OCCT 8.0.1 / the local full source download, not necessarily in the pruned cascade-port subset — see *Build gaps* below.

**Build gaps the engine agent must close (honest, from `cascade-port/MANIFEST.md`):** the existing cascade-port subset is the dependency closure of {TKPrim, TKBO, TKFillet, TKOffset, TKMesh, TKTopAlgo} plus the STEP/XDE expansion (TKDESTEP, TKDE, TKXSBase, TKCDF, TKLCAF, TKCAF, TKXCAF, TKService-partial). This catalog additionally requires, at minimum: **TKFeat** (local features), **TKHLR** (hidden-line), **TKDEIGES, TKDESTL, TKDEGLTF, TKDEVRML, TKDEPLY, TKRWMesh** (the other formats), **TKExpress** (expressions), **TKBin/TKXml + TKStd/TKStdL** (XBF/XML document persistence), and TKXMesh if extended mesh ops are wanted. Each must be added by the same method as before: transitive closure from OCCT's own `EXTERNLIB.cmake`, never hand-picked files. Until a toolkit is in the build, its commands must report 'not in this build' — never fake a result.

## Commands by category

### Session & naming (12)

#### `new`
- Syntax: `new <name>`
- OCCT: `TopoDS_Compound / TDocStd_Document` — toolkit `TKBRep/TKLCAF`
- What it does: Start an empty document/compound; all named shapes live here.
- Example: `new bracket`

#### `set`
- Syntax: `set <var> = <number|string|point|vector>`
- OCCT: `Expr / TKExpress expression interpreter` — toolkit `TKExpress`
- What it does: Set a session variable usable in later arguments ($var). OCCT ships an expression parser (Expr), not a parametric history.
- Example: `set wall = 2.5`

#### `show-vars`
- Syntax: `show-vars `
- OCCT: `— (app session layer over Expr)` — toolkit `TKExpress`
- What it does: List session variables.
- Example: `show-vars`

#### `units`
- Syntax: `units mm|cm|m|in|ft`
- OCCT: `UnitsAPI / UnitsMethods` — toolkit `TKernel`
- What it does: Set working length unit; OCCT internally works in mm and converts via UnitsAPI.
- Example: `units mm`

#### `precision`
- Syntax: `precision <tolerance>`
- OCCT: `Precision::Confusion` — toolkit `TKernel`
- What it does: Set/show the modelling tolerance used by builders.
- Example: `precision 1e-7`

#### `rename`
- Syntax: `rename <shape> as <name>`
- OCCT: `TNaming_NamedShape / XCAFDoc_ShapeTool label` — toolkit `TKCAF/TKXCAF`
- What it does: Give a shape a persistent name (OCAF/XCAF label).
- Example: `rename body1 as Housing`

#### `list`
- Syntax: `list [shapes|solids|faces|edges|wires|shells|compounds]`
- OCCT: `TopExp_Explorer` — toolkit `TKBRep`
- What it does: List named shapes, optionally filtered by TopAbs type.
- Example: `list solids`

#### `delete`
- Syntax: `delete <name>`
- OCCT: `TopoDS / TDF_Label removal` — toolkit `TKBRep/TKLCAF`
- What it does: Remove a named shape from the session.
- Example: `delete tmp1`

#### `duplicate`
- Syntax: `duplicate <name> as <newname>`
- OCCT: `BRepBuilderAPI_Copy` — toolkit `TKTopAlgo`
- What it does: Deep-copy a shape under a new name.
- Example: `duplicate body1 as body2`

#### `shape-history`
- Syntax: `shape-history <name>`
- OCCT: `BRepTools_History` — toolkit `TKTopAlgo`
- What it does: Show boolean/feature modification history (generated/modified/deleted sub-shapes) recorded by BRepAlgoAPI builders.
- Example: `shape-history fuse1`

#### `undo`
- Syntax: `undo `
- OCCT: `TDocStd_Document Undo (OCAF)` — toolkit `TKCAF`
- What it does: Undo last document transaction. NOTE: only works for operations recorded as OCAF transactions — the app must wrap commands; raw TopoDS edits have no undo in OCCT.
- Example: `undo`

#### `redo`
- Syntax: `redo `
- OCCT: `TDocStd_Document Redo (OCAF)` — toolkit `TKCAF`
- What it does: Redo an undone OCAF transaction.
- Example: `redo`

### Primitives (solids) (9)

#### `box`
- Syntax: `box dx dy dz [at x y z]`
- OCCT: `BRepPrimAPI_MakeBox` — toolkit `TKPrim`
- What it does: Axis-aligned (or placed) rectangular solid.
- Example: `box 40 30 20 as plate`

#### `wedge`
- Syntax: `wedge dx dy dz ltx [at x y z]`
- OCCT: `BRepPrimAPI_MakeWedge` — toolkit `TKPrim`
- What it does: Wedge solid; ltx is top-face x length.
- Example: `wedge 40 30 20 15 as ramp`

#### `cylinder`
- Syntax: `cylinder r h [axis x y z dx dy dz] [angle deg]`
- OCCT: `BRepPrimAPI_MakeCylinder` — toolkit `TKPrim`
- What it does: Cylinder, optionally a sector by angle.
- Example: `cylinder 10 50 as shaft`

#### `cone`
- Syntax: `cone r1 r2 h`
- OCCT: `BRepPrimAPI_MakeCone` — toolkit `TKPrim`
- What it does: Cone/frustum between two radii.
- Example: `cone 20 5 30 as nozzle`

#### `sphere`
- Syntax: `sphere r [vmin vmax] [angle deg]`
- OCCT: `BRepPrimAPI_MakeSphere` — toolkit `TKPrim`
- What it does: Sphere, optionally truncated/sector.
- Example: `sphere 15 as ball`

#### `torus`
- Syntax: `torus R r [angle1 angle2] [angle deg]`
- OCCT: `BRepPrimAPI_MakeTorus` — toolkit `TKPrim`
- What it does: Torus (donut), optionally partial.
- Example: `torus 30 8 as ring`

#### `halfspace`
- Syntax: `halfspace <face> x y z`
- OCCT: `BRepPrimAPI_MakeHalfSpace` — toolkit `TKPrim`
- What it does: Infinite solid on one side of a face (boolean tool).
- Example: `halfspace topface 0 0 -1 as cutter`

#### `prism-solid`
- Syntax: `prism-solid <face> dx dy dz`
- OCCT: `BRepPrimAPI_MakePrism` — toolkit `TKPrim`
- What it does: Linear sweep of a face along a vector (see also extrude).
- Example: `prism-solid prof1 0 0 12 as pad`

#### `revolution-solid`
- Syntax: `revolution-solid <face> ax ay az dx dy dz angle`
- OCCT: `BRepPrimAPI_MakeRevolution` — toolkit `TKPrim`
- What it does: Surface/solid of revolution of a face about an axis.
- Example: `revolution-solid prof1 0 0 0 0 0 1 360 as vase`

### Points, curves & edges (21)

#### `point`
- Syntax: `point x y z`
- OCCT: `gp_Pnt` — toolkit `TKMath`
- What it does: Create a named point.
- Example: `point 10 0 5 as p1`

#### `vertex`
- Syntax: `vertex x y z [tol]`
- OCCT: `BRepBuilderAPI_MakeVertex` — toolkit `TKTopAlgo`
- What it does: Create a topological vertex.
- Example: `vertex 0 0 0 as v1`

#### `line`
- Syntax: `line <p1> <p2> | x1 y1 z1 x2 y2 z2`
- OCCT: `GC_MakeSegment / Geom_TrimmedCurve + BRepBuilderAPI_MakeEdge` — toolkit `TKGeomBase/TKTopAlgo`
- What it does: Straight segment edge.
- Example: `line 0 0 0  50 0 0 as e1`

#### `infinite-line`
- Syntax: `infinite-line x y z dx dy dz`
- OCCT: `Geom_Line + BRepBuilderAPI_MakeEdge` — toolkit `TKG3d/TKTopAlgo`
- What it does: Unbounded line (construction geometry).
- Example: `infinite-line 0 0 0 1 0 0 as axisx`

#### `circle`
- Syntax: `circle cx cy cz r [nx ny nz]`
- OCCT: `GC_MakeCircle / Geom_Circle` — toolkit `TKGeomBase/TKG3d`
- What it does: Full circle edge.
- Example: `circle 0 0 0 20 as e2`

#### `arc`
- Syntax: `arc <p1> <p2> <p3> | circle <c> a1 a2`
- OCCT: `GC_MakeArcOfCircle` — toolkit `TKGeomBase`
- What it does: Circular arc through 3 points or by angles.
- Example: `arc p1 p2 p3 as e3`

#### `ellipse`
- Syntax: `ellipse cx cy cz R r [nx ny nz]`
- OCCT: `GC_MakeEllipse / Geom_Ellipse` — toolkit `TKGeomBase/TKG3d`
- What it does: Ellipse edge.
- Example: `ellipse 0 0 0 30 12 as e4`

#### `hyperbola`
- Syntax: `hyperbola cx cy cz R r`
- OCCT: `GC_MakeHyperbola / Geom_Hyperbola` — toolkit `TKGeomBase/TKG3d`
- What it does: Hyperbola branch edge.
- Example: `hyperbola 0 0 0 20 10 as e5`

#### `parabola`
- Syntax: `parabola cx cy cz focal`
- OCCT: `GC_MakeParabola / Geom_Parabola` — toolkit `TKGeomBase/TKG3d`
- What it does: Parabola edge.
- Example: `parabola 0 0 0 8 as e6`

#### `bezier`
- Syntax: `bezier <p1> <p2> ... [weights w1 w2 ...]`
- OCCT: `Geom_BezierCurve + BRepBuilderAPI_MakeEdge` — toolkit `TKG3d/TKTopAlgo`
- What it does: Bezier curve through control points (rational if weights given).
- Example: `bezier 0 0 0  10 20 0  30 20 0  40 0 0 as spline1`

#### `bspline`
- Syntax: `bspline <p1> <p2> ... [degree d] [periodic]`
- OCCT: `Geom_BSplineCurve + GeomAPI_PointsToBSpline` — toolkit `TKG3d/TKGeomAlgo`
- What it does: B-spline from control points, or interpolated (see interpolate).
- Example: `bspline 0 0 0  10 10 0  20 0 0  30 10 0 as rail`

#### `interpolate`
- Syntax: `interpolate <p1> <p2> ... [tangent1 ... tangent2 ...]`
- OCCT: `GeomAPI_Interpolate` — toolkit `TKGeomAlgo`
- What it does: Smooth C2 curve passing exactly through the points, optional end tangents.
- Example: `interpolate p1 p2 p3 p4 as path`

#### `trim`
- Syntax: `trim <curve> u1 u2`
- OCCT: `Geom_TrimmedCurve + BRepBuilderAPI_MakeEdge` — toolkit `TKG3d/TKTopAlgo`
- What it does: Trim a curve to a parameter range.
- Example: `trim spline1 0.2 0.8 as s1t`

#### `offset-curve`
- Syntax: `offset-curve <edge> distance [nx ny nz]`
- OCCT: `Geom_OffsetCurve / BRepOffsetAPI_MakeOffset (2D/3D curve offset)` — toolkit `TKG3d/TKOffset`
- What it does: Offset a curve by a distance in a plane.
- Example: `offset-curve e1 3 0 0 1 as e1o`

#### `project-curve`
- Syntax: `project-curve <edge> onto <face>`
- OCCT: `GeomAPI_ProjectPointOnSurf / BRepAlgoAPI + ProjLib` — toolkit `TKGeomAlgo/TKGeomBase`
- What it does: Project a curve/point onto a surface, returning the projected edge.
- Example: `project-curve path onto topface as ppath`

#### `extend-curve`
- Syntax: `extend-curve <edge> by <len> [continuity C0|C1|C2]`
- OCCT: `GeomLib_ExtendCurveByLength / ShapeExtend` — toolkit `TKGeomBase/TKShHealing`
- What it does: Extend a curve by a length with chosen continuity.
- Example: `extend-curve s1 10 C1 as s1x`

#### `helix`
- Syntax: `helix r pitch height [axis ...]`
- OCCT: `Parametric cylindrical curve via Geom_Surface (cylinder) + Geom2d_Line diagonal + BRepBuilderAPI_MakeEdge` — toolkit `TKG3d/TKTopAlgo`
- What it does: True helix edge: a diagonal 2D line on a cylindrical surface mapped to 3D. OCCT has no single MakeHelix primitive class — this is the documented construction route, and thread/screw sweeps build on it.
- Example: `helix 10 5 40 as coil`

#### `spiral`
- Syntax: `spiral r1 r2 turns height`
- OCCT: `Geom_BSplineCurve (sampled Archimedean spiral, GeomAPI_PointsToBSpline)` — toolkit `TKG3d/TKGeomAlgo`
- What it does: Planar/ conical spiral approximated by an interpolated B-spline — labelled approximation, not an analytic OCCT curve type.
- Example: `spiral 2 20 3 0 as cam`

#### `curve-length`
- Syntax: `curve-length <edge>`
- OCCT: `GCPnts_AbscissaPoint / BRepGProp on edge` — toolkit `TKGeomBase/TKTopAlgo`
- What it does: Report arc length of an edge/curve.
- Example: `curve-length path`

#### `curve-point`
- Syntax: `curve-point <edge> at <u|fraction|length>`
- OCCT: `Geom_Curve::Value / GCPnts_AbscissaPoint` — toolkit `TKG3d/TKGeomBase`
- What it does: Evaluate a point (and optionally tangent) on a curve.
- Example: `curve-point path at length 12.5`

#### `curve-curvature`
- Syntax: `curve-curvature <edge> at <u>`
- OCCT: `GeomLProp_CLProps / BRepLProp` — toolkit `TKGeomBase/TKBRep`
- What it does: Report curvature/radius at a parameter.
- Example: `curve-curvature spline1 at 0.5`

### Surfaces & faces (15)

#### `plane`
- Syntax: `plane x y z [nx ny nz] [w h]`
- OCCT: `Geom_Plane + BRepBuilderAPI_MakeFace` — toolkit `TKG3d/TKTopAlgo`
- What it does: Planar face, optionally bounded.
- Example: `plane 0 0 0 0 0 1 100 100 as datum`

#### `cylindrical-surface`
- Syntax: `cylindrical-surface r [axis ...] [w h]`
- OCCT: `Geom_CylindricalSurface + BRepBuilderAPI_MakeFace` — toolkit `TKG3d/TKTopAlgo`
- What it does: Cylindrical surface face.
- Example: `cylindrical-surface 25 as borewall`

#### `conical-surface`
- Syntax: `conical-surface r semiangle [axis ...]`
- OCCT: `Geom_ConicalSurface` — toolkit `TKG3d`
- What it does: Conical surface face.
- Example: `conical-surface 20 15 as cone_wall`

#### `spherical-surface`
- Syntax: `spherical-surface r [centre ...]`
- OCCT: `Geom_SphericalSurface` — toolkit `TKG3d`
- What it does: Spherical surface face.
- Example: `spherical-surface 20 as dome_surf`

#### `toroidal-surface`
- Syntax: `toroidal-surface R r`
- OCCT: `Geom_ToroidalSurface` — toolkit `TKG3d`
- What it does: Toroidal surface face.
- Example: `toroidal-surface 30 8 as torus_surf`

#### `surface-of-revolution`
- Syntax: `surface-of-revolution <edge> ax ay az dx dy dz`
- OCCT: `Geom_SurfaceOfRevolution` — toolkit `TKG3d`
- What it does: Surface made by revolving a curve.
- Example: `surface-of-revolution prof 0 0 0 0 0 1 as surf1`

#### `surface-of-extrusion`
- Syntax: `surface-of-extrusion <edge> dx dy dz`
- OCCT: `Geom_SurfaceOfLinearExtrusion` — toolkit `TKG3d`
- What it does: Surface made by extruding a curve along a direction.
- Example: `surface-of-extrusion e1 0 0 1 as surf2`

#### `bezier-surface`
- Syntax: `bezier-surface grid <rows x cols of points>`
- OCCT: `Geom_BezierSurface + BRepBuilderAPI_MakeFace` — toolkit `TKG3d/TKTopAlgo`
- What it does: Bezier patch from a control net.
- Example: `bezier-surface grid pts.csv as patch`

#### `bspline-surface`
- Syntax: `bspline-surface grid <points> [degreeU d] [degreeV d]`
- OCCT: `Geom_BSplineSurface / GeomAPI_PointsToBSplineSurface` — toolkit `TKG3d/TKGeomAlgo`
- What it does: B-spline surface from control net or interpolated through a point grid.
- Example: `bspline-surface grid pts.csv as skin`

#### `fill-surface`
- Syntax: `fill-surface <edge1> [<edge2> ...] [style stretch|coons|curved] [continuity C0|C1|C2]`
- OCCT: `BRepOffsetAPI_MakeFilling / GeomFill_BSplineCurves` — toolkit `TKOffset/TKGeomAlgo`
- What it does: Fill an n-sided hole bounded by edges (Plate/Filling). The CAD 'patch a hole' operation.
- Example: `fill-surface e1 e2 e3 e4 style coons as patch`

#### `plate-surface`
- Syntax: `plate-surface <wire> [constraints points/curves]`
- OCCT: `GeomPlate_BuildPlateSurface / BRepFill? GeomPlate` — toolkit `TKGeomAlgo`
- What it does: Plate surface passing through curve/point constraints with G1/G2 continuity targets.
- Example: `plate-surface boundary as fairing`

#### `offset-surface`
- Syntax: `offset-surface <face> distance`
- OCCT: `Geom_OffsetSurface / BRepOffsetAPI_MakeOffsetShape` — toolkit `TKG3d/TKOffset`
- What it does: Offset surface/sheet by a distance.
- Example: `offset-surface skin 1.5 as skin_off`

#### `surface-point`
- Syntax: `surface-point <face> at u v`
- OCCT: `Geom_Surface::Value / GeomLProp_SLProps` — toolkit `TKG3d/TKGeomBase`
- What it does: Evaluate point, normal, curvature on a surface.
- Example: `surface-point skin at 0.5 0.5`

#### `surface-uv`
- Syntax: `surface-uv <face> of x y z`
- OCCT: `GeomAPI_ProjectPointOnSurf` — toolkit `TKGeomAlgo`
- What it does: Find UV parameters of the projection of a 3D point.
- Example: `surface-uv skin of 10 5 2`

#### `ruled-surface`
- Syntax: `ruled-surface <edge1> <edge2>`
- OCCT: `GeomFill / BRepFill ruled via GeomAPI? GeomFill_BSplineCurves style ruled` — toolkit `TKGeomAlgo`
- What it does: Ruled (straight-line) surface between two curves.
- Example: `ruled-surface rail1 rail2 as ramp_surf`

### Wires, profiles & sketches (15)

#### `wire`
- Syntax: `wire <edge1> <edge2> ... [ordered]`
- OCCT: `BRepBuilderAPI_MakeWire` — toolkit `TKTopAlgo`
- What it does: Join connected edges into a wire; reports gaps if ends do not meet within tolerance.
- Example: `wire e1 e2 e3 e4 as prof1`

#### `polygon`
- Syntax: `polygon x1 y1 z1 x2 y2 z2 ... [close]`
- OCCT: `BRepBuilderAPI_MakePolygon` — toolkit `TKTopAlgo`
- What it does: Polyline wire from points, optionally closed.
- Example: `polygon 0 0 0  40 0 0  40 30 0  0 30 0 close as prof1`

#### `face`
- Syntax: `face <wire> [plane x y z nx ny nz]`
- OCCT: `BRepBuilderAPI_MakeFace` — toolkit `TKTopAlgo`
- What it does: Planar (or surface-bounded) face from a closed wire.
- Example: `face prof1 as face1`

#### `face-with-holes`
- Syntax: `face-with-holes <outerwire> hole <wire1> [hole <wire2> ...]`
- OCCT: `BRepBuilderAPI_MakeFace (face + inner wires)` — toolkit `TKTopAlgo`
- What it does: Face with inner wires as holes.
- Example: `face-with-holes outer hole inner1 as plate_face`

#### `rectangle`
- Syntax: `rectangle w h [at x y] [plane ...]`
- OCCT: `BRepBuilderAPI_MakePolygon + MakeFace (app profile builder over OCCT)` — toolkit `TKTopAlgo`
- What it does: Rectangle profile face — convenience profile built from OCCT edges, not a separate OCCT class.
- Example: `rectangle 40 30 as prof1`

#### `circle-profile`
- Syntax: `circle-profile r [at x y] [plane ...]`
- OCCT: `GC_MakeCircle + MakeWire + MakeFace` — toolkit `TKGeomBase/TKTopAlgo`
- What it does: Circular profile face.
- Example: `circle-profile 12 as holeprof`

#### `slot-profile`
- Syntax: `slot-profile length r [at x y]`
- OCCT: `Two GC_MakeArcOfCircle + two GC_MakeSegment in a MakeWire` — toolkit `TKGeomBase/TKTopAlgo`
- What it does: Oblong/slot profile face (convenience profile).
- Example: `slot-profile 30 6 as slot1`

#### `sketch-begin`
- Syntax: `sketch-begin <name> [plane xy|xz|yz|<face>]`
- OCCT: `BRepBuilderAPI_MakeFace plane + app sketch record of OCCT edges` — toolkit `TKTopAlgo`
- What it does: Start a named 2D profile on a plane/face. IMPORTANT: OCCT has NO parametric sketch constraint solver (see Limitations) — a 'sketch' here is a set of exact OCCT edges/wires on a plane, with numeric coordinates, not driven dimensions.
- Example: `sketch-begin prof1 plane xy`

#### `sketch-line`
- Syntax: `sketch-line x1 y1 x2 y2`
- OCCT: `GC_MakeSegment in sketch plane` — toolkit `TKGeomBase`
- What it does: Add a line to the open sketch.
- Example: `sketch-line 0 0 40 0`

#### `sketch-arc`
- Syntax: `sketch-arc x1 y1 x2 y2 x3 y3`
- OCCT: `GC_MakeArcOfCircle in sketch plane` — toolkit `TKGeomBase`
- What it does: Add an arc through 3 sketch points.
- Example: `sketch-arc 40 0 40 15 30 30`

#### `sketch-circle`
- Syntax: `sketch-circle x y r`
- OCCT: `GC_MakeCircle in sketch plane` — toolkit `TKGeomBase`
- What it does: Add a circle to the open sketch.
- Example: `sketch-circle 20 15 6`

#### `sketch-spline`
- Syntax: `sketch-spline x1 y1 x2 y2 ...`
- OCCT: `GeomAPI_Interpolate in sketch plane` — toolkit `TKGeomAlgo`
- What it does: Add an interpolated spline to the open sketch.
- Example: `sketch-spline 0 30 15 38 40 30`

#### `sketch-end`
- Syntax: `sketch-end `
- OCCT: `BRepBuilderAPI_MakeWire + MakeFace` — toolkit `TKTopAlgo`
- What it does: Close the sketch into wire(s)+face; reports open ends / self-intersections found by BRepCheck.
- Example: `sketch-end`

#### `check-wire`
- Syntax: `check-wire <wire>`
- OCCT: `BRepCheck_Wire / ShapeAnalysis_Wire` — toolkit `TKTopAlgo/TKShHealing`
- What it does: Report wire order, closure, self-intersection, small edges.
- Example: `check-wire prof1`

#### `order-wire`
- Syntax: `order-wire <wire>`
- OCCT: `ShapeAnalysis_WireOrder / BRepLib` — toolkit `TKShHealing/TKTopAlgo`
- What it does: Reorder/reconnect a wire's edges into a traversable order.
- Example: `order-wire messy as prof1`

### Extrude, revolve, loft, sweep & features (18)

#### `extrude`
- Syntax: `extrude <face|wire> dx dy dz | along <dir> distance <d> [taper deg]`
- OCCT: `BRepPrimAPI_MakePrism (taper: BRepFeat? / BRepOffsetAPI taper via MakePrism + Draft)` — toolkit `TKPrim`
- What it does: Extrude a profile face along a direction — the core pad operation.
- Example: `extrude prof1 along 0 0 1 distance 12 as pad`

#### `extrude-symmetric`
- Syntax: `extrude-symmetric <face> distance <d> [dir ...]`
- OCCT: `BRepPrimAPI_MakePrism (two-sided)` — toolkit `TKPrim`
- What it does: Extrude equally both ways from the profile plane.
- Example: `extrude-symmetric prof1 distance 12 as pad`

#### `extrude-to-face`
- Syntax: `extrude-to-face <face> dir ... to <targetface>`
- OCCT: `BRepFeat_MakePrism (up-to-face)` — toolkit `TKFeat`
- What it does: Extrude a profile until it meets a target face — a local feature operation, not a plain prism.
- Example: `extrude-to-face prof1 to topface as boss`

#### `revolve`
- Syntax: `revolve <face|wire> ax ay az dx dy dz angle`
- OCCT: `BRepPrimAPI_MakeRevol` — toolkit `TKPrim`
- What it does: Revolve a profile about an axis by an angle (360 = full).
- Example: `revolve prof1 0 0 0 0 0 1 360 as turned`

#### `loft`
- Syntax: `loft <wire1> <wire2> ... [solid] [ruled] [closed]`
- OCCT: `BRepOffsetAPI_ThruSections` — toolkit `TKOffset`
- What it does: Loft through a series of section wires; ruled = straight between sections, otherwise smooth.
- Example: `loft w1 w2 w3 solid as body1`

#### `sweep`
- Syntax: `sweep <profilewire> along <spinewire> [frenet|fixed|auxiliary]`
- OCCT: `BRepOffsetAPI_MakePipeShell` — toolkit `TKOffset`
- What it does: Sweep a profile along a path with a trihedron mode.
- Example: `sweep prof along path as rail`

#### `pipe`
- Syntax: `pipe <profilewire> along <spinewire>`
- OCCT: `BRepOffsetAPI_MakePipe` — toolkit `TKOffset`
- What it does: Constant-section pipe along a spine.
- Example: `pipe prof along path as tube`

#### `pipe-shell`
- Syntax: `pipe-shell <profile> along <spine> [mode frenet|corrected|discrete] [transition right|round|transformed]`
- OCCT: `BRepOffsetAPI_MakePipeShell (SetMode/SetTransitionMode)` — toolkit `TKOffset`
- What it does: Full sweep control: mode and corner transition.
- Example: `pipe-shell prof along path mode frenet transition round as duct`

#### `variable-sweep`
- Syntax: `variable-sweep <spine> sections <wire@u ...>`
- OCCT: `BRepOffsetAPI_MakePipeShell with auxiliary spine / law functions (GeomFill with sections)` — toolkit `TKOffset/TKGeomAlgo`
- What it does: Sweep whose section changes along the path (PipeShell with multiple sections / laws).
- Example: `variable-sweep path sections s@0 s@0.5 s@1 as duct`

#### `helix-sweep`
- Syntax: `helix-sweep <profile> r pitch height`
- OCCT: `BRepOffsetAPI_MakePipeShell along helix edge (see helix)` — toolkit `TKOffset`
- What it does: Sweep a profile along a helix — screw threads, coils, springs (profile should be the thread tooth for threads).
- Example: `helix-sweep tooth r 10 pitch 5 height 40 as thread`

#### `fill-sweep`
- Syntax: `fill-sweep <edge1> <edge2> [support <face>]`
- OCCT: `BRepFill / GeomFill (swept surface between rails)` — toolkit `TKBool/TKGeomAlgo`
- What it does: Swept surface between two guide curves (BRepFill).
- Example: `fill-sweep rail1 rail2 as surf`

#### `groove`
- Syntax: `groove <face> ax ay az dx dy dz angle`
- OCCT: `BRepFeat_MakeRevol (revolved local feature in cut mode — OCCT has no separate MakeGroove class in 8.0.1; verified against the TKFeat package list)` — toolkit `TKFeat`
- What it does: Revolved cut feature (a turned groove) from a profile face.
- Example: `groove prof 0 0 0 0 0 1 360 as cut1`

#### `hole-feature`
- Syntax: `hole-feature <solid> face <face> centre x y r depth <d>|through`
- OCCT: `BRepFeat_MakeCylindricalHole` — toolkit `TKFeat`
- What it does: Drill a cylindrical hole as a local feature into a solid from a face (BRepFeat cylindrical-hole feature, with its own status/error reporting).
- Example: `hole-feature body1 face topface centre 20 15 r 3 depth through as body1`

#### `rib-feature`
- Syntax: `rib-feature <face> ... (BRepFeat_MakeRibSlot)`
- OCCT: `BRepFeat_MakeRibSlot` — toolkit `TKFeat`
- What it does: Rib/slot feature grown from a profile until it meets the base solid.
- Example: `rib-feature ribprof as rib1`

#### `dprism-feature`
- Syntax: `dprism-feature <face> dir ... [angle]`
- OCCT: `BRepFeat_MakeDPrism` — toolkit `TKFeat`
- What it does: Drafted prism feature (prism with draft angle) fused/cut as a local operation.
- Example: `dprism-feature prof 0 0 1 as boss`

#### `linear-feature`
- Syntax: `linear-feature <face> ...`
- OCCT: `BRepFeat_MakeLinearForm` — toolkit `TKFeat`
- What it does: Linear (extruded-with-rules) feature form (rib/slot family).
- Example: `linear-feature prof as rib1`

#### `glued-feature`
- Syntax: `glued-feature <feature> on <solid> glue <face>`
- OCCT: `BRepFeat_Gluer / LocOpe_Gluer` — toolkit `TKFeat`
- What it does: Glue a feature shape onto a solid at a face (local operation keeping the rest untouched).
- Example: `glued-feature boss on body1 glue topface as body2`

#### `split-feature`
- Syntax: `split-feature <solid> by <face|plane>`
- OCCT: `BRepFeat_SplitShape / LocOpe_SplitShape` — toolkit `TKFeat`
- What it does: Split a shape by a tool face, keeping local-operation history.
- Example: `split-feature body1 by midplane as body1`

### Booleans & defeaturing (9)

#### `fuse`
- Syntax: `fuse <a> <b> [as <name>] [glue] [fuzzy <tol>]`
- OCCT: `BRepAlgoAPI_Fuse (BOPAlgo)` — toolkit `TKBO/TKBool`
- What it does: Boolean union. glue = faster glued option for touching solids; fuzzy adds tolerance.
- Example: `fuse body1 boss1 as body1`

#### `cut`
- Syntax: `cut <a> minus <b> [...]`
- OCCT: `BRepAlgoAPI_Cut` — toolkit `TKBO/TKBool`
- What it does: Boolean subtraction (a − b). Multiple tools allowed.
- Example: `cut body1 hole1 as body1`

#### `common`
- Syntax: `common <a> <b>`
- OCCT: `BRepAlgoAPI_Common` — toolkit `TKBO/TKBool`
- What it does: Boolean intersection — the volume shared by both.
- Example: `common a b as overlap`

#### `section-boolean`
- Syntax: `section-boolean <a> <b>`
- OCCT: `BRepAlgoAPI_Section` — toolkit `TKBO/TKBool`
- What it does: Edges where two shapes' surfaces intersect (no solid result).
- Example: `section-boolean a b as sect`

#### `split`
- Syntax: `split <a> by <b>`
- OCCT: `BRepAlgoAPI_Splitter` — toolkit `TKBO/TKBool`
- What it does: Split a by b, keeping all resulting pieces (splitter, unlike cut/fuse).
- Example: `split body1 by plane1 as pieces`

#### `boolean-multi`
- Syntax: `boolean-multi fuse|cut|common <a> tools <b1> <b2> ... [arguments ...]`
- OCCT: `BOPAlgo_Builder + BRepAlgoAPI_BuilderAlgo (general boolean with argument/tool sets — there is no BRepAlgoAPI_MultiFuse class in OCCT 8.0.1; verified)` — toolkit `TKBO`
- What it does: General Boolean Operation (GBO) with separate argument and tool lists, non-destructive/fuzzy/glue options.
- Example: `boolean-multi fuse base tools t1 t2 as body1`

#### `boolean-options`
- Syntax: `boolean-options `
- OCCT: `BOPAlgo_Options (SetFuzzyValue, SetGlue, SetRunParallel, SetUseOBB, CheckInverted)` — toolkit `TKBO`
- What it does: Show/set global boolean options: fuzzy tolerance, glue, parallel, OBB pre-check, inverted-solid checking.
- Example: `boolean-options glue on fuzzy 0.001`

#### `defeature`
- Syntax: `defeature <shape> remove faces <f1> [<f2> ...]`
- OCCT: `BRepAlgoAPI_Defeaturing` — toolkit `TKBO`
- What it does: Remove selected faces (holes, fillets, pockets) and heal the surrounding solid closed — OCCT's defeaturing, built on the boolean engine.
- Example: `defeature body1 remove faces face(12) face(13) as clean`

#### `halfspace-cut`
- Syntax: `halfspace-cut <shape> <face> x y z`
- OCCT: `BRepPrimAPI_MakeHalfSpace + BRepAlgoAPI_Cut` — toolkit `TKPrim/TKBO`
- What it does: Cut a solid with the half-space beyond a face.
- Example: `halfspace-cut body1 cutface 0 0 -1 as trimmed`

### Fillet, chamfer, shell, offset & draft (13)

#### `fillet`
- Syntax: `fillet <shape> radius <r> on edges <e...> | all`
- OCCT: `BRepFilletAPI_MakeFillet` — toolkit `TKFillet`
- What it does: Constant-radius rolling-ball fillet on selected edges (or all).
- Example: `fillet body1 radius 2 on edges edge(3) edge(4) as body1`

#### `fillet-variable`
- Syntax: `fillet-variable <shape> on edge <e> radius <r1> at start radius <r2> at end`
- OCCT: `BRepFilletAPI_MakeFillet::Add(r1,r2,edge)` — toolkit `TKFillet`
- What it does: Variable-radius fillet along an edge.
- Example: `fillet-variable body1 on edge edge(3) radius 1 at start radius 4 at end as body1`

#### `fillet-law`
- Syntax: `fillet-law <shape> on edge <e> law <values...>`
- OCCT: `BRepFilletAPI_MakeFillet::Add(Law_Function)` — toolkit `TKFillet`
- What it does: Fillet radius driven by a law function along the edge.
- Example: `fillet-law body1 on edge edge(3) law 1 3 1 as body1`

#### `chamfer`
- Syntax: `chamfer <shape> distance <d> [distance2 <d2>|angle <deg>] on edges <e...>`
- OCCT: `BRepFilletAPI_MakeChamfer` — toolkit `TKFillet`
- What it does: Chamfer: equal distances, two distances, or distance+angle.
- Example: `chamfer body1 distance 1.5 on edges all as body1`

#### `chamfer-2d`
- Syntax: `chamfer-2d <face|wire> ...`
- OCCT: `ChFi2d_FilletAPI / ChFi2d_AnaFilletAlgo` — toolkit `TKFillet`
- What it does: 2D fillet/chamfer between planar edges in a profile (before extrusion).
- Example: `chamfer-2d prof1 as prof1`

#### `fillet-2d`
- Syntax: `fillet-2d <wire> radius <r> at vertex <v>`
- OCCT: `ChFi2d_FilletAlgo` — toolkit `TKFillet`
- What it does: 2D corner fillet inside a planar wire.
- Example: `fillet-2d prof1 radius 3 at vertex 2 as prof1`

#### `shell`
- Syntax: `shell <solid> thickness <t> remove faces <f...> [tol]`
- OCCT: `BRepOffsetAPI_MakeThickSolid` — toolkit `TKOffset`
- What it does: Hollow a solid to a wall thickness, opening the listed faces.
- Example: `shell body1 thickness 2 remove faces topface as housing`

#### `thicken`
- Syntax: `thicken <face|shell> thickness <t> [both]`
- OCCT: `BRepOffsetAPI_MakeThickSolid (sheet mode) / MakeOffsetShape` — toolkit `TKOffset`
- What it does: Give a surface/sheet solid thickness.
- Example: `thicken skin thickness 1.5 as panel`

#### `offset-shape`
- Syntax: `offset-shape <shape> distance <d> [mode skin|pipe|rectoverso] [join arc|intersection] [tol]`
- OCCT: `BRepOffsetAPI_MakeOffsetShape` — toolkit `TKOffset`
- What it does: Offset a whole solid/sheet in/out by a distance (grow/shrink).
- Example: `offset-shape body1 distance -0.4 mode skin join arc as body1`

#### `offset-face`
- Syntax: `offset-face <face> distance <d>`
- OCCT: `BRepOffsetAPI_MakeOffset (face offset in a wire/face context)` — toolkit `TKOffset`
- What it does: Offset a face/wire in its plane (2D offset for profiles).
- Example: `offset-face prof1 distance 2 as prof_big`

#### `draft`
- Syntax: `draft <shape> angle <deg> neutral <face|plane> dir x y z [add faces ...]`
- OCCT: `BRepOffsetAPI_DraftAngle` — toolkit `TKOffset`
- What it does: Apply mould draft taper to selected faces about a neutral plane.
- Example: `draft body1 angle 3 neutral bottom dir 0 0 1 as body1`

#### `draft-check`
- Syntax: `draft-check <shape> dir x y z min <deg>`
- OCCT: `BRepOffsetAPI_DraftAngle analysis via face normals (GeomLProp) — app analysis over OCCT normals` — toolkit `TKOffset/TKGeomBase`
- What it does: Report faces under the minimum draft angle for a pull direction (mouldability check). Analysis only; no geometry change.
- Example: `draft-check body1 dir 0 0 1 min 2`

#### `sew-then-shell`
- Syntax: `sew-then-shell <shell> thickness <t>`
- OCCT: `ShapeFix + BRepOffsetAPI_MakeThickSolid` — toolkit `TKShHealing/TKOffset`
- What it does: Convenience chain: sew/heal a sheet then thicken (app script of two OCCT ops).
- Example: `sew-then-shell sheet thickness 2 as solid1`

### Transforms & patterns (12)

#### `translate`
- Syntax: `translate <shape> dx dy dz [copy as <name>]`
- OCCT: `gp_Trsf SetTranslation + BRepBuilderAPI_Transform` — toolkit `TKMath/TKTopAlgo`
- What it does: Move a shape (in place unless copy).
- Example: `translate body1 10 0 0`

#### `rotate`
- Syntax: `rotate <shape> ax ay az dx dy dz angle [copy]`
- OCCT: `gp_Trsf SetRotation + BRepBuilderAPI_Transform` — toolkit `TKMath/TKTopAlgo`
- What it does: Rotate about an arbitrary axis.
- Example: `rotate body1 0 0 0 0 0 1 45`

#### `scale`
- Syntax: `scale <shape> factor <f> [centre x y z] [copy]`
- OCCT: `gp_Trsf SetScale + BRepBuilderAPI_Transform (true geometry scale: BRepBuilderAPI_GTransform)` — toolkit `TKMath/TKTopAlgo`
- What it does: Uniform scale. NOTE: non-uniform scale needs gtransform (below) and converts surfaces to B-splines in places.
- Example: `scale body1 factor 2 centre 0 0 0 copy as big`

#### `gtransform`
- Syntax: `gtransform <shape> sx sy sz [centre ...]`
- OCCT: `BRepBuilderAPI_GTransform (gp_GTrsf)` — toolkit `TKTopAlgo/TKMath`
- What it does: General (incl. non-uniform) transform; may downgrade analytic surfaces — reported honestly in output.
- Example: `gtransform body1 2 1 1 as stretched`

#### `mirror`
- Syntax: `mirror <shape> plane x y z nx ny nz [copy]`
- OCCT: `gp_Trsf SetMirror + BRepBuilderAPI_Transform` — toolkit `TKMath/TKTopAlgo`
- What it does: Mirror about a plane.
- Example: `mirror body1 plane 0 0 0 1 0 0 copy as otherhalf`

#### `move-to`
- Syntax: `move-to <shape> place <target> [from <source>]`
- OCCT: `TopLoc_Location / gp_Trsf placement` — toolkit `TKBRep/TKMath`
- What it does: Set a shape's location (placement) without rebuilding geometry — cheap, reversible.
- Example: `move-to part1 place loc1`

#### `location`
- Syntax: `location <shape>`
- OCCT: `TopLoc_Location / TopoDS_Shape::Location` — toolkit `TKBRep`
- What it does: Report a shape's placement (translation + rotation).
- Example: `location part1`

#### `linear-pattern`
- Syntax: `linear-pattern <shape|feature> dir x y z count <n> spacing <d> [fuse]`
- OCCT: `gp_Trsf repeated + BRepAlgoAPI_MultiFuse (app loop over OCCT transforms/booleans)` — toolkit `TKMath/TKBO`
- What it does: Repeat a shape/feature in a line. OCCT has no single pattern class — this is an app loop over transforms (+ optional fuse), stated as such.
- Example: `linear-pattern hole1 dir 1 0 0 count 5 spacing 12 fuse as body1`

#### `polar-pattern`
- Syntax: `polar-pattern <shape> axis ... count <n> angle <total> [fuse]`
- OCCT: `gp_Trsf rotations + BRepAlgoAPI_MultiFuse (app loop)` — toolkit `TKMath/TKBO`
- What it does: Repeat around an axis (same app-loop note as linear-pattern).
- Example: `polar-pattern tooth axis 0 0 0 0 0 1 count 12 angle 360 fuse as gear`

#### `rect-pattern`
- Syntax: `rect-pattern <shape> dir1 ... n1 spacing1 dir2 ... n2 spacing2 [fuse]`
- OCCT: `App loop of gp_Trsf + MultiFuse` — toolkit `TKMath/TKBO`
- What it does: 2D grid pattern (app loop, as above).
- Example: `rect-pattern hole1 dir1 1 0 0 n1 4 spacing1 10 dir2 0 1 0 n2 3 spacing2 10 fuse`

#### `mirror-pattern`
- Syntax: `mirror-pattern <shape> plane ... fuse`
- OCCT: `gp_Trsf mirror + BRepAlgoAPI_Fuse` — toolkit `TKMath/TKBO`
- What it does: Mirror and fuse to the original (symmetric part completion).
- Example: `mirror-pattern half plane 0 0 0 1 0 0 fuse as whole`

#### `copy-transform`
- Syntax: `copy-transform <shape> transforms <file|list>`
- OCCT: `BRepBuilderAPI_Transform per transform (app loop)` — toolkit `TKTopAlgo`
- What it does: Apply a list of transforms producing multiple copies (instancing by copy).
- Example: `copy-transform bolt transforms placements.csv as bolts`

### Topology, inspection & selection (22)

#### `info`
- Syntax: `info <shape>`
- OCCT: `TopExp_Explorer + TopAbs_ShapeEnum census` — toolkit `TKBRep`
- What it does: Full census: solids/shells/faces/wires/edges/vertices, closed?, orientation, location.
- Example: `info body1`

#### `type`
- Syntax: `type <shape>`
- OCCT: `TopoDS_Shape::ShapeType` — toolkit `TKBRep`
- What it does: Report TopAbs type (SOLID, SHELL, FACE, ...).
- Example: `type body1`

#### `solids`
- Syntax: `solids <shape>`
- OCCT: `TopExp_Explorer(TopAbs_SOLID) / TopoDS::Solid` — toolkit `TKBRep`
- What it does: List/count solids inside a shape, naming them solid(1)... for later commands.
- Example: `solids assembly1`

#### `faces`
- Syntax: `faces <shape> [type plane|cylinder|cone|sphere|torus|bspline|all]`
- OCCT: `TopExp_Explorer(TopAbs_FACE) + BRepAdaptor_Surface::GetType` — toolkit `TKBRep/TKG3d`
- What it does: List faces, optionally only one surface type — the selection vocabulary for fillet/shell/etc.
- Example: `faces body1 type cylinder`

#### `edges`
- Syntax: `edges <shape> [type line|circle|bspline|all]`
- OCCT: `TopExp_Explorer(TopAbs_EDGE) + BRepAdaptor_Curve::GetType` — toolkit `TKBRep/TKG3d`
- What it does: List edges by curve type.
- Example: `edges body1 type circle`

#### `wires`
- Syntax: `wires <shape>`
- OCCT: `TopExp_Explorer(TopAbs_WIRE)` — toolkit `TKBRep`
- What it does: List wires.
- Example: `wires face1`

#### `vertices`
- Syntax: `vertices <shape>`
- OCCT: `TopExp_Explorer(TopAbs_VERTEX) + BRep_Tool::Pnt` — toolkit `TKBRep`
- What it does: List vertices with coordinates.
- Example: `vertices body1`

#### `shells`
- Syntax: `shells <shape>`
- OCCT: `TopExp_Explorer(TopAbs_SHELL)` — toolkit `TKBRep`
- What it does: List shells and whether each is closed.
- Example: `shells body1`

#### `face-info`
- Syntax: `face-info face(<n>) of <shape>`
- OCCT: `BRepAdaptor_Surface + GeomAdaptor_Surface (type, bounds, area via BRepGProp)` — toolkit `TKG3d/TKTopAlgo`
- What it does: Surface type, UV bounds, area, normal at centre for one face.
- Example: `face-info face(4) of body1`

#### `edge-info`
- Syntax: `edge-info edge(<n>) of <shape>`
- OCCT: `BRepAdaptor_Curve (type, range, length)` — toolkit `TKG3d`
- What it does: Curve type, parameter range, length for one edge.
- Example: `edge-info edge(7) of body1`

#### `adjacent`
- Syntax: `adjacent faces|edges to face(<n>)|edge(<n>) of <shape>`
- OCCT: `TopExp::MapShapesAndAncestors / TopTools indexed maps` — toolkit `TKBRep`
- What it does: Adjacency: which faces share an edge, which edges bound a face, etc.
- Example: `adjacent faces to edge(7) of body1`

#### `shared`
- Syntax: `shared between <a> and <b>`
- OCCT: `TopExp::MapShapesAndAncestors intersection (app set logic over OCCT maps)` — toolkit `TKBRep`
- What it does: Sub-shapes shared by two shapes.
- Example: `shared between a and b`

#### `same-domain`
- Syntax: `same-domain <shape>`
- OCCT: `ShapeUpgrade_UnifySameDomain (report mode) / TopExp maps` — toolkit `TKShHealing/TKBRep`
- What it does: Find coplanar/coaxial same-domain faces that could be merged.
- Example: `same-domain body1`

#### `orientation`
- Syntax: `orientation <shape>`
- OCCT: `TopoDS_Shape::Orientation / BRepLib::OrientClosedSolid` — toolkit `TKBRep/TKTopAlgo`
- What it does: Report/fix solid orientation (forward/reversed, closed-solid orientation).
- Example: `orientation body1`

#### `free-edges`
- Syntax: `free-edges <shape>`
- OCCT: `ShapeAnalysis_FreeBounds / TopExp edge-use count` — toolkit `TKShHealing/TKBRep`
- What it does: Edges used by only one face — open boundaries / cracks.
- Example: `free-edges sheet1`

#### `check`
- Syntax: `check <shape> [verbose]`
- OCCT: `BRepCheck_Analyzer (+ BRepCheck per-subshape results)` — toolkit `TKTopAlgo`
- What it does: Validity check: is the shape a valid B-Rep? Lists invalid sub-shapes and fault codes.
- Example: `check body1 verbose`

#### `contains`
- Syntax: `contains <shape> point x y z [tol]`
- OCCT: `BRepClass3d_SolidClassifier` — toolkit `TKTopAlgo`
- What it does: Is a point IN, ON, or OUT of a solid?
- Example: `contains body1 point 5 5 5`

#### `classify`
- Syntax: `classify <face|wire> ...`
- OCCT: `BRepClass_FaceClassifier / BRepClass2d? BRepClass3d` — toolkit `TKTopAlgo`
- What it does: Classify point/face relationships (2D and 3D classifiers).
- Example: `classify face1 point 10 10`

#### `explode`
- Syntax: `explode <shape> into solids|faces|shells`
- OCCT: `TopExp_Explorer + naming (app naming over OCCT explorer)` — toolkit `TKBRep`
- What it does: Split a compound/compsolid into individually named pieces.
- Example: `explode assembly1 into solids`

#### `compound`
- Syntax: `compound <s1> <s2> ... as <name>`
- OCCT: `TopoDS_Compound + BRep_Builder::Add` — toolkit `TKBRep`
- What it does: Group shapes into a compound without fusing them.
- Example: `compound a b c as assembly1`

#### `compsolid`
- Syntax: `compsolid <solid1> <solid2> ... as <name>`
- OCCT: `TopoDS_CompSolid + BRep_Builder` — toolkit `TKBRep`
- What it does: Group face-connected solids into a compsolid.
- Example: `compsolid s1 s2 as part`

#### `extract`
- Syntax: `extract <subshape-selector> from <shape> as <name>`
- OCCT: `TopExp_Explorer indexing (shared index space)` — toolkit `TKBRep`
- What it does: Pull one face/edge/solid out as its own named shape.
- Example: `extract face(4) from body1 as topface`

### Measurement & analysis (15)

#### `measure-distance`
- Syntax: `measure-distance <a> <b> | point point`
- OCCT: `BRepExtrema_DistShapeShape` — toolkit `TKTopAlgo`
- What it does: Minimum distance between two shapes/points, with the closest points.
- Example: `measure-distance body1 body2`

#### `measure-length`
- Syntax: `measure-length <edge|wire|shape>`
- OCCT: `BRepGProp::LinearProperties (GProp)` — toolkit `TKTopAlgo`
- What it does: Total edge/wire length.
- Example: `measure-length prof1`

#### `measure-area`
- Syntax: `measure-area <face|shell|shape>`
- OCCT: `BRepGProp::SurfaceProperties` — toolkit `TKTopAlgo`
- What it does: Surface area.
- Example: `measure-area body1`

#### `measure-volume`
- Syntax: `measure-volume <solid|shape>`
- OCCT: `BRepGProp::VolumeProperties` — toolkit `TKTopAlgo`
- What it does: Volume (signed; negative flags reversed orientation).
- Example: `measure-volume body1`

#### `centre-of-mass`
- Syntax: `centre-of-mass <shape>`
- OCCT: `BRepGProp Volume/Surface/LinearProperties::CentreOfMass` — toolkit `TKTopAlgo`
- What it does: Centre of mass/gravity for volume, area, or length as appropriate.
- Example: `centre-of-mass body1`

#### `inertia`
- Syntax: `inertia <shape>`
- OCCT: `GProp_PrincipalProps / MatrixOfInertia via BRepGProp` — toolkit `TKTopAlgo/TKMath`
- What it does: Moments of inertia, principal axes, radii of gyration about the centre of mass.
- Example: `inertia body1`

#### `moment`
- Syntax: `moment <shape> about <axis|plane>`
- OCCT: `GProp_PrincipalProps / BRepGProp with reference point` — toolkit `TKTopAlgo`
- What it does: Moment of inertia about a chosen axis/point.
- Example: `moment body1 about axis 0 0 0 0 0 1`

#### `bbox`
- Syntax: `bbox <shape> [optimal] [usemesh]`
- OCCT: `BRepBndLib::Add / AddOptimal + Bnd_Box` — toolkit `TKTopAlgo`
- What it does: Axis-aligned bounding box; optimal = tight (slower, exact), usemesh = from triangulation.
- Example: `bbox body1 optimal`

#### `bbox-gap`
- Syntax: `bbox-gap <shape>`
- OCCT: `Bnd_Box::Gap` — toolkit `TKTopAlgo`
- What it does: Report the tolerance gap inflated into the bounding box.
- Example: `bbox-gap body1`

#### `angle-between`
- Syntax: `angle-between <face|edge> <face|edge> [at point]`
- OCCT: `GeomLProp / BRepAdaptor normals & tangents (app math over OCCT adaptors)` — toolkit `TKG3d/TKGeomBase`
- What it does: Angle between planes/cylinders' axes or edge tangents.
- Example: `angle-between face(1) face(2) of body1`

#### `radius`
- Syntax: `radius <edge|face>`
- OCCT: `BRepAdaptor_Curve/Surface (Circle radius / Cylinder radius / Sphere radius)` — toolkit `TKG3d`
- What it does: Radius of a circular edge or cylindrical/spherical face.
- Example: `radius face(6) of body1`

#### `perimeter`
- Syntax: `perimeter <face|wire>`
- OCCT: `BRepGProp::LinearProperties on wires` — toolkit `TKTopAlgo`
- What it does: Perimeter length of a face/wire.
- Example: `perimeter face1`

#### `cross-section`
- Syntax: `cross-section <shape> at <plane> [area]`
- OCCT: `BRepAlgoAPI_Section + BRepGProp on resulting face (via MakeFace)` — toolkit `TKBO/TKTopAlgo`
- What it does: Section edges at a plane; with area, the section face area and centroid.
- Example: `cross-section body1 at plane z=15 area`

#### `thickness-at`
- Syntax: `thickness-at <solid> point x y z dir ...`
- OCCT: `BRepIntCurveSurface_Inter / BRepExtrema ray cast (app ray over OCCT intersector)` — toolkit `TKTopAlgo/TKGeomAlgo`
- What it does: Wall thickness along a ray through a solid (entry/exit distance).
- Example: `thickness-at housing point 0 0 30 dir 0 0 -1`

#### `mass`
- Syntax: `mass <shape> density <d>`
- OCCT: `BRepGProp volume x density (app arithmetic)` — toolkit `TKTopAlgo`
- What it does: Mass from true OCCT volume and a user density — arithmetic, not a material database (OCCT has none built in).
- Example: `mass body1 density 7.85e-6`

### Healing, sewing & shape fix (26)

#### `heal`
- Syntax: `heal <shape> [all]`
- OCCT: `ShapeFix_Shape (runs the ShapeFix suite)` — toolkit `TKShHealing`
- What it does: Run OCCT's full healing pipeline (wire, face, shell, solid fixes) and report what changed.
- Example: `heal imported as fixed`

#### `fix-wire`
- Syntax: `fix-wire <wire|face>`
- OCCT: `ShapeFix_Wire` — toolkit `TKShHealing`
- What it does: Fix wire order, small edges, self-intersection, nonadjacent points.
- Example: `fix-wire prof1 as prof1`

#### `fix-face`
- Syntax: `fix-face <face>`
- OCCT: `ShapeFix_Face` — toolkit `TKShHealing`
- What it does: Fix face orientation, missing seam, loop wires, intersecting wires.
- Example: `fix-face f1 as f1`

#### `fix-shell`
- Syntax: `fix-shell <shell> [orientation]`
- OCCT: `ShapeFix_Shell` — toolkit `TKShHealing`
- What it does: Fix shell face orientation / closedness.
- Example: `fix-shell sh1 as sh1`

#### `fix-solid`
- Syntax: `fix-solid <solid>`
- OCCT: `ShapeFix_Solid` — toolkit `TKShHealing`
- What it does: Fix solid shell orientation and construction.
- Example: `fix-solid s1 as s1`

#### `fix-edge`
- Syntax: `fix-edge <edge> [sameparameter] [degenerated]`
- OCCT: `ShapeFix_Edge` — toolkit `TKShHealing`
- What it does: Fix edge curve/3D-2D consistency (SameParameter), degenerated edges.
- Example: `fix-edge e1 sameparameter as e1`

#### `sew`
- Syntax: `sew <face|shell> ... [tol] [option cutting|nonmanifold]`
- OCCT: `BRepBuilderAPI_Sewing` — toolkit `TKTopAlgo`
- What it does: Sew separate faces/shells into a shell/solid by stitching free edges within tolerance.
- Example: `sew f1 f2 f3 tol 0.01 as shell1`

#### `unify`
- Syntax: `unify <shape> [faces] [edges] [safe]`
- OCCT: `ShapeUpgrade_UnifySameDomain` — toolkit `TKShHealing`
- What it does: Merge same-domain (coplanar/coaxial/C1) faces and collinear edges into single faces/edges — the 'Refine Shape' operation; removes leftover split faces from imports/booleans.
- Example: `unify imported faces edges as clean`

#### `remove-split`
- Syntax: `remove-split <shape>`
- OCCT: `ShapeUpgrade_RemoveInternalWires / ShapeUpgrade split tools` — toolkit `TKShHealing`
- What it does: Remove internal wires / redundant split features.
- Example: `remove-split body1 as body1`

#### `convert-to-bspline`
- Syntax: `convert-to-bspline <shape> [curves] [surfaces]`
- OCCT: `ShapeCustom_ConvertToBSpline / ShapeUpgrade? ShapeCustom` — toolkit `TKShHealing`
- What it does: Convert analytic curves/surfaces to B-splines (for downstream ops that need them).
- Example: `convert-to-bspline body1 surfaces as bsbody`

#### `convert-to-revolution`
- Syntax: `convert-to-revolution <shape>`
- OCCT: `ShapeCustom_ConvertToRevolution` — toolkit `TKShHealing`
- What it does: Convert suitable surfaces to surfaces of revolution.
- Example: `convert-to-revolution body1 as body1`

#### `bspline-restriction`
- Syntax: `bspline-restriction <shape> continuity ... maxdegree ...`
- OCCT: `ShapeCustom_BSplineRestriction` — toolkit `TKShHealing`
- What it does: Restrict B-spline degree/segments/continuity in a shape.
- Example: `bspline-restriction body1 maxdegree 8 as body1`

#### `direct-faces`
- Syntax: `direct-faces <shape>`
- OCCT: `ShapeCustom_DirectFaces` — toolkit `TKShHealing`
- What it does: Rebuild faces directly from their surfaces where builders left indirect geometry.
- Example: `direct-faces imported as imported`

#### `analyse-surface`
- Syntax: `analyse-surface <face>`
- OCCT: `ShapeAnalysis_Surface (bounds, singularities, closedness)` — toolkit `TKShHealing`
- What it does: Report surface singularities, U/V closedness, bounds.
- Example: `analyse-surface face1`

#### `analyse-curve`
- Syntax: `analyse-curve <edge>`
- OCCT: `ShapeAnalysis_Curve (gaps, projection, bounds)` — toolkit `TKShHealing`
- What it does: Report curve gaps and 3D/2D curve consistency.
- Example: `analyse-curve e1`

#### `analyse-freebounds`
- Syntax: `analyse-freebounds <shape> [tol]`
- OCCT: `ShapeAnalysis_FreeBounds` — toolkit `TKShHealing`
- What it does: List free boundary wires of a sheet (gaps to sew).
- Example: `analyse-freebounds sheet1`

#### `analyse-shell`
- Syntax: `analyse-shell <shape>`
- OCCT: `ShapeAnalysis_Shell (bad faces, free edges)` — toolkit `TKShHealing`
- What it does: Report bad/free faces in shells.
- Example: `analyse-shell shell1`

#### `small-edges`
- Syntax: `small-edges <shape> [tol]`
- OCCT: `ShapeAnalysis_CheckSmallFace / ShapeFix_Face small-face tools` — toolkit `TKShHealing`
- What it does: Find (and optionally remove via fix) sliver faces / small edges.
- Example: `small-edges body1 tol 0.01`

#### `spot-face`
- Syntax: `spot-face <face>`
- OCCT: `ShapeAnalysis_CheckSmallFace::IsSpotFace` — toolkit `TKShHealing`
- What it does: Detect spot (tiny) faces.
- Example: `spot-face face(9) of body1`

#### `strip-face`
- Syntax: `strip-face <face>`
- OCCT: `ShapeAnalysis_CheckSmallFace::IsStripFace` — toolkit `TKShHealing`
- What it does: Detect strip (long thin) faces.
- Example: `strip-face face(9) of body1`

#### `shape-process`
- Syntax: `shape-process <shape> <operator> [params]`
- OCCT: `ShapeProcess_Operator / ShapeProcessAPI_ApplySequence` — toolkit `TKShHealing`
- What it does: Run a named ShapeProcess operator/sequence (OCCT's scriptable fix pipeline — the engine behind many import options).
- Example: `shape-process imported SplitShape as imported`

#### `same-parameter`
- Syntax: `same-parameter <shape> [tol]`
- OCCT: `BRepLib::SameParameter / ShapeFix_Edge` — toolkit `TKTopAlgo/TKShHealing`
- What it does: Force edge 3D and 2D curves to share parametrisation within tolerance.
- Example: `same-parameter body1 as body1`

#### `update-tolerance`
- Syntax: `update-tolerance <shape> <tol> [faces|edges|vertices]`
- OCCT: `BRep_Tool / ShapeFix? BRepLib tolerance update via TopoDS tolerances (ShapeUpgrade? )` — toolkit `TKBRep`
- What it does: Set sub-shape tolerances (last-resort repair; loosening tolerance can hide real errors — output warns).
- Example: `update-tolerance imported 0.001 edges`

#### `orient-solid`
- Syntax: `orient-solid <solid>`
- OCCT: `BRepLib::OrientClosedSolid` — toolkit `TKTopAlgo`
- What it does: Orient a closed solid outward.
- Example: `orient-solid s1 as s1`

#### `build-solid`
- Syntax: `build-solid <shell> [tol]`
- OCCT: `BRepBuilderAPI_MakeSolid / ShapeFix_Solid` — toolkit `TKTopAlgo/TKShHealing`
- What it does: Make a solid from a (closed) shell.
- Example: `build-solid shell1 as solid1`

#### `build-shell`
- Syntax: `build-shell <face> ... `
- OCCT: `BRepBuilderAPI_Sewing + TopoDS_Shell via BRep_Builder` — toolkit `TKTopAlgo/TKBRep`
- What it does: Assemble faces into a shell without sewing (shared topology as-is).
- Example: `build-shell f1 f2 as shell1`

### Import / export (data exchange) (28)

#### `import-step`
- Syntax: `import-step <file> [as <name>] [mode shape|xcaf]`
- OCCT: `STEPControl_Reader / STEPCAFControl_Reader (XDE)` — toolkit `TKDESTEP/TKXCAF`
- What it does: Import STEP AP203/AP214/AP242. shape mode = geometry only; xcaf mode = assembly structure, names, colours, materials, GD&T where present.
- Example: `import-step bracket.step as body1 mode xcaf`

#### `export-step`
- Syntax: `export-step <shape> <file> [ap242|ap214|ap203] [units mm|in] [colours]`
- OCCT: `STEPControl_Writer / STEPCAFControl_Writer` — toolkit `TKDESTEP/TKXCAF`
- What it does: Export STEP with schema and unit choice; colours/names need the XDE writer.
- Example: `export-step body1 out.step ap242 colours`

#### `import-iges`
- Syntax: `import-iges <file> [as <name>]`
- OCCT: `IGESControl_Reader` — toolkit `TKDEIGES`
- What it does: Import IGES (surfaces/wires often arrive as sheets — follow with sew/heal).
- Example: `import-iges surf.iges as sheet1`

#### `export-iges`
- Syntax: `export-iges <shape> <file> [brep|faces]`
- OCCT: `IGESControl_Writer` — toolkit `TKDEIGES`
- What it does: Export IGES, B-Rep or face mode.
- Example: `export-iges body1 out.iges brep`

#### `import-brep`
- Syntax: `import-brep <file> [as <name>]`
- OCCT: `BRepTools::Read` — toolkit `TKBRep`
- What it does: Import OCCT native BREP text/binary shape file — lossless OCCT topology.
- Example: `import-brep part.brep as body1`

#### `export-brep`
- Syntax: `export-brep <shape> <file> [binary]`
- OCCT: `BRepTools::Write / BinTools::Write` — toolkit `TKBRep`
- What it does: Export native BREP (text) or binary BREP.
- Example: `export-brep body1 part.brep`

#### `save-xbf`
- Syntax: `save-xbf <shape|document> <file>`
- OCCT: `BinTools / PCDM via TDocStd + BinDrivers (XBF binary OCAF)` — toolkit `TKBRep/TKBin/TKCDF`
- What it does: Save in OCCT binary format (XBF / BinTools shape or full OCAF document).
- Example: `save-xbf body1 part.xbf`

#### `load-xbf`
- Syntax: `load-xbf <file> [as <name>]`
- OCCT: `BinTools::Read / BinDrivers retrieval` — toolkit `TKBRep/TKBin`
- What it does: Load XBF/binary BREP or document.
- Example: `load-xbf part.xbf as body1`

#### `save-xml`
- Syntax: `save-xml <document> <file>`
- OCCT: `XmlDrivers / TDocStd (OCAF XML persistence)` — toolkit `TKXml/TKCDF`
- What it does: Save the OCAF document as XML (XCAF structure included).
- Example: `save-xml doc part.xml`

#### `import-stl`
- Syntax: `import-stl <file> [as <name>]`
- OCCT: `StlAPI_Reader / RWStl::ReadFile` — toolkit `TKDESTL/TKRWMesh`
- What it does: Import STL as a faceted shell/compound of faces (NOT a smooth solid — see Limitations).
- Example: `import-stl mesh.stl as raw`

#### `export-stl`
- Syntax: `export-stl <shape> <file> [ascii|binary] [deflection <d>]`
- OCCT: `StlAPI_Writer` — toolkit `TKDESTL`
- What it does: Export STL, tessellating first with the given deflection.
- Example: `export-stl body1 out.stl binary deflection 0.1`

#### `import-obj`
- Syntax: `import-obj <file> [as <name>]`
- OCCT: `RWObj_Reader (RWMesh)` — toolkit `TKRWMesh/TKDEOBJ`
- What it does: Import Wavefront OBJ mesh.
- Example: `import-obj mesh.obj as raw`

#### `export-obj`
- Syntax: `export-obj <shape> <file>`
- OCCT: `RWObj_Writer` — toolkit `TKRWMesh/TKDEOBJ`
- What it does: Export OBJ from tessellation.
- Example: `export-obj body1 out.obj`

#### `import-gltf`
- Syntax: `import-gltf <file> [as <name>]`
- OCCT: `RWGltf_Reader` — toolkit `TKDEGLTF`
- What it does: Import glTF/GLB (mesh + materials/structure via XCAF).
- Example: `import-gltf scene.glb as raw`

#### `export-gltf`
- Syntax: `export-gltf <shape> <file> [binary]`
- OCCT: `RWGltf_Writer` — toolkit `TKDEGLTF`
- What it does: Export glTF/GLB from tessellation with colours/materials.
- Example: `export-gltf body1 out.glb binary`

#### `import-vrml`
- Syntax: `import-vrml <file> [as <name>]`
- OCCT: `VrmlAPI_CafReader / VrmlData (TKDEVRML)` — toolkit `TKDEVRML`
- What it does: Import VRML mesh/shape.
- Example: `import-vrml scene.wrl as raw`

#### `export-vrml`
- Syntax: `export-vrml <shape> <file>`
- OCCT: `VrmlAPI_Writer` — toolkit `TKDEVRML`
- What it does: Export VRML.
- Example: `export-vrml body1 out.wrl`

#### `import-ply`
- Syntax: `import-ply <file> [as <name>]`
- OCCT: `RWMesh PLY reader (TKDEPLY / RWMesh)` — toolkit `TKDEPLY/TKRWMesh`
- What it does: Import PLY mesh.
- Example: `import-ply scan.ply as raw`

#### `export-ply`
- Syntax: `export-ply <shape> <file>`
- OCCT: `RWMesh PLY writer` — toolkit `TKDEPLY/TKRWMesh`
- What it does: Export PLY from tessellation.
- Example: `export-ply body1 out.ply`

#### `import-dxf-note`
- Syntax: `import-dxf-note `
- OCCT: `— none in OCCT` — toolkit `—`
- What it does: DXF is NOT an OCCT format. No command; use STEP/IGES instead. Listed explicitly so nobody assumes it.
- Example: `—`

#### `xcaf-info`
- Syntax: `xcaf-info <document|shape>`
- OCCT: `XCAFDoc_ShapeTool (labels, assemblies, instances)` — toolkit `TKXCAF`
- What it does: Show XCAF assembly tree: labels, names, instances, locations.
- Example: `xcaf-info assembly1`

#### `xcaf-colours`
- Syntax: `xcaf-colours <shape|document>`
- OCCT: `XCAFDoc_ColorTool` — toolkit `TKXCAF`
- What it does: List XCAF colours per label/face (surface, curve, generic).
- Example: `xcaf-colours body1`

#### `xcaf-materials`
- Syntax: `xcaf-materials <shape|document>`
- OCCT: `XCAFDoc_VisMaterialTool / XCAFDoc_MaterialTool` — toolkit `TKXCAF`
- What it does: List XCAF materials / visual materials (PBR parameters stored in the file).
- Example: `xcaf-materials body1`

#### `xcaf-gdt`
- Syntax: `xcaf-gdt <shape|document>`
- OCCT: `XCAFDoc_DimTolTool (GD&T / dimensions & tolerances)` — toolkit `TKXCAF`
- What it does: List GD&T, datums, dimensions stored in a STEP AP242 XCAF document (read/display — OCCT does not enforce them in modelling).
- Example: `xcaf-gdt body1`

#### `xcaf-notes`
- Syntax: `xcaf-notes <shape|document>`
- OCCT: `XCAFDoc_NoteTool / XCAFNoteObjects` — toolkit `TKXCAF`
- What it does: List notes/annotations stored in the XCAF document.
- Example: `xcaf-notes body1`

#### `xcaf-views`
- Syntax: `xcaf-views <shape|document>`
- OCCT: `XCAFDoc_ViewTool / XCAFView` — toolkit `TKXCAF`
- What it does: List saved views/cameras stored in the document.
- Example: `xcaf-views body1`

#### `assembly-add`
- Syntax: `assembly-add <shape> into <assembly> [name ...] [place ...]`
- OCCT: `XCAFDoc_ShapeTool::AddComponent / NewShape` — toolkit `TKXCAF`
- What it does: Add a component instance to an XCAF assembly (instance shares geometry, carries its own location).
- Example: `assembly-add bolt into assembly1 place 10 0 0`

#### `units-file`
- Syntax: `units-file <file>`
- OCCT: `Interface_Static / STEPControl unit settings; UnitsMethods` — toolkit `TKXSBase/TKernel`
- What it does: Report/set the unit conversion applied on import/export (OCCT converts to mm).
- Example: `units-file bracket.step`

### Tessellation, HLR & BRep appearance (11)

#### `tessellate`
- Syntax: `tessellate <shape> deflection <d> [angle <deg>] [relative] [parallel]`
- OCCT: `BRepMesh_IncrementalMesh + IMeshTools_Parameters` — toolkit `TKMesh`
- What it does: Triangulate a shape's faces (the mesh the viewer and mesh exports use). Reports triangle count.
- Example: `tessellate body1 deflection 0.1 angle 15`

#### `mesh-info`
- Syntax: `mesh-info <shape>`
- OCCT: `TopoDS_Face triangulation via BRep_Tool::Triangulation / Poly_Triangulation` — toolkit `TKBRep`
- What it does: Report existing triangulation: triangles, nodes, deflection, per-face ranges.
- Example: `mesh-info body1`

#### `mesh-clear`
- Syntax: `mesh-clear <shape>`
- OCCT: `BRepTools::Clean` — toolkit `TKBRep`
- What it does: Remove stored triangulation from a shape.
- Example: `mesh-clear body1`

#### `mesh-check`
- Syntax: `mesh-check <shape>`
- OCCT: `Poly_Triangulation checks / BRepCheck on triangulation (app checks over Poly data)` — toolkit `TKBRep`
- What it does: Check stored mesh for degenerate triangles / free mesh edges.
- Example: `mesh-check body1`

#### `hlr`
- Syntax: `hlr <shape> view <dir> [outfile]`
- OCCT: `HLRBRep_Algo + HLRBRep_HLRToShape` — toolkit `TKHLR`
- What it does: Hidden-line-removal projection: visible/hidden sharp & smooth edges as 2D/3D edges — the technical-drawing edge set.
- Example: `hlr body1 view 0 -1 0`

#### `hlr-export`
- Syntax: `hlr-export <shape> view <dir> <file.step|brep>`
- OCCT: `HLRBRep_HLRToShape + STEP/BREP writer` — toolkit `TKHLR/TKDESTEP`
- What it does: Export HLR result (drawing linework) as shapes.
- Example: `hlr-export body1 view 1 0 0 drawing.brep`

#### `set-colour`
- Syntax: `set-colour <shape|face-selector> colour <r g b|name>`
- OCCT: `XCAFDoc_ColorTool::SetColor (XDE) / Quantity_Color` — toolkit `TKXCAF/TKernel`
- What it does: Set BRep/XCAF surface colour on a shape or face. Without an XCAF document this is document metadata, not geometry.
- Example: `set-colour body1 colour 0.2 0.5 0.9`

#### `set-transparency`
- Syntax: `set-transparency <shape> alpha <0..1>`
- OCCT: `XCAFDoc_VisMaterial / Graphic3d transparency stored via XCAFDoc_ColorTool+VisMaterialTool` — toolkit `TKXCAF/TKService`
- What it does: Set transparency as XCAF visual material data.
- Example: `set-transparency body1 alpha 0.4`

#### `set-material`
- Syntax: `set-material <shape> material <name> [pbr metalness <m> roughness <r> basecolour ...]`
- OCCT: `XCAFDoc_VisMaterialTool (Graphic3d_MaterialAspect / PBR)` — toolkit `TKXCAF/TKService`
- What it does: Attach an XCAF visual material (incl. PBR parameters) — data carried through STEP/glTF; shading itself is the viewer's job.
- Example: `set-material body1 material steel pbr metalness 0.9 roughness 0.35`

#### `face-colours`
- Syntax: `face-colours <shape>`
- OCCT: `XCAFDoc_ColorTool::GetColor per face (as in cascade-port mc_shape_face_colors)` — toolkit `TKXCAF`
- What it does: Report per-face colours carried by an imported XDE file.
- Example: `face-colours body1`

#### `texture-note`
- Syntax: `texture-note `
- OCCT: `XCAFDoc_VisMaterial textures (Graphic3d_TextureParams data)` — toolkit `TKXCAF/TKService`
- What it does: OCCT XCAF can STORE texture references in visual materials, but OCCT does not UV-unwrap or texture-map B-Rep faces for you — listed as storage-only.
- Example: `—`

### Interference, section & advanced geometry (18)

#### `interference`
- Syntax: `interference <a> <b>`
- OCCT: `BRepAlgoAPI_Common volume + BOPAlgo check / IntTools_FaceFace` — toolkit `TKBO/TKTopAlgo`
- What it does: Interference report: do the solids overlap, and by what volume (common > 0)? Distinct from measure-distance (=0 when touching/overlapping).
- Example: `interference body1 body2`

#### `clearance`
- Syntax: `clearance <a> <b> min <d>`
- OCCT: `BRepExtrema_DistShapeShape vs threshold` — toolkit `TKTopAlgo`
- What it does: Pass/fail clearance check against a minimum gap.
- Example: `clearance body1 body2 min 1.0`

#### `section`
- Syntax: `section <shape> by plane x y z nx ny nz [as <name>]`
- OCCT: `BRepAlgoAPI_Section with a plane face` — toolkit `TKBO`
- What it does: Section edges of a shape cut by a plane (open result, not a solid).
- Example: `section body1 by plane 0 0 15 0 0 1 as sect1`

#### `section-solid`
- Syntax: `section-solid <shape> by plane ... keep above|below`
- OCCT: `BRepAlgoAPI_Cut/Splitter with halfspace` — toolkit `TKBO/TKPrim`
- What it does: Cut a solid at a plane and keep one side (a capped section solid — via splitter + selection).
- Example: `section-solid body1 by plane 0 0 15 0 0 1 keep below as half`

#### `slice`
- Syntax: `slice <shape> planes z=<list> `
- OCCT: `Repeated BRepAlgoAPI_Section (app loop)` — toolkit `TKBO`
- What it does: Multiple parallel sections at once (contour slices).
- Example: `slice body1 planes z=5,10,15 as contours`

#### `intersect-curves`
- Syntax: `intersect-curves <edge1> <edge2>`
- OCCT: `GeomAPI_IntCS / IntCurves? GeomInt_IntSS / BRepIntCurveSurface` — toolkit `TKGeomAlgo`
- What it does: Intersection points/curves between curves/surfaces.
- Example: `intersect-curves e1 e2`

#### `intersect-surface`
- Syntax: `intersect-surface <face1> <face2>`
- OCCT: `GeomInt_IntSS / BRepAlgoAPI_Section on faces` — toolkit `TKGeomAlgo/TKBO`
- What it does: Surface-surface intersection curve(s).
- Example: `intersect-surface f1 f2`

#### `extrema`
- Syntax: `extrema <shape> <shape> [all solutions]`
- OCCT: `BRepExtrema_DistShapeShape (all solutions mode)` — toolkit `TKTopAlgo`
- What it does: All local distance extrema solutions between shapes, not just the minimum.
- Example: `extrema e1 f1 all solutions`

#### `fair-curve`
- Syntax: `fair-curve <points> [tolerance] [smoothing]`
- OCCT: `FairCurve_Batten / FairCurve_MinimalVariation` — toolkit `TKGeomAlgo`
- What it does: Fair (ship-curve style) a curve: batten/minimal-variation smoothing — OCCT's FairCurve package.
- Example: `fair-curve pts tolerance 0.1 as faired`

#### `approx-curve`
- Syntax: `approx-curve <points|edge> [tol] [continuity] [maxdegree]`
- OCCT: `GeomAPI_PointsToBSpline / Approx_Curve3d / AdvApprox` — toolkit `TKGeomAlgo/TKGeomBase`
- What it does: Approximate points or a curve by a B-spline within tolerance.
- Example: `approx-curve pts tol 0.05 as approx1`

#### `approx-surface`
- Syntax: `approx-surface <points grid> [tol]`
- OCCT: `GeomAPI_PointsToBSplineSurface / Approx_Surface` — toolkit `TKGeomAlgo`
- What it does: Approximate a point grid by a B-spline surface.
- Example: `approx-surface grid.csv tol 0.05 as surf`

#### `convert-curve`
- Syntax: `convert-curve <edge> to bspline|bezier`
- OCCT: `GeomConvert_CurveToBSplineCurve / GeomConvert_ApproxCurve` — toolkit `TKGeomBase`
- What it does: Convert a curve to B-spline/Bezier form.
- Example: `convert-curve e1 to bspline as e1b`

#### `split-curve`
- Syntax: `split-curve <edge> at <u> | at point ...`
- OCCT: `GeomConvert_SplitBSplineCurve / ShapeUpgrade_SplitCurve3d` — toolkit `TKGeomBase/TKShHealing`
- What it does: Split a curve at parameters.
- Example: `split-curve spline1 at 0.5 as s_a s_b`

#### `split-surface`
- Syntax: `split-surface <face> at u <u> | v <v>`
- OCCT: `GeomConvert_SplitBSplineSurface / ShapeUpgrade_SplitSurface` — toolkit `TKGeomBase/TKShHealing`
- What it does: Split a surface at parameters.
- Example: `split-surface skin at u 0.5`

#### `merge-curves`
- Syntax: `merge-curves <edge1> <edge2> ...`
- OCCT: `ShapeUpgrade_UnifySameDomain (edges) / GeomConvert_ConcatBSplineCurve` — toolkit `TKShHealing/TKGeomBase`
- What it does: Merge C1-connected collinear/co-circular edges into one.
- Example: `merge-curves e1 e2 as e_all`

#### `project-point`
- Syntax: `project-point x y z onto <face|edge>`
- OCCT: `GeomAPI_ProjectPointOnSurf / GeomAPI_ProjectPointOnCurve` — toolkit `TKGeomAlgo`
- What it does: Project a point; reports projected point, distance, parameters.
- Example: `project-point 10 10 10 onto face1`

#### `surface-from-points`
- Syntax: `surface-from-points <csv|points> [tol]`
- OCCT: `GeomAPI_PointsToBSplineSurface` — toolkit `TKGeomAlgo`
- What it does: Interpolating/approximating surface through a point cloud grid (reverse-engineering helper).
- Example: `surface-from-points scan.csv as surf`

#### `points-from-shape`
- Syntax: `points-from-shape <shape> [spacing]`
- OCCT: `BRepMesh nodes / GCPnts_QuasiUniformDeflection sampling (app sampling over OCCT)` — toolkit `TKMesh/TKGeomBase`
- What it does: Sample points on edges/faces (for inspection exports).
- Example: `points-from-shape body1 spacing 2`

### Viewing (app layer, OCCT-fed) (7)

#### `view`
- Syntax: `view <name> [fit]`
- OCCT: `— app viewer (Metal tessellation from BRepMesh_IncrementalMesh)` — toolkit `TKMesh (source data)`
- What it does: Show the named shape in the 3D viewer. The viewer is the app's, not OCCT's AIS/OpenGL — OCCT supplies the triangulation.
- Example: `view body1`

#### `view-all`
- Syntax: `view-all `
- OCCT: `— app viewer over all named shapes' triangulations` — toolkit `TKMesh`
- What it does: Show every named shape.
- Example: `view-all`

#### `hide`
- Syntax: `hide <name>`
- OCCT: `— app viewer state` — toolkit `—`
- What it does: Hide a shape in the viewer (geometry untouched).
- Example: `hide tmp1`

#### `show`
- Syntax: `show <name>`
- OCCT: `— app viewer state` — toolkit `—`
- What it does: Show a hidden shape.
- Example: `show tmp1`

#### `view-mode`
- Syntax: `view-mode shaded|wireframe|shaded-edges|transparent`
- OCCT: `— app viewer state (source: Poly_Triangulation + HLR edges optionally)` — toolkit `TKMesh/TKHLR`
- What it does: Viewer display mode.
- Example: `view-mode shaded-edges`

#### `screenshot`
- Syntax: `screenshot <file.png>`
- OCCT: `— app viewer render to file` — toolkit `—`
- What it does: Save a viewer screenshot (app feature, not OCCT).
- Example: `screenshot out.png`

#### `export-drawing`
- Syntax: `export-drawing <shape> view <dir> <file>`
- OCCT: `HLRBRep_HLRToShape + writer (see hlr-export)` — toolkit `TKHLR`
- What it does: Alias kept for discoverability; same OCCT HLR engine.
- Example: `export-drawing body1 view 0 -1 0 front.brep`

## What OCCT does NOT provide — do not fake these

This section is binding on every other agent. If a user-facing feature sits here, it is either **not offered**, or **offered as the app's own code on top of OCCT geometry, labelled as such, with true computed results only**.

1. **No FEM / simulation solver.** OCCT has no finite-element solver, no volume (tetrahedral) mesher, and no stress/thermal/modal analysis. `TKDESTEP` contains `RWStepFEA` classes — those only *read/write FEA data inside STEP files*; they solve nothing. `BRepMesh_IncrementalMesh` makes **surface** triangles for display/export, not an analysis mesh. The cascade-port façade's old section 11 was the project's **own** voxel mesher + linear-static solver standing on OCCT queries — that is the honest pattern if Cascade Console offers 'simulation': own solver, own mesher, true solver output, labelled non-OCCT. Never present a coloured picture that did not come out of a real solve.
2. **No sketch constraint solver.** OCCT has geometric *construction* solvers for individual tangency/incidence problems (`GccAna`, `Geom2dGcc`, `GccInt` — used inside fillet/construction code), but no parametric sketcher: no coincident/perpendicular/dimension constraints, no degrees-of-freedom solving, no driving dimensions that update a model. FreeCAD's Sketcher is FreeCAD code, not OCCT. Cascade Console 'sketches' are exact numeric OCCT edges on a plane (see `sketch-*` commands). Any future constraint feature is new app code and must be labelled as such.
3. **No parametric feature history / design tree.** OCCT shapes are final B-Rep results. `TNaming`/`BRepTools_History` record *what a boolean did to sub-shapes*, and OCAF (`TDocStd`) gives document structure + undo transactions, but there is no feature tree that replays 'edit the pad length and everything rebuilds'. The app may keep its own command log and re-run it — that is an app feature (script replay), not OCCT parametric modelling, and it must be described that way.
4. **No assembly mate solver.** XCAF (`XCAFDoc_ShapeTool`) stores assembly structure, instances and locations. OCCT does not solve coincident/gear/ball mates or do kinematic/dynamics simulation. Placement is by explicit transform/location commands.
5. **No CAM, no toolpaths, no slicer, no G-code.** Nothing in OCCT generates machining or printing toolpaths.
6. **No material/physics database.** XCAF can *store* materials, visual (PBR) materials, densities and GD&T from files, and `mass` above is volume × a user-supplied density. OCCT ships no material library and no physical properties of its own.
7. **GD&T is storage, not enforcement.** `XCAFDoc_DimTolTool` reads/writes dimensions, datums and tolerances from STEP AP242. OCCT does not check a model against them or drive geometry from them.
8. **Mesh files are meshes.** STL/OBJ/PLY/glTF/VRML import gives faceted shapes (`Poly_Triangulation` / faceted shells). OCCT does not turn a mesh into a smooth analytic solid; `sew`+`heal` can close a clean mesh into a faceted solid, and defeaturing/fillets on faceted shapes will mostly fail — the console must say so instead of pretending a conversion happened. (Fitting surfaces to a mesh is approximation work — `approx-surface`/`surface-from-points` — and its output must carry its measured tolerance.)
9. **No true single-class pattern, helix, or texture-mapping operations.** Linear/polar patterns are app loops over `gp_Trsf` + booleans; a helix is a constructed curve (diagonal on a cylinder), not a `MakeHelix` class; XCAF stores texture references but OCCT does not UV-unwrap B-Rep faces. All three are labelled as constructions in their command entries.
10. **No DXF, DWG, SolidWorks/Fusion native formats.** OCCT data exchange is STEP, IGES, BREP/XBF (native), STL, OBJ, glTF, VRML, PLY. DWG and proprietary CAD formats are not supported by OCCT at all.
11. **No rendering engine for the app.** OCCT's visualisation (TKV3d/TKOpenGl/AIS) is a desktop OpenGL viewer stack; on Mac/iPad the app uses its own Metal viewer fed by `BRepMesh_IncrementalMesh` triangulations and `HLRBRep` edge sets. Shading, Liquid Glass UI, picking visuals etc. are app code.
12. **No unit-test of truth for 'simulation and others'.** Modern-CAD extras the user asked for that are *not* OCCT — interference/clearance **are** OCCT-backed (above), but versioning, cloud sync, collaboration, rendering/ray-tracing, and print preparation are app/platform features and must not be attributed to OCCT in the user guide or UI.

## Licensing & attribution (binding)

- OCCT 8.0.1 is © Open Cascade SAS, licensed **LGPL 2.1 with the Open CASCADE exception**.
- The licence texts `OCCT/LICENSE_LGPL_21.txt` and `OCCT/OCCT_LGPL_EXCEPTION.txt` must ship in the repo and in/near the app (About/Settings screen credit: 'Geometry by Open CASCADE Technology (OCCT), © Open Cascade SAS, LGPL 2.1 + OCCT exception').
- OCCT sources must not be modified; if any ever are, the modifications must be disclosed and those files stay LGPL (standing rule from the cascade-ios work).
- The app's own code is separate work linking OCCT through the façade — keep that separation (façade = pass-through wrappers, no geometry logic of its own) so the licence boundary stays clean.
- No contributor's real name appears in public artifacts for this project; use 'user'.

## Gaps & open questions for the parent

- **Toolkit expansion is the critical path** (see Build gaps): roughly a third of this catalog (IGES/STL/glTF/OBJ/VRML/PLY, HLR, features, XBF/XML persistence) is not in the current cascade-port subset build. Catalog is written against full OCCT 8.0.1, as commissioned ('every feature'), with the build delta named rather than hidden.
- **TKXMesh / TKMeshVS / TKTObj family** were not given commands beyond mesh storage: TKXMesh is mostly an internal extension of mesh data structures, and MeshVS is a desktop-visualisation mesh presenter superseded by the app's Metal viewer. If the engine agent finds a user-meaningful TKXMesh operation, add it to the JSON first, then regenerate this file.
- **`import-dxf-note` is a deliberate non-command** in the JSON (occt_class '— none in OCCT') so consumers can surface an honest 'not supported' instead of a missing entry.
- A small number of entries are **labelled app constructions** (patterns, helix route, spiral approximation, thickness-at ray cast, draft-check, mass). Their `occt_class` fields name the real OCCT pieces they compose; the façade agent should implement them exactly as those compositions, or drop the command rather than approximate silently.
- Command grammar is a proposal: the parser agent may normalise keyword spelling, but must not drop commands silently — any cut command needs a note in the JSON (`"status":"deferred"`) and a reason.
