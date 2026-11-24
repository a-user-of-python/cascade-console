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

## v0.2.1 — device-feedback fixes (2026-11-23)

The user's iPad test of v0.2 (object "test" in the sidebar) showed
three defects, all in the family "proven on the host OCCT backend,
never run on the device mc backend / device environment":

1. **Viewer renders nothing; viewport says "0 object(s)"** although
   the session holds the object. ROOT CAUSE (in
   `Core/native/src/ccgeom_mc.cpp`): `ccgeom_tessellate` and
   `ccgeom_face_ranges` copied the mesh arrays out of
   `mc_tessellate`'s result and then read `mesh.vertexCount` /
   `mesh.triangleCount` / `mesh.faceCount` AFTER calling
   `mc_free_mesh(&mesh)` — and the facade's `mc_free_mesh` frees the
   arrays and then memsets the whole `MCFacadeMesh` struct to zero
   (cascade-port `Facade/occt_facade.cpp`). Every count therefore
   came back 0: `cc_view_data` returned each object with 0 vertices
   / 0 triangles / 0 face ranges, `EngineMeshAdapter` skipped it
   (it requires >= 3 indices), and the renderer honestly reported
   an empty scene. FIX: capture the three counts BEFORE
   `mc_free_mesh`, in both functions, with the rule commented at
   both sites. Additionally, the failure is no longer silent:
   `EngineViewDataProviding.viewData` now returns an
   `EngineViewDataResult` whose `errorMessage` carries the
   session's `cc_last_error` text, AppState logs
   "Viewer feed failed: ..." plus diagnostics when the session has
   objects but no view data arrived, and ContentView refreshes the
   scene when the viewport appears.
2. **`view test` -> red error "Could not write view data to
   'test'."** ROOT CAUSE (app layer): `ViewCommandParser` has no
   object-name case, so `view <name>` fell through AppState's
   dispatch to the engine, whose `view` is the host-debug grammar
   `view <path.json> [name] [deflection]` — it treated "test" as a
   file path and its `std::ofstream` failed in the app sandbox.
   FIX (iPad `AppState.handleViewCommand`; the Mac AppState gets
   the same interception — its stub engine silently swallowed
   these lines): a `view` line NEVER reaches the engine now.
   Parser subcommands go to the renderer as before; `view <name>`
   / `view <name> fit` select an existing session object and
   refresh ("Showing '<name>'."); an unknown name is a clear
   console error ("view: no object named '<name>'."); bare `view`
   shows everything. The engine's host-debug form stays in the
   interpreter for the host CLI/tests only.
3. **`export-stl test test.stl` -> "mc_export_stl: writer did not
   complete"** (and any console export with a bare file name).
   ROOT CAUSE (app layer owns device file paths): AppState did not
   intercept export commands, so the engine received the raw
   relative path and wrote against the process working directory —
   not writable under the iOS sandbox, and not Documents. The
   writer itself is sound: OCCT 8.0.1's `StlAPI_Writer::Write`
   returns false only when the output stream cannot be opened or
   the shape has zero triangulation, and the CI-injected
   `mc_export_stl` meshes first via `BRepMesh_IncrementalMesh`,
   whose parameterized constructor calls `Perform()` (both facts
   read in the OCCT sources). The per-command matrix below proves
   the same injected `mc_export_stl` writes a valid ASCII STL to a
   writable path, and that an unwritable path fails honestly with
   EXPORT_FAILED. FIX (iPad `AppState.routeExportToDocuments`):
   `export` / `export-step` / `export-stl` lines whose target is a
   bare file name are rewritten to the app's Documents folder
   before the engine call, and the console result is displayed with
   the Documents/ prefix so the user can find the file in the
   in-app browser; the engine's multi-target `_<name>` insertion
   operates on the rewritten absolute path, so per-object files
   land in Documents too. Paths with a directory component pass
   through unchanged. Mac export is deliberately unchanged: the
   Mac engine is still the Swift stub, which writes no files at
   all, so there is no path to route until the Mac native-engine
   pass lands.

