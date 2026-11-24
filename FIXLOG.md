# FIXLOG — BUILD agent pass, 2026-11-23

Work done in `buildwork/` (a copy of the integrated `repo/`). Nothing
was pushed anywhere. Every change below was made only in this copy;
the main agent syncs it back into `repo/` before dispatching CI.

## 1. NEW: iPad Xcode project — `Apps/iPad/CascadeConsole.xcodeproj/`

- `project.pbxproj` hand-authored (standard structure, objectVersion
  56, deterministic IDs). One app target `CascadeConsole`:
  bundle id `com.user.cascadeconsole`, iPad only
  (`TARGETED_DEVICE_FAMILY = 2`), `IPHONEOS_DEPLOYMENT_TARGET = 17.0`.
  Rationale for 17.0: the sources use `ContentUnavailableView` and
  the iOS 17 `onChange` forms; Liquid Glass is only reached behind
  `#available(iOS 26.0, *)`; the viewer guards platform code with
  `#if os(...)`. Header comment in the pbxproj records this and the
  OCCT TODO.
- `xcshareddata/xcschemes/CascadeConsole.xcscheme` added (shared
  scheme, XML-validated) so CI's `-scheme CascadeConsole` resolves.
- Sources phase (25 files, all verified to exist on disk):
  `Apps/iPad/Sources/**` (13) + `Shared/Console/CommandHistory.swift`,
  `Shared/Engine/EngineProtocol.swift`, `Shared/Models/SharedModels.swift`,
  `Shared/Settings/SettingsKeys.swift`, the 7 viewer Swift files and
  `Shared/Viewer/Shaders/Shaders.metal`.
- Resources phase (5 files): `Shared/Resources/catalog.json`,
  `Resources/welcome.cascade`, `Resources/sample-project.cascade`,
  and both OCCT licence texts from `Licenses/` (QA gate: licences
  bundled and openable in-app).
- Info.plist is generated (`GENERATE_INFOPLIST_FILE`) with file
  sharing + open-documents-in-place enabled (the in-app Documents
  browser is the supported sideload path).
- OCCT / cascade-port linking is a documented TODO in the pbxproj
  header: no Layer-2 library exists yet, so the target builds against
  the Shared Swift `StubEngine` (answers E5002 NOT_IMPLEMENTED for
  modelling commands) — the honest current state.
- Structural verification (no Xcode in this sandbox): all 90 object
  IDs referenced are defined; brace/paren balance exact; every
  fileRef resolves to a real file on disk through its group chain.

## 2. Mac SwiftPM package — `Apps/Mac/Package.swift`

- Verified: target `CascadeConsoleMac`, path `CascadeConsoleMac/`,
  all 12 Swift files exist and are picked up automatically.
- Rewrote the header to resolve the Shared/ dependency EXPLICITLY:
  the Mac target deliberately does NOT depend on `../../Shared`
  today, because its per-app types are internally consistent and
  adding Shared now would duplicate `SceneObjectItem`,
  `Color(hexString:)`, and the StubEngine/SettingsKeys/CommandResult
  surfaces in one module. The adaptation TODO (INTEGRATION-NOTES (f))
  is named as the step that changes this. The iPad target is ahead:
  it already compiles Shared (see §3).

## 3. Swift audit fixes (line-by-line read of all 40 Swift files + Metal)

Balance: every file's braces/parens/brackets balanced before and
after. Duplicate-definition scan run per target set (see below).

### F1 — Mac `AppState.swift`: dangling type `ViewerBridge` (COMPILE ERROR)
`let viewer: ViewerBridge` + default `PlaceholderViewerBridge()` —
but the Mac target defines no type named `ViewerBridge` (the
integration removed the Mac protocol of that name; the Shared
protocol has a different surface and `PlaceholderViewerBridge`
conforms to neither). This could never have compiled. Fixed: the
property and initializer now use the concrete
`PlaceholderViewerBridge`, matching the iPad pattern, with a comment
pointing at the resolution-(e) repoint TODO.

