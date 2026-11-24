# Cascade Console — Viewer

The shared 3D viewer for the macOS and iPad apps. Metal (`MTKView`),
direct lighting only — **no ray tracing, ever** (standing rule). The
viewer never touches OCCT: the core tessellates BRep shapes with
`BRepMesh` and hands over plain triangle buffers in the format below.

Both apps use these sources **verbatim**. Platform differences are
confined to `Swift/CascadeMetalView.swift` (gestures + SwiftUI hosting).

## Files

| File | Role |
|---|---|
| `Swift/MeshBuffer.swift` | CCM1 mesh-buffer format: types + parser (validates magic, counts, index range, unit normals) |
| `Swift/ViewerBridge.swift` | **The protocol** — commands, display props, delegate (normative, below) |
| `Swift/Camera.swift` | Orbit camera: presets, fit, pan/zoom maths, perspective + orthographic matrices |
| `Swift/SceneStore.swift` | Scene state, mesh cache, bounds, explode, CPU ray picking + measure |
| `Swift/Renderer.swift` | `CascadeRenderer`: Metal pipelines, GPU buffer cache, draw, screenshot-to-PNG; implements `ViewerBridge` + `MTKViewDelegate` |
| `Swift/CascadeMetalView.swift` | `MTKView` subclass: mouse / touch / Pencil input, `CascadeViewerRepresentable` for SwiftUI |
| `Swift/ViewCommands.swift` | Parser for every `view …` console command → `ViewerCommand` |
| `Shaders/Shaders.metal` | Mesh (direct-lit), line, and background-gradient shaders |
| `Verification/verify_tessellation.py` | Host proof of the data contract against live OCCT (see Results) |
| `Verification/sample_mesh.ccm` | The verified sample buffer the script wrote |

## ViewerBridge protocol (what Agents 3 and 4 conform to)

Create **one** `CascadeRenderer`, pass it to `CascadeMetalView(renderer:)`
(or embed `CascadeViewerRepresentable(renderer:)` in SwiftUI), and set
`renderer.delegate`. All interaction goes through the protocol:

**App → Viewer**

- `loadMesh(_ object: MeshObject, props: ObjectDisplayProps)` — geometry
  arrives pre-tessellated. Re-loading with an unchanged
  `(id, geometryVersion)` is a no-op for geometry (props still update).
- `updateObjectProps(id:props:)` — colour / opacity / visibility /
  per-object edge overlay. Never re-tessellates, never re-uploads.
- `removeObject(id:)` / `clearScene()`
- `apply(_ command: ViewerCommand)` — every view command (below).
  Apps normally obtain these from `ViewCommandParser.parse(line)`.
- `pick(at:viewSize:)` — view points, **origin top-left, y down**, on
  both platforms (the macOS view flips AppKit's bottom-left coordinates
  internally, once). Returns object id, world point, and the OCCT
  source-face index (via face groups) when known.
- Read-only state for a `view status` report: `objectIDs`, `props(id:)`,
  `displayMode`, `projectionMode`, `explodeFactor`, `sectionPlane`.

**Viewer → App** (`ViewerBridgeDelegate`, main queue by convention —
the renderer calls it from UI/draw paths only):
`viewerDidChangeCamera`, `didPick`, `measureDistanceChanged` (model
units, `nil` until two points are picked), `didWriteScreenshotTo`,
`didFailWith` (plain-language message; show it verbatim).

**Threading:** all bridge calls on the main queue. The core may build
`MeshObject`s on its own queue but must hand them over on main.

## Mesh buffer format (CCM1)

Little-endian throughout. Header: magic `CCM1`, `UInt32` version = 1,
`UInt32` objectCount, `UInt32` reserved. Per object: name (length-prefixed
UTF-8, = scene id), `UInt64 geometryVersion`, face groups
(`sourceFaceIndex, vertexStart, vertexCount, indexStart, indexCount` —
one per BRep face, enabling per-face selection), then interleaved
vertices `x y z nx ny nz` (Float32, **stride 24 bytes**, identical in the
file and the Metal vertex buffer), `UInt32` triangle indices (CCW,
outward), bbox (6×Float32), centre (3×Float32).

**Coordinate contract:** OCCT model space as-is — right-handed, **Z-up**,
model units (mm by convention). No axis conversion anywhere; the camera
is built in Z-up space, so `view top` really is looking down −Z.
Vertices are **not welded across faces** (sharp CAD edges, correct
per-face normals). Normals are the true surface normals — surface `D1`
at each node's UV parameters, flipped for REVERSED faces — computed on
the core side; triangulations delivered to the viewer must carry rigid
locations only (identity/rotation+translation), so normals stay valid.
Winding is flipped for REVERSED faces so front faces are outward.

## View commands (console surface)

All parsed by `ViewCommands.swift`; also directly constructible.