**New ship gate (the user's requirement: "a test on each command
before you give me the next version").** New job
`mc-backend-matrix` in `.github/workflows/build-native-engine.yml`
builds CascadeKit for the host from the SAME pinned cascade-ios
checkout + the SAME CI facade patch as the IPA build, links the
SAME five engine objects the app links, and runs two binaries:
`Core/native/tests/test_view_data_mc.cpp` (cc_view_data
invariants: counts > 0, indices in range, face ranges
census-ordered and partitioning the index buffer, centroids at
true face centres) and `Core/native/tests/test_matrix_mc.cpp` —
every command in `NativeEngine.knownCommands` driven through
`cc_execute` with a real invariant per command (analytic primitive
volumes; boolean volume arithmetic; fillet/chamfer in the
host-proven bands and exact values; transform bbox assertions;
session-state assertions for copy/duplicate/rename/delete/list/
info/clear; set/show-vars; undo/redo/history; echo/help output;
shape-history == E5002 by design; `run` on a script file; export
files verified on disk — STEP carries ISO-10303-21, STL is ASCII
with facet records, multi-target files land per object; engine
`view` JSON reports triangleCount > 0; the sim subset solves a
box cantilever whose root/tip faces are discovered from the
census centroids, max displacement within 5% of Euler-Bernoulli
at two mesh sizes; sim modal == E5002). Local pre-CI proof on this
machine (patched facade from the local cascade-port tree + conda
OCCT 8.0.1): matrix 117 pass / 0 fail, smoke 18 pass / 0 fail —
CI on the pinned checkout is the deciding run, recorded below.

**Investigated, NOT a bug:** the console showed "Saved
sample-project.cascade to Documents." four times in a row. That
line is only produced by `AppState.saveBuffer()`, whose callers are
the explicit Save buttons and ContentView's scenePhase autosave
(save the buffer when the app leaves the foreground, when the
autosave setting is on). First-launch seeding uses
`FileStore.seedIfMissing`, which never logs that line and is
gated by a UserDefaults flag. Four identical lines = the app was
backgrounded four times with sample-project.cascade as the current
file (e.g. while taking/sharing screenshots); each backgrounding
re-saves the same buffer, harmlessly. No code change.

CI on the v0.2.1 commit (2f9708b2): Host tests SUCCESS (run 45312784599);
Build Mac app SUCCESS (45312784548); Build iPad IPA SUCCESS (45312784644,
symbol gate green); Native engine SUCCESS (45312784652) — the new
mc-backend-matrix job reports "RESULT: 18 pass, 0 fail (mc view-data
smoke)" and "RESULT: 117 pass, 0 fail (mc per-command matrix)", with the
sim cantilever at 0.193548 mm coarse / 0.198820 mm fine through cc_execute
on the mc backend, identical to the local proof run. The IPA artifact was
downloaded and verified by hand: bundle com.user.cascadeconsole, version
0.2.1 (3), cc_execute / cc_session_create / mc_clone_shape / mc_export_stl
present, catalog.json + default.metallib + both OCCT licence texts
bundled; 9,156,944 bytes, md5 6e2ad5969d73d94ec76d91eca4edead3.

Version: MARKETING_VERSION 0.2.1, CURRENT_PROJECT_VERSION 3.

## v0.2.2 — device-feedback fixes (2026-11-24)

The user's iPad test of v0.2.1 reported two defects:

