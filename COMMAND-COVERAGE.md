# Cascade Console — Command Coverage

Generated at integration from `docs/catalog/catalog.json` (251 catalog commands) plus the one app-layer session command added by resolution (a) = **252 rows**.

Status meanings:
- **implemented-in-prototype** — the Python reference interpreter in `Core/` executes it end-to-end today (host, OCCT 7.8).
- **facade-ready** — every OCCT toolkit the command needs is present in the staged cascade-port OCCT 8.0.1 tree (35 toolkits); what remains is Layer-2 dispatch in the C++ session interpreter and, where Layer 1 has no wrap yet, a new `mc_*` function. NOT yet executable.
- **toolkit-missing** — at least one required toolkit is not in the staged tree (see `docs/BUILD-PLAN-OCCT-TOOLKITS.md`). Until it is added, the command MUST return NOT_IMPLEMENTED (E5002 / CC-SYS-000) — never a fake result.
- **app-layer** — implemented by the app/viewer/session layer, not by an OCCT toolkit (may consume OCCT-fed data).

## Counts

- implemented-in-prototype: **24**
- facade-ready: **212**
- toolkit-missing: **7**
- app-layer: **9**

## Table

| Command | Category | Toolkit(s) | Status | Note |
|---|---|---|---|---|
| `new` | Session & naming | TKBRep/TKLCAF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `set` | Session & naming | TKExpress | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `show-vars` | Session & naming | TKExpress | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `units` | Session & naming | TKernel | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `precision` | Session & naming | TKernel | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `rename` | Session & naming | TKCAF/TKXCAF | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `list` | Session & naming | TKBRep | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `delete` | Session & naming | TKBRep/TKLCAF | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `duplicate` | Session & naming | TKTopAlgo | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `shape-history` | Session & naming | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `undo` | Session & naming | TKCAF | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `redo` | Session & naming | TKCAF | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `box` | Primitives (solids) | TKPrim | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `wedge` | Primitives (solids) | TKPrim | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `cylinder` | Primitives (solids) | TKPrim | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `cone` | Primitives (solids) | TKPrim | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `sphere` | Primitives (solids) | TKPrim | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `torus` | Primitives (solids) | TKPrim | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `halfspace` | Primitives (solids) | TKPrim | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `prism-solid` | Primitives (solids) | TKPrim | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `revolution-solid` | Primitives (solids) | TKPrim | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `point` | Points, curves & edges | TKMath | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `vertex` | Points, curves & edges | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `line` | Points, curves & edges | TKGeomBase/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `infinite-line` | Points, curves & edges | TKG3d/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `circle` | Points, curves & edges | TKGeomBase/TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `arc` | Points, curves & edges | TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `ellipse` | Points, curves & edges | TKGeomBase/TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `hyperbola` | Points, curves & edges | TKGeomBase/TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `parabola` | Points, curves & edges | TKGeomBase/TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `bezier` | Points, curves & edges | TKG3d/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `bspline` | Points, curves & edges | TKG3d/TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `interpolate` | Points, curves & edges | TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `trim` | Points, curves & edges | TKG3d/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `offset-curve` | Points, curves & edges | TKG3d/TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `project-curve` | Points, curves & edges | TKGeomAlgo/TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `extend-curve` | Points, curves & edges | TKGeomBase/TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `helix` | Points, curves & edges | TKG3d/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `spiral` | Points, curves & edges | TKG3d/TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `curve-length` | Points, curves & edges | TKGeomBase/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `curve-point` | Points, curves & edges | TKG3d/TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `curve-curvature` | Points, curves & edges | TKGeomBase/TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `plane` | Surfaces & faces | TKG3d/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `cylindrical-surface` | Surfaces & faces | TKG3d/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `conical-surface` | Surfaces & faces | TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `spherical-surface` | Surfaces & faces | TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `toroidal-surface` | Surfaces & faces | TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `surface-of-revolution` | Surfaces & faces | TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `surface-of-extrusion` | Surfaces & faces | TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `bezier-surface` | Surfaces & faces | TKG3d/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `bspline-surface` | Surfaces & faces | TKG3d/TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fill-surface` | Surfaces & faces | TKOffset/TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `plate-surface` | Surfaces & faces | TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `offset-surface` | Surfaces & faces | TKG3d/TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `surface-point` | Surfaces & faces | TKG3d/TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `surface-uv` | Surfaces & faces | TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `ruled-surface` | Surfaces & faces | TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `wire` | Wires, profiles & sketches | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `polygon` | Wires, profiles & sketches | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `face` | Wires, profiles & sketches | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `face-with-holes` | Wires, profiles & sketches | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `rectangle` | Wires, profiles & sketches | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `circle-profile` | Wires, profiles & sketches | TKGeomBase/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `slot-profile` | Wires, profiles & sketches | TKGeomBase/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `sketch-begin` | Wires, profiles & sketches | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `sketch-line` | Wires, profiles & sketches | TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `sketch-arc` | Wires, profiles & sketches | TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `sketch-circle` | Wires, profiles & sketches | TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `sketch-spline` | Wires, profiles & sketches | TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `sketch-end` | Wires, profiles & sketches | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `check-wire` | Wires, profiles & sketches | TKTopAlgo/TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `order-wire` | Wires, profiles & sketches | TKShHealing/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `extrude` | Extrude, revolve, loft, sweep & features | TKPrim | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `extrude-symmetric` | Extrude, revolve, loft, sweep & features | TKPrim | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `extrude-to-face` | Extrude, revolve, loft, sweep & features | TKFeat | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `revolve` | Extrude, revolve, loft, sweep & features | TKPrim | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `loft` | Extrude, revolve, loft, sweep & features | TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `sweep` | Extrude, revolve, loft, sweep & features | TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `pipe` | Extrude, revolve, loft, sweep & features | TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `pipe-shell` | Extrude, revolve, loft, sweep & features | TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `variable-sweep` | Extrude, revolve, loft, sweep & features | TKOffset/TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `helix-sweep` | Extrude, revolve, loft, sweep & features | TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fill-sweep` | Extrude, revolve, loft, sweep & features | TKBool/TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `groove` | Extrude, revolve, loft, sweep & features | TKFeat | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `hole-feature` | Extrude, revolve, loft, sweep & features | TKFeat | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `rib-feature` | Extrude, revolve, loft, sweep & features | TKFeat | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `dprism-feature` | Extrude, revolve, loft, sweep & features | TKFeat | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `linear-feature` | Extrude, revolve, loft, sweep & features | TKFeat | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `glued-feature` | Extrude, revolve, loft, sweep & features | TKFeat | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `split-feature` | Extrude, revolve, loft, sweep & features | TKFeat | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fuse` | Booleans & defeaturing | TKBO/TKBool | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `cut` | Booleans & defeaturing | TKBO/TKBool | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `common` | Booleans & defeaturing | TKBO/TKBool | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `section-boolean` | Booleans & defeaturing | TKBO/TKBool | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `split` | Booleans & defeaturing | TKBO/TKBool | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `boolean-multi` | Booleans & defeaturing | TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `boolean-options` | Booleans & defeaturing | TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `defeature` | Booleans & defeaturing | TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `halfspace-cut` | Booleans & defeaturing | TKPrim/TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fillet` | Fillet, chamfer, shell, offset & draft | TKFillet | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `fillet-variable` | Fillet, chamfer, shell, offset & draft | TKFillet | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fillet-law` | Fillet, chamfer, shell, offset & draft | TKFillet | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `chamfer` | Fillet, chamfer, shell, offset & draft | TKFillet | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `chamfer-2d` | Fillet, chamfer, shell, offset & draft | TKFillet | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fillet-2d` | Fillet, chamfer, shell, offset & draft | TKFillet | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `shell` | Fillet, chamfer, shell, offset & draft | TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `thicken` | Fillet, chamfer, shell, offset & draft | TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `offset-shape` | Fillet, chamfer, shell, offset & draft | TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `offset-face` | Fillet, chamfer, shell, offset & draft | TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `draft` | Fillet, chamfer, shell, offset & draft | TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `draft-check` | Fillet, chamfer, shell, offset & draft | TKOffset/TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `sew-then-shell` | Fillet, chamfer, shell, offset & draft | TKShHealing/TKOffset | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `translate` | Transforms & patterns | TKMath/TKTopAlgo | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `rotate` | Transforms & patterns | TKMath/TKTopAlgo | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `scale` | Transforms & patterns | TKMath/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `gtransform` | Transforms & patterns | TKTopAlgo/TKMath | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `mirror` | Transforms & patterns | TKMath/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `move-to` | Transforms & patterns | TKBRep/TKMath | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `location` | Transforms & patterns | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `linear-pattern` | Transforms & patterns | TKMath/TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `polar-pattern` | Transforms & patterns | TKMath/TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `rect-pattern` | Transforms & patterns | TKMath/TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `mirror-pattern` | Transforms & patterns | TKMath/TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `copy-transform` | Transforms & patterns | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `info` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `type` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `solids` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `faces` | Topology, inspection & selection | TKBRep/TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `edges` | Topology, inspection & selection | TKBRep/TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `wires` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `vertices` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `shells` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `face-info` | Topology, inspection & selection | TKG3d/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `edge-info` | Topology, inspection & selection | TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `adjacent` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `shared` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `same-domain` | Topology, inspection & selection | TKShHealing/TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `orientation` | Topology, inspection & selection | TKBRep/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `free-edges` | Topology, inspection & selection | TKShHealing/TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `check` | Topology, inspection & selection | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `contains` | Topology, inspection & selection | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `classify` | Topology, inspection & selection | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `explode` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `compound` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `compsolid` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `extract` | Topology, inspection & selection | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `measure-distance` | Measurement & analysis | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `measure-length` | Measurement & analysis | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `measure-area` | Measurement & analysis | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `measure-volume` | Measurement & analysis | TKTopAlgo | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `centre-of-mass` | Measurement & analysis | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `inertia` | Measurement & analysis | TKTopAlgo/TKMath | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `moment` | Measurement & analysis | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `bbox` | Measurement & analysis | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `bbox-gap` | Measurement & analysis | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `angle-between` | Measurement & analysis | TKG3d/TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `radius` | Measurement & analysis | TKG3d | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `perimeter` | Measurement & analysis | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `cross-section` | Measurement & analysis | TKBO/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `thickness-at` | Measurement & analysis | TKTopAlgo/TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `mass` | Measurement & analysis | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `heal` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fix-wire` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fix-face` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fix-shell` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fix-solid` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fix-edge` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `sew` | Healing, sewing & shape fix | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `unify` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `remove-split` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `convert-to-bspline` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `convert-to-revolution` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `bspline-restriction` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `direct-faces` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `analyse-surface` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `analyse-curve` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `analyse-freebounds` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `analyse-shell` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `small-edges` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `spot-face` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `strip-face` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `shape-process` | Healing, sewing & shape fix | TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `same-parameter` | Healing, sewing & shape fix | TKTopAlgo/TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `update-tolerance` | Healing, sewing & shape fix | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `orient-solid` | Healing, sewing & shape fix | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `build-solid` | Healing, sewing & shape fix | TKTopAlgo/TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `build-shell` | Healing, sewing & shape fix | TKTopAlgo/TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `import-step` | Import / export (data exchange) | TKDESTEP/TKXCAF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `export-step` | Import / export (data exchange) | TKDESTEP/TKXCAF | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `import-iges` | Import / export (data exchange) | TKDEIGES | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `export-iges` | Import / export (data exchange) | TKDEIGES | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `import-brep` | Import / export (data exchange) | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `export-brep` | Import / export (data exchange) | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `save-xbf` | Import / export (data exchange) | TKBRep/TKBin/TKCDF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `load-xbf` | Import / export (data exchange) | TKBRep/TKBin | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `save-xml` | Import / export (data exchange) | TKXml/TKCDF | toolkit-missing | needs TKXml — not in the staged cascade-port tree; must answer NOT_IMPLEMENTED (E5002 / CC-SYS-000) |
| `import-stl` | Import / export (data exchange) | TKDESTL/TKRWMesh | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `export-stl` | Import / export (data exchange) | TKDESTL | implemented-in-prototype | Python prototype (Core/) executes it end-to-end over OCCT 7.8 |
| `import-obj` | Import / export (data exchange) | TKRWMesh/TKDEOBJ | toolkit-missing | needs TKDEOBJ — not in the staged cascade-port tree; must answer NOT_IMPLEMENTED (E5002 / CC-SYS-000) |
| `export-obj` | Import / export (data exchange) | TKRWMesh/TKDEOBJ | toolkit-missing | needs TKDEOBJ — not in the staged cascade-port tree; must answer NOT_IMPLEMENTED (E5002 / CC-SYS-000) |
| `import-gltf` | Import / export (data exchange) | TKDEGLTF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `export-gltf` | Import / export (data exchange) | TKDEGLTF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `import-vrml` | Import / export (data exchange) | TKDEVRML | toolkit-missing | needs TKDEVRML — not in the staged cascade-port tree; must answer NOT_IMPLEMENTED (E5002 / CC-SYS-000) |
| `export-vrml` | Import / export (data exchange) | TKDEVRML | toolkit-missing | needs TKDEVRML — not in the staged cascade-port tree; must answer NOT_IMPLEMENTED (E5002 / CC-SYS-000) |
| `import-ply` | Import / export (data exchange) | TKDEPLY/TKRWMesh | toolkit-missing | needs TKDEPLY — not in the staged cascade-port tree; must answer NOT_IMPLEMENTED (E5002 / CC-SYS-000) |
| `export-ply` | Import / export (data exchange) | TKDEPLY/TKRWMesh | toolkit-missing | needs TKDEPLY — not in the staged cascade-port tree; must answer NOT_IMPLEMENTED (E5002 / CC-SYS-000) |
| `import-dxf-note` | Import / export (data exchange) | — | app-layer | app/viewer layer (OCCT-fed), no toolkit required |
| `xcaf-info` | Import / export (data exchange) | TKXCAF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `xcaf-colours` | Import / export (data exchange) | TKXCAF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `xcaf-materials` | Import / export (data exchange) | TKXCAF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `xcaf-gdt` | Import / export (data exchange) | TKXCAF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `xcaf-notes` | Import / export (data exchange) | TKXCAF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `xcaf-views` | Import / export (data exchange) | TKXCAF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `assembly-add` | Import / export (data exchange) | TKXCAF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `units-file` | Import / export (data exchange) | TKXSBase/TKernel | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `tessellate` | Tessellation, HLR & BRep appearance | TKMesh | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `mesh-info` | Tessellation, HLR & BRep appearance | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `mesh-clear` | Tessellation, HLR & BRep appearance | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `mesh-check` | Tessellation, HLR & BRep appearance | TKBRep | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `hlr` | Tessellation, HLR & BRep appearance | TKHLR | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `hlr-export` | Tessellation, HLR & BRep appearance | TKHLR/TKDESTEP | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `set-colour` | Tessellation, HLR & BRep appearance | TKXCAF/TKernel | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `set-transparency` | Tessellation, HLR & BRep appearance | TKXCAF/TKService | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `set-material` | Tessellation, HLR & BRep appearance | TKXCAF/TKService | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `face-colours` | Tessellation, HLR & BRep appearance | TKXCAF | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `texture-note` | Tessellation, HLR & BRep appearance | TKXCAF/TKService | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `interference` | Interference, section & advanced geometry | TKBO/TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `clearance` | Interference, section & advanced geometry | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `section` | Interference, section & advanced geometry | TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `section-solid` | Interference, section & advanced geometry | TKBO/TKPrim | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `slice` | Interference, section & advanced geometry | TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `intersect-curves` | Interference, section & advanced geometry | TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `intersect-surface` | Interference, section & advanced geometry | TKGeomAlgo/TKBO | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `extrema` | Interference, section & advanced geometry | TKTopAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `fair-curve` | Interference, section & advanced geometry | TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `approx-curve` | Interference, section & advanced geometry | TKGeomAlgo/TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `approx-surface` | Interference, section & advanced geometry | TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `convert-curve` | Interference, section & advanced geometry | TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `split-curve` | Interference, section & advanced geometry | TKGeomBase/TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `split-surface` | Interference, section & advanced geometry | TKGeomBase/TKShHealing | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `merge-curves` | Interference, section & advanced geometry | TKShHealing/TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `project-point` | Interference, section & advanced geometry | TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `surface-from-points` | Interference, section & advanced geometry | TKGeomAlgo | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `points-from-shape` | Interference, section & advanced geometry | TKMesh/TKGeomBase | facade-ready | all required toolkits are in the staged tree; Layer-2 dispatch + (where needed) a new mc_* wrap remain |
| `view` | Viewing (app layer, OCCT-fed) | TKMesh (source data) | app-layer | app/viewer layer (OCCT-fed), no toolkit required |
| `view-all` | Viewing (app layer, OCCT-fed) | TKMesh | app-layer | app/viewer layer (OCCT-fed), no toolkit required |
| `hide` | Viewing (app layer, OCCT-fed) | — | app-layer | app/viewer layer (OCCT-fed), no toolkit required |
| `show` | Viewing (app layer, OCCT-fed) | — | app-layer | app/viewer layer (OCCT-fed), no toolkit required |
| `view-mode` | Viewing (app layer, OCCT-fed) | TKMesh/TKHLR | app-layer | app/viewer layer (OCCT-fed), no toolkit required |
| `screenshot` | Viewing (app layer, OCCT-fed) | — | app-layer | app/viewer layer (OCCT-fed), no toolkit required |
| `export-drawing` | Viewing (app layer, OCCT-fed) | TKHLR | app-layer | app/viewer layer (OCCT-fed), no toolkit required |
| `history` | Session & naming (app layer) | — | app-layer | session command log; prototype implements it (Core/python/cc/interpreter.py cmd_history). Added at integration, resolution (a) — not a catalog entry. |