### F2 — iPad target: duplicate type definitions vs Shared (COMPILE ERRORS)
Including Shared/ in the iPad target (required by §1) collided with
the iPad scaffold's superseded per-app files. Resolved by ADAPTING
the iPad app to the Shared canonical types and DELETING the three
superseded files from this copy:
- DELETED `Sources/Models/CommandModels.swift` (duplicated Shared
  `CommandResult`, `SceneObjectItem`, `CascadeFileKind`; its
  `LogEntry` is Shared `ConsoleLogEntry`).
- DELETED `Sources/Services/EngineBridge.swift` (duplicated Shared
  `StubEngine`; its `CascadeEngineFacing` protocol is superseded by
  Shared `CascadeEngine`).
- DELETED `Sources/Services/SettingsStore.swift` (duplicated Shared
  `SettingsKeys`, `LengthUnit`, `TessellationQuality`,
  `AppearanceChoice`).
Adaptations that followed:
- `Sources/Models/AppState.swift`: log is `[ConsoleLogEntry]`,
  `appendLog(ConsoleLogEntry.Kind, …)`, engine typed `CascadeEngine`;
  `apply(_:)` now iterates `CommandResult.producedNames` — Shared's
  result carries session names only, and in the Layer-2 design the
  session name IS the shape handle, so `shapeID == name` (commented).
- `Sources/Views/ConsoleView.swift`: `LogEntry` → `ConsoleLogEntry`;
  the colour switch gained the `.result` and `.warning` cases the
  Shared `Kind` adds (the switch would otherwise be non-exhaustive).
- `Sources/Views/SettingsView.swift` + `Sources/CascadeConsoleApp.swift`:
  stale comments updated to the Shared types/keys.
- `Sources/Viewer/ViewportPlaceholderView.swift`: user-visible text
  named the removed `CascadeViewerBridging` protocol; now names the
  real Shared `ViewerBridge`.

### F3 — Shared `SettingsKeys`: missing key the iPad views use
iPad Console/Settings views read `SettingsKeys.consoleFontSizeStep`,
which the Shared key enum did not carry (only the deleted per-app
file had it, under the abandoned `settings.*` scheme). Added
`consoleFontSizeStep = "cc.consoleFontSizeStep"` (Int, -1...1) to
`Shared/Settings/SettingsKeys.swift`, keeping the relative-step
semantics under the canonical `cc.*` scheme.

### F4 — `Apps/iPad/README.md` brought back in sync
Folder layout, engine/settings connection points and the "create the
project in Xcode by hand" instructions updated to the real project
and the Shared-canonical structure (§1–§3).

### Audit results with NO change needed
- Mac target set: zero duplicate type definitions.
- iPad+Shared set after F2: the only repeated definition name is
  `CascadeViewerRepresentable`, defined twice inside ONE file
  (`CascadeMetalView.swift`) in mutually exclusive `#if os(macOS)` /
  `#else` branches — not a collision. `CascadeRenderer` has two
  legal extensions (one per file). `Color(hexString:)` exists once
  per target set.