1. **Created geometry renders inverted / inside-out** ("The
   geometry is inverted so I can't see it"). Objects now reach the
   viewer (the v0.2.1 use-after-free fix works) but appear
   inside-out. ROOT CAUSE (Swift viewer layer,
   `Shared/Viewer/Swift/Camera.swift`): the perspective matrix was
   LEFT-handed — the glm `perspectiveLH_ZO` form, clip w = +z_view
   and NDC z decreasing with distance — while the view matrix
   (right-handed lookAt), the model data (OCCT, right-handed) and
   Metal's defaults are all right-handed. Proven numerically by
   replicating the shipped formulas: every point in front of the
   camera had clip w < 0 (36/36 box corners), which inverts the
   rasterizer's front/back facing test — with Metal's default
   back-face culling the near faces are culled and the inside of
   the far side shows — and NDC z DEcreased with distance
   (1.003 -> 1.0004 over 10..80 mm), so under the renderer's
   less-than depth test far surfaces beat near ones. The
   orthographic matrix had the same inverted depth slope.
   The mesh data was investigated first and is NOT the cause:
   both engine tessellators (façade `mc_tessellate` and
   `ccgeom_occt`) flip triangle winding for TopAbs_REVERSED faces,
   and a probe through `cc_view_data` on BOTH backends (OCCT 8.0.1;
   mc over the CI-patched façade) shows signed mesh volume ==
   analytic volume (box +1000, L-prism +6000, cylinder ~0.99x),
   all 6 box face normals outward, and an asymmetric L prism NOT
   mirrored (notch corner at (10,10), none at (20,10)). No
   mirrored transform exists in the view-data path (model matrix
   is identity/translation only) and the renderer sets no cull /
   winding overrides. FIX at the wrong layer only: Camera.swift's
   perspective is now the right-handed form (clip w = -z_view > 0
   in front; NDC z 0 at near -> 1 at far, increasing with
   distance) and the orthographic z slope is flipped to match.
   Picking and face labels consume the same view-projection (and
   its inverse), so they stay consistent automatically. Rendering
   is correct by default on creation; no command or setting.
   REGRESSION GUARDS: (a) new orientation invariants in
   `Core/native/tests/test_engine.cpp` (OCCT backend) and
   `Core/native/tests/test_view_data_mc.cpp` (mc backend): signed
   mesh volume > 0 and matching analytic for box / cylinder /
   L-prism, box face-range normals outward (dot > 0, all 6), L
   notch not mirrored; (b) new
   `Shared/Viewer/Verification/verify_projection.py`, run by the
   Host tests workflow, which mirrors Camera.swift's formulas and
   asserts clip w > 0 in front, NDC z in [0,1] and increasing with
   distance, correct front/back classification of a box's faces,
   and the orthographic depth slope. (Swift itself still cannot
   be compiled on the host; the guard pins the formulas, and the
   user's device verdict remains the final judge.)
2. **File sharing is off**: the app's Documents folder (where
   v0.2.1 routes exports) is not visible via the Files app /
   Finder file sharing. VERIFIED FROM THE SHIPPED ARTIFACTS, not
   the project file: the delivered v0.1, v0.2 and v0.2.1 IPAs'
   Info.plists all contain LSSupportsOpeningDocumentsInPlace =
   true but NO UIFileSharingEnabled key at all — although
   `INFOPLIST_KEY_UIFileSharingEnabled = YES` has been in the
   target's build settings since v0.1 (the build-prep note
   claiming "file sharing enabled" was wrong about the shipped
   binary). The generated-Info.plist route silently drops this
   key. FIX: the app now carries an explicit
   `Apps/iPad/Info.plist` with UIFileSharingEnabled = true and
   LSSupportsOpeningDocumentsInPlace = true, wired via
   INFOPLIST_FILE (the INFOPLIST_KEY_* settings remain as well),
   AND the build-ipa bundle gate now asserts both keys are true
   in the built .app's Info.plist (PlistBuddy), so this cannot
   silently regress again.

Version: MARKETING_VERSION 0.2.2, CURRENT_PROJECT_VERSION 4.

CI on the v0.2.2 commit (d5686c9b): all four workflows SUCCESS —
Host tests (run 45385218536, incl. the new projection guard and the
tessellation contract); Build Mac app (45385218378); Build iPad IPA
(45385218663, symbol gate + new file-sharing PlistBuddy gate green);
Native engine (45385218404) — mc-backend matrix job reports
"RESULT: 117 pass, 0 fail (mc per-command matrix)" and
"RESULT: 26 pass, 0 fail (mc view-data smoke)" (18 + 8 new
orientation checks), engine host suites 112 pass OCCT / 94 pass
mock with the same orientation invariants. The IPA artifact was
downloaded and verified by hand: bundle com.user.cascadeconsole,
version 0.2.2 (4), cc_execute / cc_session_create / mc_clone_shape /
mc_export_stl present, catalog.json + default.metallib + both OCCT
licence texts bundled, and — the file-sharing fix proven in the
shipped binary — Info.plist carries UIFileSharingEnabled = true
and LSSupportsOpeningDocumentsInPlace = true. 9,156,298 bytes,
md5 0dc9dbfdbcde23e249dc0007fceec63c.

## v0.2.3 — device-feedback fixes (2026-11-24)