| Command | Effect |
|---|---|
| `view fit` | frame all visible objects |
| `view top\|bottom\|front\|back\|left\|right\|iso` | standard camera presets |
| `view shaded` / `view solid` | direct-lit shading |
| `view wireframe` | triangle wireframe |
| `view edges` | shaded + edge overlay (unique edges, derived once per geometry version) |
| `view xray` | all objects at 25% opacity, depth-write off |
| `view transparent` | per-object opacity honoured, drawn back-to-front |
| `view section off` | disable clipping |
| `view section x\|y\|z <distance>` | clip everything beyond the plane (e.g. `view section z 5` keeps z ≤ 5) |
| `view section <nx> <ny> <nz> <constant>` | arbitrary plane: `dot(p,n)+c > 0` is clipped |
| `view explode <0…2>` | parts translate away from scene centre along their centre line (0 = assembled) |
| `view screenshot [path] [w h]` | offscreen render to PNG (default Pictures folder, 1600×1200) |
| `view measure on\|off\|clear` | on: next two picks set the measure points; distance reported via delegate + drawn as a line |
| `view grid on\|off`, `view axes on\|off` | grid on the z=0 plane (auto step: power of ten from scene size); X red / Y green / Z blue axes |
| `view background <topRRGGBB> <bottomRRGGBB>` | gradient background |
| `view projection ortho\|perspective` | projection toggle (fit/zoom keep both parameterisations in sync) |
| `view hide <id>` / `view show <id>` | per-object visibility |
| `view opacity <id> <0…1>` | per-object opacity |
| `view color <id> <RRGGBB>` | per-object colour |
| `view reset` | default camera + fit |

Section clipping is a fragment discard — an open cut, **not** a capped
solid. Explode is a per-object translation only (no per-face-group
explode in this version). Transparency sorting is per-object by centre
distance, not per-triangle.

**Controls:** orbit = left-drag / one-finger drag (Pencil = finger);
pan = right-drag or Cmd-drag / two-finger drag; zoom = scroll wheel,
trackpad magnify / pinch; pick = click / tap (a press moving < 3 pt).

## Performance rules

1. **Tessellation quality is a core-side setting**, deflection-based.
   Profiles (verified below): `coarse` deflection 0.5 / angular 0.5,
   `standard` 0.1 / 0.3 (default), `fine` 0.02 / 0.1, plus `custom`
   (user values from Settings). Quality changes re-tessellate on the
   core and arrive as a bumped `geometryVersion`.
2. **Mesh caching by `(objectID, geometryVersion)`** in both
   `SceneStore` (CPU) and the renderer (GPU buffers + lazily built edge
   buffers). Same key ⇒ no upload, no rebuild.
3. **Camera moves never touch geometry.** A frame rewrites only a
   176-byte uniform block per object; grid/axes rebuild only when scene
   bounds change; edge buffers build once per geometry version.
4. Picking/measure run on the CPU copies — no GPU readback, ever.
5. Transparent objects are the only sorted pass, and only per-object.

## Verification (host-side, run in this sandbox)

`Verification/verify_tessellation.py` (venv `~/workspace/stl2step-venv`,
OCP/OCCT) builds a real solid — 30×20×12 box with a radius-6 cylinder
cut through it (`BRepAlgoAPI_Cut`) — tessellates it at the three
profiles, writes the standard profile as CCM1, and re-reads it with the
same layout the Swift parser uses. Results, 2026-11-23:

- OCCT truth: volume **5842.832 mm³**, surface area **2626.195 mm²**,
  bbox (0,0,0)–(30,20,12), 7 faces.
- coarse: 130 vertices / 120 triangles · standard: **194 vertices /
  184 triangles / 7 face groups** · fine: 530 vertices / 520 triangles.
- CCM1 round-trip: counts, face groups, and bbox match OCCT exactly;
  max |normal|−1 error **2.94×10⁻⁸**; summed mesh triangle area
  2626.616 mm² vs OCCT 2626.195 mm² (**0.016%** error); file 7,086 bytes.
- Verdict printed by the script: `CONTRACT VERIFIED`.

**Swift execution gate (v0.2.3):** the Python contract above proves
the file format, but until v0.2.3 no gate ever ran the Swift side —
and the shipped app broke there twice. The `mc-backend-matrix` CI
job now generates a view-data fixture from the real engine
(`Core/native/tests/dump_view_fixture.cpp`, mc backend) and runs
`Verification/swift-harness/main.swift`, compiled with the
production `MeshBuffer.swift` / `EngineMeshAdapter.swift` sources:
it asserts the adapter + loader round-trip (counts, bbox, face
groups, signed volume) and re-reads the parsed `[MeshVertex]`
buffer with the renderer's vertex-descriptor layout values
(`MeshVertex.bufferStride` / `bufferNormalOffset`), asserting every
vertex survives. Note the format subtlety that caused the v0.2.2
fan: the CCM1 file packs each vertex in 24 bytes, but a
`MeshVertex` in memory has stride 32 (two 16-byte-stride
`SIMD3<Float>` members, normal at offset 16). The file stride and
the buffer stride are different constants on purpose now.

## Integration checklist for the two apps

- Add all `Swift/*.swift` + `Shaders/Shaders.metal` to **both** app
  targets (or one shared framework target — the renderer falls back to
  its own bundle for the Metal library).
- The view must be created with `renderer.metalDevice`; pixel formats
  are set in `CascadeMetalView.commonInit` (bgra8Unorm / depth32Float).
- Forward console lines beginning with `view` to
  `ViewCommandParser.parse`; on `.failure(let message)` print the
  message and apply nothing.
- Honest status: this scaffold is **not compiled** — no Metal/Swift
  toolchain exists in the Linux sandbox. It was written to standard
  Swift/Metal APIs and reviewed line by line (including two fixes found
  in review: triangle fill mode is encoder state, not pipeline state;
  the background pass needs a depth-compare-`.always` state because it
  renders exactly at the far plane). First Xcode build on the Mac is
  the compile verdict; gesture sign conventions (macOS `deltaY`) are
  the one behaviour to confirm on device.