- Viewer notes (risks, not fixed — out of this pass's scope):
  `Renderer.swift` holds its pipelines in implicitly-unwrapped
  optionals and `CascadeMetalView`'s convenience init `fatalError`s
  when no Metal device exists; `ViewCommands.swift` force-unwraps
  `StandardView(rawValue:)` on a value already constrained by its
  own case list (safe, but a force unwrap). All three are listed in
  the risk ranking returned to the main agent.

## 4. CI workflows (`.github/workflows/`)

- `build-ipa.yml`: header updated (project + shared scheme now
  exist); added a pre-flight step (`test -f` on pbxproj/scheme/
  catalog + `xcodebuild -list`) and a post-build bundle gate
  (`catalog.json`, `default.metallib`, `OCCT-LGPL-2.1.txt` must be
  inside the built .app — proving resources shipped, per QA §5's
  binary-gate rule). Paths/scheme/product name match §1 exactly.
  No error masking anywhere.
- `build-mac.yml`: header updated to the Package.swift resolution;
  added `test -x` on the built binary. Paths match §2.
- `host-tests.yml`: unchanged (already correct).
- All workflows: `macos-26` standard free runners (host-tests:
  `ubuntu-latest`). No paid/larger runner labels anywhere. YAML
  parse-verified.

## 5. Host verifications re-run in THIS copy

- Core Python tests: **47/47 OK** (`unittest discover`, OCCT 7.8
  bindings from the existing venv).
- Viewer tessellation verification: **CONTRACT VERIFIED** — CCM1
  round-trip OK, mesh area 2626.616 mm² vs OCCT 2626.195 mm²
  (0.016% error), max normal error 2.94e-08; regenerated
  `sample_mesh.ccm` is byte-identical to the repo copy.

## Not done / cannot be done in this sandbox
- No Swift toolchain exists here: nothing above is compiler-verified.
  The first CI runs are the first real compiles (risks ranked in the
  report to the main agent).
- No workflow was dispatched; no push was made.

## CI fix loop — coordinator, 2026-11-23

### F5 — iPad project missing SDKROOT (IPA runs 45241769566 / 45241814167, exit 70)
xcodebuild failed before compiling: "Unable to find a destination
matching { generic:1, platform:iOS }" and the only available
destinations listed were macOS ("My Mac" / "Any Mac"). Root cause:
the hand-authored pbxproj never set `SDKROOT`, so Xcode treated the
target as a macOS app despite IPHONEOS_DEPLOYMENT_TARGET and
TARGETED_DEVICE_FAMILY=2. Every working iOS project in this workspace
(HiddenBlocks, cascade-port) sets `SDKROOT = iphoneos` in the target
configurations. Fix: added `SDKROOT = iphoneos;` to both target
build configurations (Debug + Release). Xcode on the runner is
26.6 (iphoneos26.5 SDK) — no Xcode-selection change was needed.

### F6 — duplicate source filename ViewerBridge.swift (IPA run 45244550232)
F5 worked (iOS destination resolved, build started) and Xcode then
failed with: error: Filename "ViewerBridge.swift" used twice:
'Apps/iPad/Sources/Viewer/ViewerBridge.swift' and
'Shared/Viewer/Swift/ViewerBridge.swift' (in target 'CascadeConsole').
Xcode requires unique source basenames per target. The iPad file
contains only `PlaceholderViewerBridge` (its header already says the
Shared file is the normative bridge), so the honest fix is a rename,
not an exclusion: Apps/iPad/Sources/Viewer/ViewerBridge.swift ->
PlaceholderViewerBridge.swift, with the pbxproj fileRef/buildFile
entries (IDs FEED642D…, 64FF6FD3…) and Apps/iPad/README.md updated.
The Shared ViewerBridge.swift is untouched.

### F6 — duplicate source filename ViewerBridge.swift (IPA run 45244550232)
F5 worked (iOS destination resolved, build started) and Xcode then
failed with: error: Filename "ViewerBridge.swift" used twice:
'Apps/iPad/Sources/Viewer/ViewerBridge.swift' and
'Shared/Viewer/Swift/ViewerBridge.swift' (in target 'CascadeConsole').
Xcode requires unique source basenames per target. The iPad file
contains only `PlaceholderViewerBridge` (its header already says the
Shared file is the normative bridge), so the honest fix is a rename,
not an exclusion: Apps/iPad/Sources/Viewer/ViewerBridge.swift ->
PlaceholderViewerBridge.swift, with the pbxproj fileRef/buildFile
entries (IDs FEED642D…, 64FF6FD3…) and Apps/iPad/README.md updated.
The Shared ViewerBridge.swift is untouched.

### F7 — Shared viewer Swift compile errors (IPA run 45244853609, 39 errors in 2 files)
Real compilation started after F6. Three root causes:
1. ViewCommands.swift (33 errors): the parser declared
   `Result<ViewerCommand, String>` — String does not conform to
   `Error`, so the Result type itself was invalid and every
   `.success(.fit)` / `.displayMode(...)` etc. lost its contextual
   type ("cannot infer contextual base"). Fix: new
   `ViewCommandParseError: Error` struct carrying `message`; the
   parser returns Result<ViewerCommand, ViewCommandParseError> and
   all 15 failure sites wrap their message. No in-repo callers used
   the String form (checked), and the console-facing message text
   is unchanged.
2. Renderer.swift (4 errors): it assigned `store.entries[id]?.props…`
   but SceneStore.entries is `private(set)`. Fix: SceneStore gained
   `setProps(id:props:)` and `mutateProps(id:_:)`; the Renderer now
   calls those for updateObjectProps and the setObjectVisible /
   setObjectOpacity / setObjectColor commands. Reads of entries
   (props query, draw loop) are unchanged.
3. Renderer.swift (2 errors): `makeBuffer(bytes: vData)` was handed a
   `Data`; the API takes UnsafeRawPointer. Fix: buffers are created
   directly inside each array's withUnsafeBytes from its raw base
   address and byte count.

### RESULT — all three workflows GREEN, 2026-11-23 (commit 4eeb1fd4)
After F7: Host tests run 45245238484 SUCCESS, Build Mac run
45245238556 SUCCESS, Build iPad IPA run 45245238379 SUCCESS (all
steps incl. the bundle-resource gate). IPA artifact verified from
the downloaded artifact itself: bundle id com.user.cascadeconsole,
version 1.0 (1), arm64 Mach-O executable, catalog.json (86,796 B),
default.metallib (87,596 B), OCCT-LGPL-2.1.txt and
OCCT-LGPL-EXCEPTION.txt, welcome.cascade and sample-project.cascade
all inside CascadeConsole.app. Mac artifact verified: arm64 Mach-O
CascadeConsoleMac binary (676 KB) in the unsigned zip. Honest
scope note (unchanged): a green IPA run means the app compiles and
packages against the Swift StubEngine — the native OCCT Layer-2
library does not exist yet, so modelling commands answer
NOT_IMPLEMENTED on device until it is linked.

---

# v0.2 — CI coordinator pass, 2026-11-23

## Integration of enginework/ into repo/
- `Core/native/` ← engine's NativeEngine tree (interpreter, 3 backends,
  mc_additions, tests, build_host.sh, module map). Build artifacts
  (`Core/native/build/`) excluded.