The user's iPad test of v0.2.2 reported, with a screenshot:
`box test 10 2 10` → "Created test.", the object listed in the
sidebar — but the viewport shows a spiky fan (a couple of large
pale triangles plus dozens of thin slivers radiating from one
point) and the header still says "0 object(s)". ("This don't look
like a box.")

1. **The fan — vertex-buffer layout mismatch (Swift viewer
   layer).** The chain was audited end to end against bytes from
   the real engine. The C++ view data is GOOD (re-proven this
   round: cc_view_data for the 10x2x10 box on the OCCT backend
   returns 24 vertices / 12 triangles, signed mesh volume +200,
   bbox [0 0 0 .. 10 2 10], 6 census face ranges, no out-of-range
   indices; the v0.2.2 mc-backend probes agree). NativeEngine's
   bridging, EngineMeshAdapter's CCM1 writing and
   MeshBufferLoader's parsing are mutually consistent (the adapter
   unwelds per corner; indices are sequential; the loader validates
   unit normals and index ranges). The corruption is in the LAST
   step: `CascadeRenderer.upload` copies the `[MeshVertex]` array's
   raw memory into the MTLBuffer, but `buildPipelines` described
   that buffer with `MeshVertex.stride` = 24 and normal offset 12 —
   the PACKED CCM1 FILE layout. A `MeshVertex` in memory is two
   `SIMD3<Float>` members, each 16-byte aligned with a 16-byte
   stride (verified with a Swift layout probe: struct stride 32,
   normal at byte offset 16). The GPU therefore strode 24 bytes
   per vertex through 32-byte records. Deterministic host
   reproduction from the real fixture: with the shipped descriptor
   only 4 of 36 box-corner vertices are fetched at their true
   positions, 20 fetched "positions" are actually normal-vector
   components (all within +/-1 of the origin — the fan's hub), and
   the GPU-visible signed volume is -17 instead of +200. With the
   correct descriptor values (32/16) all 36 vertices are exact and
   the volume is +200. FIX at the wrong layer: MeshBuffer.swift
   now keeps `stride` = 24 as the documented CCM1 FILE stride only,
   and adds `bufferStride` / `bufferNormalOffset` derived from
   `MemoryLayout<MeshVertex>` (so they can never drift from the
   type again); Renderer.swift's vertex descriptor declares those.
   Nothing else in the chain changed — picking and face labels read
   the CPU-side MeshObject and were never affected.
2. **Header "0 object(s)" over a drawn scene.** The header read
   `renderer?.objectIDs.count` in ViewportView's body, but
   ViewportView observes nothing that changes after a load:
   AppState's only @Published mutations in refreshScene (the
   sidebar sync) happen BEFORE `loadMesh`, and nothing publishes
   afterwards, so the count was evaluated while the renderer was
   still empty and never re-evaluated. FIX: AppState publishes
   `viewerObjectCount`, assigned from `renderer.objectIDs.count`
   AFTER the load loop in refreshScene (and after removeObject /
   clearScene mutations); ViewportView displays that value, passed
   from ContentView at both layout sites.
3. **The test hole that shipped this twice is closed.** Every
   previous gate stopped at the C++ boundary — the Swift parser
   and layout code had never been executed by any test. The
   mc-backend-matrix CI job now (a) builds and runs
   `Core/native/tests/dump_view_fixture.cpp` against the device-
   path mc backend, writing its cc_view_data output (box + cylinder)
   to a fixture, and (b) compiles the PRODUCTION Swift sources
   (MeshBuffer.swift, EngineMeshAdapter.swift, EngineProtocol.swift,
   SharedModels.swift) with `Shared/Viewer/Verification/swift-harness/main.swift`
   via swiftc and runs the harness against the fixture. The harness
   asserts the adapter+loader round-trip (counts, names, derived
   bbox, census face-group partition, signed volume: box exactly
   +200, cylinder within tessellation tolerance) AND re-reads the
   parsed vertex array's raw memory with the descriptor's layout
   values, asserting every vertex and the signed volume survive —
   the exact read whose failure produced the fan. With the old
   24/12 constants that check fails; that is the point of it.

Version: MARKETING_VERSION 0.2.3, CURRENT_PROJECT_VERSION 5.
Nothing was removed from knownCommands.

