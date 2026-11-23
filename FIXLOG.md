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