- `Shared/Engine/NativeEngine.swift` + iPad pbxproj entries (engine's
  repo-copy changes), Mac Package.swift plan comment, new workflow
  `.github/workflows/build-native-engine.yml` (cascade-ios fetch now
  PINNED to 061875afb5384227db5f39cba81266cf889257a4).
- Engine report preserved verbatim at `docs/ENGINE-REPORT.md`.
- Host tests RE-RUN from the repo copy on this machine (not just
  trusted): mock 84 pass / 0 fail / 2 skip; real OCCT 8.0.1
  (conda-forge) 90 pass / 0 fail / 0 skip; ccgeom_mc.cpp compiles
  against the real cascade-port facade header. Matches REPORT.md §3.

## mc_additions caveat — CORRECTED during integration
The delivered paste block in `Core/native/src/mc_additions.cpp`
assumed the facade handle's `_impl` is a raw `TopoDS_Shape*` and an
error helper named `setError()`. The REAL facade (cascade-ios
061875af…) wraps a private `ShapeImpl { TopoDS_Shape shape; ... }`
behind `shapeOf()`/`wrap()`, and its error helper is
`fail(err, code, msg)`. Pasting the block verbatim would not have
compiled (and a forced variant would have crashed at runtime).
`Core/native/ci/patch_cascade_port.py` therefore injects corrected
implementations (via shapeOf/wrap/fail, StlAPI_Writer include,
TKDESTL is in the staged tree) into the ephemeral CI checkout of
cascade-ios only; cascade-ios upstream and all OCCT sources are
unmodified. The delivered mc_additions files stay in Core/native/src
as the design record, with this caveat.

## Viewer feed (v0.2 gate: the viewer must be FED)
- `Shared/Engine/EngineProtocol.swift`: new `EngineViewObject` +
  `EngineViewDataProviding` protocol. NativeEngine conforms (its
  viewData now returns EngineViewObject); StubEngine deliberately
  does not — no core, nothing rendered, honestly.
