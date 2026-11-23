# OCCT Toolkit Build Plan — closing the catalog's build gaps

## Where the build actually stands (checked at integration, 2026-11-23)

Agent 1's catalog flagged ~1/3 of the 251 commands as needing extra
toolkits beyond "the current cascade-port build closure". Checking the
actual staged tree (`~/workspace/cascade-port/OCCT/src/`,
`MANIFEST.md`) shows that picture is **out of date**: the FreeCAD
extension of 2026-10-29 already staged 12 more toolkits additively, and
the tree now holds **35 toolkits, 5,234 compilable sources**:

FoundationClasses: TKernel, TKMath · ModelingData: TKG2d, TKG3d,
TKGeomBase, TKBRep · ModelingAlgorithms: TKGeomAlgo, TKTopAlgo,
TKPrim, TKBO, TKBool, **TKHLR**, TKFillet, TKOffset, **TKFeat**,
TKMesh, TKShHealing, **TKExpress** · Visualization: TKService
(partial), TKV3d, TKMeshVS · ApplicationFramework: TKCDF, TKLCAF,
TKCAF, TKBinL, **TKBin**, TKVCAF · DataExchange: TKXSBase, TKDE,
TKDESTEP, **TKDEIGES**, **TKDESTL**, **TKDEGLTF**, **TKRWMesh**, TKXCAF

(bold = on Agent 1's gap list, already staged). Cascade Console does
not use TKV3d/TKService's viewer machinery (its viewer is the Metal
viewer in `Shared/Viewer/`); those toolkits are staged only as data
dependencies.

## What is genuinely still missing

Only **7 of 251 catalog commands** are blocked on a missing toolkit
(see `COMMAND-COVERAGE.md`):

| Toolkit to add | Commands it unblocks | Notes |
|---|---|---|
| TKDEOBJ | `import-obj`, `export-obj` | OBJ via RWMesh |
| TKDEVRML | `import-vrml`, `export-vrml` | VRML reader/writer |
| TKDEPLY | `import-ply`, `export-ply` | PLY via RWMesh |
| TKXml (+ TKXmlL, and TKStd/TKStdL if the closure requires them) | `save-xml` | XML document persistence. `save-xbf`/`load-xbf` already work: TKBin + TKBinL are staged. |

Plus one optional toolkit: **TKXMesh** (extended mesh exchange) — no
catalog command requires it today; add only if extended mesh ops are
wanted.

## Method (the cascade-port rule, unchanged)

1. Take the files from the **official OCCT 8.0.1 release tarball**
   (GitHub `Open-Cascade-SAS/OCCT` tag `V8_0_1`, sha256
   `0d6913eae4bcc09a3653ceced6dda1aec11c35a1513d4c06762c9b002092c68a`
   — the same source the existing tree was byte-verified against).
   OCCT sources are copied **unmodified** (LGPL rule).
2. For each toolkit, copy exactly its per-package `FILES.cmake` lists
   plus inline include files (`.lxx`/`.pxx`/`.gxx`) by glob, `GTests`
   excluded — the same assembly the existing 35 toolkits used.
3. Add the toolkit's **transitive EXTERNLIB closure** from OCCT's own
   `adm/cmake/<toolkit>/EXTERNLIB.cmake` — never hand-pick files. Any
   closure member not already staged (e.g. TKXmlL / TKStdL for the
   XML branch) is staged by the same rule and recorded in the
   manifest.
4. Run the include scan used for the FreeCAD extension (every staged
   `.cxx`'s includes must resolve inside the tree) and restore any
   pruned-spot headers it flags, exactly as was done for
   TKXCAF's XCAFPrs and TKService's WNT files.
5. Regenerate the Xcode project with cascade-port's `gen_project.py`
   (byte-deterministic generator) and update `MANIFEST.md` counts.
6. Host-proof before device: compile the expanded set on Linux
   (one static archive per toolkit, `g++ -std=gnu++17`, no cmake —
   the method the original subset was proven with), link the façade,
   and run the façade test driver.

## What was prepared at integration, and what was not

- Prepared: this plan, the per-command coverage table
  (`COMMAND-COVERAGE.md`) that names exactly which commands flip from
  `toolkit-missing` to `facade-ready` when each toolkit lands, and the
  NOT_IMPLEMENTED contract (E5002 / CC-SYS-000) every missing-toolkit
  command must honour in the meantime.
- NOT done here: the staging itself. It edits the cascade-port tree
  (a different project with its own verified manifest and a
  byte-deterministic generated Xcode project), and doing it as a
  side-effect of this integration — without re-running its host
  compile proof and manifest update — would break that project's
  "every staged file verified" invariant. It is a discrete,
  evidence-based next step for the main agent to schedule against
  cascade-port, following steps 1–6 above. Estimated scope from the
  FreeCAD extension's precedent: TKDEOBJ/TKDEVRML/TKDEPLY are small
  (tens of files each class); the TKXml branch is the larger one.
- Until then: **7 commands answer NOT_IMPLEMENTED. Nothing fakes a
  result.**