CI on the v0.2.3 commit (f238ba41): all four workflows SUCCESS —
Host tests (run 45393184087: prototype 47/47, tessellation
contract, projection guard); Build Mac app (45393184010); Build
iPad IPA (45393184129: symbol gate + file-sharing PlistBuddy gate
green); Native engine (45393183863) — mc-backend matrix job
reports "RESULT: 117 pass, 0 fail (mc per-command matrix)",
"RESULT: 26 pass, 0 fail (mc view-data smoke)", and the new
"RESULT: 25 pass, 0 fail (swift viewer harness)" against an
mc-backend fixture whose numbers match the host OCCT fixture
exactly (box 24 vertices / 12 triangles / volume 200; cylinder
106 / 100 / 339.292); engine host suites 112 pass OCCT / 94 pass
mock, sim 35/35 on both backends (also re-run locally from this
tree before the push: 112 OCCT, 35/35 sim, 47/47 prototype,
contract + projection guards green). The IPA artifact was
downloaded and verified by hand: bundle com.user.cascadeconsole,
version 0.2.3 (5), cc_execute / cc_session_create / mc_clone_shape
/ mc_export_stl present, catalog.json + default.metallib + both
OCCT licence texts bundled, Info.plist carries
UIFileSharingEnabled = true and
LSSupportsOpeningDocumentsInPlace = true. 9,157,068 bytes,
md5 6fcce7d3a90d04f0449d9b6afec3ce15. The user's device verdict is the
final judge: create a box — it should render as a solid box
immediately, with the header reading "1 object(s)".

## v0.2.4 — device-feedback fixes + view features (2026-11-24)

The user's iPad test of v0.2.3: `box test 10 2 10` now renders
SOLID and the header reads "1 object(s)" — the v0.2.3 stride fix
works on device. But a fan of thin coloured lines (red,
yellow-green, grey) radiates from a single point at the box's
origin corner. The user also asked for: a rotate command, XYZ
coordinate arrows that "don't take up that much space", and a
command to label edges.

1. **The fan — the SAME layout disease, in the line path.**
   v0.2.3 fixed the mesh vertex descriptor; the line pipeline had
   its own hand-written constants, and they were wrong the same
   way. `LineVertex` (Renderer.swift, private) is
   `{ position: SIMD3<Float>, padding: Float, color: SIMD4<Float> }`
   with a comment claiming "colour at offset 16, stride 32". By
   the same SIMD layout rules the v0.2.3 probe proved (SIMD3<Float>
   is 16-byte aligned, 16-byte stride), the real layout is
   position @0, padding @16, colour @32, **stride 48**. The line
   vertex descriptor declared stride 32 / colour offset 16, and
   every line-buffer copy (grid/axes buffer, edge overlay, measure
   lines) truncated the array to `count * 32` bytes. Convicted by
   numerical reproduction of the exact default scene (box
   10x2x10 at the origin, grid + axes visible: 106 line vertices,
   53 segments — 50 grid + 3 axes): re-reading the built array
   through the shipped descriptor, only **2 of 106** vertices land
   on their true position, **0 of 53** segments are intact, and
   **53 of 53** segments have an endpoint within 1.0 of the
   origin — the fan's hub at the box's origin corner. The
   collapsed "positions" are the padding/origin and the grid grey
   (0.35, 0.37, 0.40) read as a position; the colours are
   cross-reads of position data ((17, -11, 0) clamps to saturated
   red, (-7, 13, 0) to green) — the red / yellow-green / grey fan
   in the screenshot, exactly. With the descriptor at the real
   layout (48/32), all 106 vertices round-trip exact. A second
   bug lived in the same function: `rebuildGridIfNeeded`'s cache
   key ignored the visibility flags and the grid was built
   unconditionally, so `view grid off` changed nothing and
   toggling axes never rebuilt. FIX at the wrong layer:
   `LineVertex` and all line builders moved to the new pure file
   `Shared/Viewer/Swift/SceneHelpers.swift` (Foundation + simd
   only, no Metal), with `bufferStride` / `bufferColorOffset`
   derived from `MemoryLayout` — the descriptor and every buffer
   copy now use those, and the rebuild key covers the full bounds
   + both visibility flags, which also gate the builders.
2. **XYZ arrows, small (feature).** The old axis lines ran from
   the origin to `half` = 1.2x the scene extent (12 units on this
   10-unit box — longer than the model). Replaced with compact
   arrows at the world origin, same axis colours: length =
   **20% of the scene-bounds diagonal** (2.86 units on this box),
   floored at 0.5 units so they stay visible on sub-unit scenes;
   each arrow is a shaft + cone head drawn as lines (4 spokes +
   base ring, 18 vertices per arrow), with an X / Y / Z letter
   chip at the tip (black text on the axis colour, face-label chip
   style). They live in world space and rotate with the scene.
   Controlled by the existing `view axes on|off`; **default stays
   ON** — the arrows are now small enough not to interfere, which
   was the user's actual complaint about the old lines.