- `Shared/Viewer/Swift/EngineMeshAdapter.swift` (new, in the iPad
  target): EngineViewObject -> CCM1 bytes -> MeshBufferLoader ->
  MeshObject. cc_view_data carries positions only, so the adapter
  derives flat normals, unwelds per triangle corner, and emits one
  face group per object — the honest consequence of the Layer-2 API;
  smooth normals via mc_tessellate are a later upgrade. Going through
  real CCM1 bytes means the shipped app exercises the exact contract
  verify_tessellation.py proves (re-run here: CONTRACT VERIFIED,
  mesh area error 0.016%).
- iPad AppState: viewer type is now the real `CascadeRenderer`
  (optional only for no-Metal devices); picks arrive via
  ViewerBridgeDelegate; after every successful command
  `refreshScene()` re-syncs the object list from the session and
  loads tessellation into the renderer via ViewerBridge.loadMesh;
  `view` commands also fit. Visibility/remove/clear go through
  ViewerBridge commands with shape names as IDs.
- ContentView now hosts the new `ViewportView` (CascadeViewer-
  Representable + Fit/display-mode chips). ViewportPlaceholderView
  and PlaceholderViewerBridge are DELETED (pbxproj entries removed /
  renamed in place). App entry uses EngineFactory.makeEngine() and
  CascadeRenderer(). App version bumped to 0.2 (build 2).
- Mac: NOT wired in this pass — its AppState still uses its own
  per-app engine/viewer types; the remaining step is the Shared
  adaptation pass (INTEGRATION-NOTES (f)) described in
  Apps/Mac/Package.swift. Mac v0.2 artifact remains the stub build.

## Native link in CI (build-ipa.yml rewritten)
Fetch cascade-ios @ 061875af…, patch its facade in-checkout, build
CascadeKit via its gen_project.py, compile cc_interpreter.cpp +
ccgeom_mc.cpp to libCascadeConsoleEngine.a for arm64/iOS, generate
the CCascadeConsole module map, build the app with
CASCADE_NATIVE_ENGINE + SWIFT_INCLUDE_PATHS + OTHER_LDFLAGS, then
GATE on the shipped executable: nm must show _cc_execute,
_cc_session_create, _mc_clone_shape; bundle must contain
catalog.json, default.metallib and BOTH OCCT licence texts.

## CI results
<!-- filled in by the coordinator as runs complete -->

## Simulation integrated (v0.2, per docs/SIM-INTEGRATION.md)
- simwork module copied into Core/native (ccsim.h/ccsim_backend.h,
  ccsim.cpp, ccsim_commands.cpp, ccsim_backend_mc.cpp,
  ccsim_backend_mock.cpp, tests/test_sim.cpp + probe_cylinder.cpp,
  build_sim.sh adapted to the repo layout). INTEGRATION.md preserved
  at docs/SIM-INTEGRATION.md.
- The OCCT sim backend was MERGED into ccgeom_occt.cpp as instructed
  (same TU as CCGeomShape, sharing ccgeom_last_error()); its
  standalone setErr shim was removed (it collided with the TU's own
  setErr — caught by the host build, fixed before any CI run).
- Interpreter registration exactly per INTEGRATION.md: ccsim::State
  member on CCSession, SimHost adapter (object/num with CCError <->
  ccsim::Error translation), one `sim` dispatch branch, sim help
  lines; `sim` is NOT in mutatingCommands and sim state is NOT
  snapshotted.
- Host proof FROM THE REPO COPY: sim suite 35/35 on mock AND real
  OCCT 8.0.1; engine suite unchanged (90 OCCT before label tests);
  plus an end-to-end smoke through cc_execute (box -> sim material
  steel -> fix @face 0 -> load @face 5 -> sim run solves the 640-
  element cantilever; sim modal -> E5002). The Layer-2 CI library
  and the ubuntu CI job now build/run the sim sources too.
- The two optional facade additions (mc_point_face_distance,
  mc_face_point_normal) were NOT added — the module ships without
  them, with its documented mc-backend limitations (pressure on
  non-planar faces fails loudly on device until they land).

## Face-number labels (v0.2)
- NUMBERING TRUTH: @face indices are the 0-based census indices
  (facade section 8 census; sim INTEGRATION.md). Labels therefore
  show 0..5 on a box — six labels, one per face, numbered as the
  commands accept. (A "1..6" labelling would have made @face 1 fix
  the face labelled 2 — rejected on the critical requirement.)
- The view-data path did NOT carry face attribution: ccgeom_
  tessellate appends triangles face by face in census order but
  exported no ranges. Added ccgeom_face_ranges (all 3 backends:
  OCCT re-walks the same TopExp map; mc converts the facade mesh's
  faceTriStart/Count, which the facade header guarantees are in
  census order; mock slices its documented box placeholder) ->
  CCViewData.faceRanges -> EngineViewObject.faceRanges -> CCM1 face
  groups with sourceFaceIndex = the census index. No renderer-side
  guessing anywhere in the chain.
- Host proof (tests/test_engine.cpp, OCCT backend): box ranges are
  census-ordered, partition the index buffer exactly, every range's
  centroid is a true box face centre (label anchors); demo part:
  label count == cc_object_stats face count. Engine suite is now
  100 pass / 0 fail on OCCT 8.0.1 (90 before), 90 on mock.
- Rendering: `view labels faces on|off` (ViewCommands grammar,
  default OFF) -> ViewerCommand.setFaceLabelsEnabled ->
  CascadeRenderer.faceLabelsEnabled (also a ViewerBridge property
  for a future UI switch). Chips are CATextLayers repositioned every
  frame with the renderer's own view-projection: black 14 pt
  semibold text on a white chip (high contrast), anchored at the
  face centroid lifted along its normal, hidden when the face
  points away (dot(normal, viewDir) <= 0.15) or behind the camera.
- HONEST LIMITS: label overlay is iOS-only in this pass (macOS sets
  the flag but draws no chips; the Mac app does not use this
  renderer yet). AppState now routes parser-accepted `view …`
  commands to the renderer; the engine's `view <path.json>` form
  still falls through to the engine. An object literally named like
  a viewer head word (e.g. "top") cannot be targeted by the
  engine's bare `view <name>` form — parser heads win; documented
  ambiguity, same as most CAD consoles.
- CI fix: build_host.sh lost its exec bit in the API push (mode
  100644) and the Native-engine ubuntu job failed with exit 126
  (Permission denied) on the v0.2 push. Workflows now invoke the
  scripts via `bash`, and pushes record mode 100755 for .sh files.
- CI fix 2 (Native-engine ubuntu job, run 45253976985): distro OCCT
  on the runner uses the renamed toolkits (TKDESTEP/TKDESTL) in the
  multiarch dir /usr/lib/x86_64-linux-gnu; build_host.sh's rename
  detection only looked in $OCCT_PREFIX/lib, so the link failed with
  "cannot find -lTKSTEP / -lTKSTL". Detection in build_host.sh and
  build_sim.sh now also searches the chosen prefix's multiarch dir.
  Scoping matters: an unscoped first version found the host's system
  OCCT 7.x TKSTEP while linking against conda 8.0.1 and mixed the
  two (link conflict, abort) — caught and fixed locally before the
  push; detection is now prefix-scoped only. Local suites re-green
  after the fix: engine 90 mock / 100 OCCT, sim 35/35 both.
- CI fix 3 (Native-engine ubuntu job, run 45257130018): engine tests
  themselves now pass in CI (90 mock / 100 OCCT — fix 2 worked), but
  build_host.sh's trailing mc-adapter compile check hardcoded
  $HOME/workspace/cascade-port, which does not exist on a runner.
  The check is now conditional on a cascade-port checkout being
  present (CC_PORT_DIR), skipping loudly otherwise; on CI the macOS
  job performs it against the pinned cascade-ios fetch.
- build-ipa.yml: COMPILER_INDEX_STORE_ENABLE=NO on the CascadeKit
  build (indexing 5,234 OCCT files in CI is pure overhead).
- CI fix 4 (IPA CascadeKit step): the xcodebuild build of the
  generated 5,234-file CascadeKit project never completed (>75 min
  in-step across three runs, incl. with the index store disabled).
  The step now compiles the identical source set directly with
  parallel clang (xargs -P ncpu), using the exact settings
  gen_project.py encodes (defines OCC_CONVERT_SIGNALS / No_Exception
  / OCCT_NO_PLUGINS / NDEBUG, all OCCT header dirs, gnu++17, -O1),
  archived into the same libCascadeKit.a, and the result is cached
  (actions/cache keyed by the pinned cascade-ios SHA + patch hash)
  so later runs skip it. OCCT sources remain unmodified.