3. **`view rotate` (feature).** `view rotate <azimuthDeg>
   <elevationDeg>` sets the absolute orbit position (degrees;
   elevation clamps to the camera's ±89.9° pole limit);
   `view rotate by <dAzimuthDeg> <dElevationDeg>` rotates
   relative. The angle application lives in `OrbitCamera`
   (`setRotation` / `rotateBy`) so the CI harness executes the
   production code path, not a copy. Object rotation is a
   different, pre-existing engine command —
   `rotate <name> <src> <ax> <ay> <az> <angleDeg> [about x,y,z]`
   (cc_interpreter.cpp) — noted in the catalog so the two are not
   confused.
4. **Edge labels (feature).** `view labels edges on|off`
   (default OFF), mirroring face labels: black-on-white chips at
   each edge's midpoint, showing the edge's census index. The
   numbers are the backend's own census, end to end: new
   `ccgeom_edge_list` (OCCT backend: `TopExp::MapShapes(TopAbs_EDGE)`
   order — the identical enumeration `pickEdges` selects from for
   fillet/chamfer; mc backend: the facade's `mc_edge_count` /
   `mc_edge_info`, whose header guarantees one shared TopExp
   census across tessellation, fillet, chamfer and edge info; no
   facade addition was needed; mock: the bbox placeholder's 12
   edges when the shape's census count is 12, documented) →
   `CCViewData.edges` → `EngineViewObject.edges` → CCM1 **v2**
   edge section → `MeshObject.edges` → chips. The loader still
   accepts CCM1 v1. Census proof, run on BOTH real backends
   (host OCCT in test_engine, device-path mc in
   test_view_data_mc + test_matrix_mc): label count ==
   cc_object_stats edge count (box 12, cylinder, demo part3);
   endpoint set == the box's 12 geometric edges; and per edge k,
   `fillet ... edges k` removes exactly (1 - pi/4) * L_k (L_k
   from the label endpoints — the index selects the labelled
   edge's length class) AND `chamfer ... edges k` puts its new
   face at labelled edge k's midpoint (nearest-midpoint binding —
   the index selects THAT edge, not a same-length sibling).
   HONEST LIMIT: facing uses a radial test — an edge's midpoint
   direction from the object centre vs the camera direction —
   because view data carries endpoints only, no edge normal; a
   long edge straddling the silhouette can show/hide at its
   midpoint's discretion. Anchors are mesh-space, exact at
   explode factor 0, same as face labels.
5. **The gate grew teeth in the line path.** The Swift harness
   now also compiles SceneHelpers.swift, ViewCommands.swift,
   ViewerBridge.swift, Camera.swift and SceneStore.swift from
   production sources and: runs the production grid + arrow
   builders on the exact default scene and re-reads the built
   [LineVertex] array through the declared line layout (every
   vertex — position AND colour — must come back exact); asserts
   the arrow length formula (20% of diagonal, floor), tip
   positions and bounded extent; runs the edge-overlay builder on
   the parsed box; round-trips the fixture's census edges
   (CCFX v2 → CCM1 v2 → MeshObject.edges, endpoint set == the
   box's 12 geometric edges); and parses `view rotate` /
   `view rotate by` / `view labels edges` with the production
   parser, applying the parsed angles through the production
   OrbitCamera methods on a SceneStore. The CCFX fixture format
   is v2 (adds per-object census edges).

Version: MARKETING_VERSION 0.2.4, CURRENT_PROJECT_VERSION 6.
Nothing was removed from knownCommands; the new commands are
app-layer view commands, added to the catalog `view` entry,
COMMAND_CATALOG.md and COMMAND-COVERAGE.md.

Local results before the push (this tree): engine OCCT (conda
8.0.1) 123 pass / 0 fail (was 112; +11 edge-census checks),
engine mock 100 pass / 0 fail / 5 skip (was 94/3; the mock's two
census-binding checks are honestly skipped — the mock has no
real fillet/chamfer geometry), sim 35/35 on both backends,
prototype 47/47, tessellation contract (CCM v2) verified,
projection guard green, ccgeom_mc.cpp compiles against the real
cascade-port facade. (Local host runs use the conda OCCT 8.0.1
tree with a manual rpath-link line — the sandbox has no distro
OCCT dev packages; CI's engine-host job runs the same suites
against distro OCCT via build_host.sh / build_sim.sh as before.)

CI on the v0.2.4 commits (ef53c32b + harness-check correction
c1181d88): all four workflows SUCCESS — Host tests (run
45437164106: prototype 47/47, tessellation contract, projection
guard); Build Mac app (45437164029); Build iPad IPA (45437164110:
bundle gate green); Native engine (45440245476, re-dispatched
after the first attempt's matrix job was cancelled in the macOS
runner queue — no code change): "RESULT: 125 pass, 0 fail (mc
per-command matrix)" (117 baseline + 8 edge-census checks),
"RESULT: 35 pass, 0 fail (mc view-data smoke)" (26 + 9, including
the per-edge fillet/chamfer census binding on the device
backend), "RESULT: 53 pass, 0 fail (swift viewer harness)" (25 +
28: line layout 48/32 pinned, all 154 default-scene line vertices
re-read exact, arrow length 2.8566 == 20% of the box diagonal,
edge round-trip + endpoint set, rotate/labels parsing + camera);
engine host suites 123 pass OCCT / 100 pass + 5 skip mock, sim
35/35 both backends. One harness check was corrected mid-loop:
the edge-overlay segment set is 18 distinct position pairs (12
geometric edges + 6 face diagonals), not 12 — the overlay is
built from the unwelded triangle soup, as it always has been;
the census-12 truth lives in MeshObject.edges and is asserted
separately. The IPA artifact was downloaded and verified by
hand: bundle com.user.cascadeconsole, version 0.2.4 (6),
_cc_execute / _cc_session_create / _mc_clone_shape /
_mc_export_stl present, catalog.json + default.metallib + both
OCCT licence texts bundled, UIFileSharingEnabled = true and
LSSupportsOpeningDocumentsInPlace = true. 9,170,580 bytes,
md5 5276f888e579be134031988e0e5b6d1a. The user's device verdict
is the final judge: the fan should be GONE (grid + small XYZ
arrows only), `view rotate 45 30` should swing the camera,
`view labels edges on` should number the box's 12 edges with
the fillet/chamfer census indices.

## v0.3.0 — UI-first redesign: history, part tree, command UI, name directories (2026-11-24)

Commissioned 2026-11-24: (1) add a history; (2) add a part tree
with folders; (3) replace typed command entry with a UI — a RIGHT
sidebar holds the command UI with sliders/inputs, the properties
inspector moves LEFT, names are auto-assigned when none is given;
(4) separate name directories per command type, so a box and a cut
can share a name. The standing ship rule applies unchanged: the
per-command matrix on the real mc backend must be green, and the
Swift harness must execute the new production model-layer code
against real backend fixtures before any IPA ships.

### Design choices (where the commission left a detail open)

- **Architecture.** The native engine + interpreter remain the
  execution layer. The UI is a parametric layer of STEPS (command +
  parameter values + result name) in `Shared/Model/`. Editing or
  deleting a step replays the step list into a FRESH engine session
  and adopts it only on full success; a failed replay leaves the
  current model untouched and reports the failing step by number
  and title — never a silent partial model. View commands are NOT
  steps (viewer state, unchanged).
- **One editor surface.** The right sidebar holds the command list;
  below it, ONE editor: in Add mode it edits the selected command's
  form; selecting a history step or a part switches it to that
  step's parameters (Apply = replay). Documented choice per the
  commission's either/or.
- **Console.** Demoted, not deleted: on iPad it is a toolbar sheet
  (regular width) / a tab (compact). Scripts, exports, `set`, and
  the `sim` family live there. Objects created by typing console
  commands are session-only — they are not steps, and the next
  replay rebuilds the session from the step list alone. Stated
  here rather than discovered by the user.
- **UI command list.** Only the 15 implemented step commands:
  box, cylinder, sphere, cone, torus, profile, extrude, union, cut,
  intersect, fillet, chamfer, translate, rotate, copy. Forms are
  generated from parameter specs (`Shared/Model/CommandSpecs.swift`):
  sliders paired with numeric fields (typed value always wins;
  ranges generous: lengths 0.1–500 mm etc., documented in the
  specs), object/profile references are pickers fed from the
  session (never free text), fillet/chamfer edge lists are optional
  text (blank = all edges — the numbers are the viewer's census
  edge labels). Unimplemented catalog commands do NOT appear.
- **Layout.** Regular width: LEFT = segmented panel (Parts tree /
  History / Properties — the inspector moved from the right),
  CENTRE = viewport, RIGHT = command UI. Compact: tabs Model /
  Build / Library / Console / Files.

### Name directories — real, in the session layer

Implemented in `Core/native/src/cc_interpreter.cpp`, not as a UI
cosmetic. Session keys are qualified `dir:name`; the directory is
the canonical creating command (aliases fold: fuse→union,
common→intersect, duplicate→copy; profiles live in profile/).

- Creating never errors because ANOTHER directory holds the name:
  box "part" and cut "part" coexist.
- Within one directory names are unique: a colliding create is
  AUTO-SUFFIXED (part → part2, and a trailing number increments:
  part2 → part3), and a name omitted at the console keeps the old
  auto-numbering (now per-directory). Consequence, stated plainly:
  the C++ session no longer produces E1006 DUPLICATE_NAME (the
  code remains in the error enum; the Python reference prototype
  still implements the old error and is unchanged — a documented
  divergence).
- Resolution order for a name used as an operand (also in
  docs/catalog/COMMAND_CATALOG.md): (1) qualified `dir:name` exact;
  (2) the context directory the position expects (extrude's profile
  operand → profile/); (3) a bare display name matching exactly ONE
  key across directories; (4) several matches → E1005, listing the
  directories and a qualified example — never a silent guess.
  In-place forms (`fuse a b as a`, `fillet ... as <source>`) take
  the operand's own qualified key/directory. Rename keeps the
  object's directory. `list` prints qualified keys; result messages
  print display names. cc_object_stats / cc_view_data / the C API
  resolve through the same rules; new cc_profile_count /
  cc_profile_name expose the profile directory to the app.
- The Swift mirror (`CascadeNames.uniqueName/autoName`) implements
  the identical claim rule so the UI can show the exact name a
  create will claim; the harness pins the parity against the real
  backend (below).

### Persistence + migration

New project format `.cascadeproj` (JSON: format tag + version,
steps with params + assigned qualified names, folders, object→
folder assignments by qualified name, viewer snapshot: grid/axes/
labels/display mode/camera angles). Reopening replays the steps —
history, tree and model restore exactly; no mesh data is stored.
Autosave is unchanged (script buffer on background, labelled as
before); project saving is explicit (Save Project / Save As in the
toolbar) so a half-edited history is never silently persisted.
Legacy `.cascade` scripts still load two ways: Open/Run as scripts
(unchanged), and **Import** in the Files tab, which migrates one to
a project whose history is a SINGLE "Imported script" step holding
the script text verbatim, replayed through the script runner. Its
commands are NOT reverse-engineered into parametric steps — that
is the honest limit of the migration.

### Gates extended (the v0.2.2–v0.2.4 lesson, applied to the new layer)

- Engine suites gained a namespace section (~28 checks: cross-
  directory coexistence, qualified resolution + volumes, ambiguity
  E1005, suffix + trailing-increment, profile-context resolution,
  rename/delete directory behaviour, in-place fuse, full replay
  name-set reproduction). Local: OCCT 153 pass / mock 129 pass +
  5 skip, sim 35/35.
- The mc per-command matrix gained the same namespace cases plus
  cylinder coexistence, an extrude volume assertion, and a replay
  block (125 baseline + new).
- The Swift harness now also compiles `Shared/Model/` and runs it
  against a NEW fixture the mc dump tool produces: a 10-step UI
  scenario executed on the real backend (engine-verified assigned
  names + analytic volumes, final name set, fresh-session replay
  proven engine-side). The harness asserts the production
  ReplayBuilder reproduces the engine's lines, predicted names and
  grouping byte-for-byte, plus CascadeNames parity cases, spec
  sanity, project round-trip, legacy migration shape, and folder
  rules. The CCFX fixture's object names are now qualified
  (box:test / cylinder:cyl) and the harness's name-keyed checks
  were updated to match.