- CI fix 5 (Native-engine ubuntu job, run 45264281060): engine tests
  passed in CI (90 mock / 100 OCCT), then test_sim.cpp failed to
  compile on the runner's g++: uint32_t used without <cstdint>
  (transitively included by this host's headers, not the runner's).
  Added the include.
- The push-triggered Build Mac runs keep ending "cancelled" with no
  log (45264281197, 45273079290) while a workflow_dispatch run of the
  same commit succeeds (45268038128); treated as a runner-side
  cancellation, Mac is re-dispatched rather than code-changed.
- CI fix 6 (Native-engine ubuntu job, run 45275978464): build_sim.sh's
  mc-adapter compile check had the same unconditional
  $HOME/workspace/cascade-port assumption as fix 3. Same conditional
  treatment. (The sim tests themselves had already passed locally and
  in the macOS job; the failing step was only this trailing check.)
- CI fix 5b (IPA CascadeKit step): per-file compilation — xcodebuild
  AND direct per-file clang — never finished in CI (>75 and >95 min
  in-step): each of the 5,234 translation units re-parses the same
  multi-megabyte OCCT header graph. Core/native/ci/build_cascadekit.sh
  now compiles the identical sources as ~130 chunked-unity TUs
  (40 files per TU, grouped by toolkit) with the exact defines and
  language standard gen_project.py encodes; unity files only
  #include the OCCT sources (unmodified, LGPL). The previous per-file
  run was left racing; whichever finishes first populates the cache.
- CI fix 5b REVERTED: chunked-unity compilation of OCCT fails —
  file-scope static helpers collide across files within a toolkit
  (redefinition of cherche_edge1 / IsLineOrCircle / Contains,
  ambiguous t3dto2d, ...). OCCT is not unity-safe and its sources
  must stay unmodified, so the workflow is back to the per-file
  direct-clang build (fix 4); build_cascadekit.sh removed.
- CI fix 7 (IPA app build, run 45273079709 — CascadeKit and the
  engine library themselves built GREEN): two Swift type errors.
  (a) NativeEngine.viewData had an extra defaulted parameter, which
  does not satisfy the EngineViewDataProviding witness; signature
  restored to the protocol's, deflection fixed at 0.5 mm inside.
  (b) Renderer.updateFaceLabels used `let host = view.layer` in a
  guard; MTKView.layer is non-optional on iOS — split the binding.
- CI fix 8 (IPA app link, run 45282966795): Swift compiled fully;
  the link failed on one undefined symbol, ccsim::execute — the
  engine-library step compiled all five objects but its `ar` line
  still archived only cc_interpreter.o + ccgeom_mc.o (the line
  predated the sim integration). All five objects are now archived.

## v0.2 CI results (final, commit 54bea331)
- Host tests: SUCCESS (run 45287892575).
- Build Mac app: SUCCESS (run 45287892732) — stub engine, see README.
- Native engine: SUCCESS on 1d11645f (run 45276454683; engine 90
  mock / 100 OCCT, sim 35/35 both backends, in CI); a confirmation
  run on final HEAD was dispatched (4529…, see Actions).
- Build iPad IPA: SUCCESS (run 45287892716). Gate step output from
  the shipped executable's symbol table:
    0000000100cfe168 T _cc_execute
    0000000100cfe09c T _cc_session_create
    0000000100615c68 T _mc_clone_shape
    0000000100615d58 T _mc_export_stl
  plus catalog.json + default.metallib + both OCCT licences present.
- Delivered artifact: CascadeConsole v0.2.ipa, 9,147,334 bytes,
  md5 68175fd6d2940aa3527f66f6427dbceb; bundle com.user.cascadeconsole
  0.2 (2), verified independently from the downloaded IPA.
- Known CI wart: the CascadeKit cache only saves when the whole IPA
  job succeeds, so fix-loop iterations each paid the ~55-70 min kit
  build. Splitting the kit into its own workflow would fix that;
  left as-is for v0.2.
