# Cascade Console — iOS / iPad App

**Xcode project:** `CascadeConsole.xcodeproj` in this folder (target
`CascadeConsole`, bundle id `com.user.cascadeconsole`, iPad only,
deployment target iOS 17.0, shared scheme `CascadeConsole`). It builds
against the Swift `StubEngine` in `Shared/Engine/` — the native OCCT
Layer-2 library does not exist yet (TODO in project.pbxproj).

iPad-first SwiftUI scaffold for the text-command Open CASCADE CAD app.
Target device used for layout decisions: iPad Air M3, 11-inch, 1180x820 pt
landscape. Also runs on iPhone (compact layout collapses to tabs).

> Honesty note: this scaffold was written and syntax-reviewed line by line
> in a Linux sandbox. It has **not** been compiled. First build must happen
> in Xcode / GitHub Actions (standard free `macos-26` runner, unsigned IPA).
> Code is deliberately standard SwiftUI, no exotic APIs, no force-unwraps,
> to minimise first-CI errors.

## Layout of this folder

```
Apps/iPad/
  README.md                         (this file)
  CascadeConsole.xcodeproj          target CascadeConsole (see above)
  Sources/
    CascadeConsoleApp.swift         @main entry, scene + first-launch seeding
    Models/
      AppState.swift                ObservableObject: log, objects, selection
      ExampleScript.swift           Welcome script + sample project (strings)
    Services/
      FileStore.swift               Documents-folder store (picker-independent)
    Viewer/
      ViewerBridge.swift            Placeholder bridge (Agent 5 adapter)
      ViewportPlaceholderView.swift SwiftUI placeholder conforming to bridge
    Views/
      ContentView.swift             Split layout (iPad) / tab layout (compact)
      ConsoleView.swift             Output log + command input + history
      ObjectListView.swift          Scene object list, selection, visibility
      FileBrowserView.swift         In-app browser over Documents (see below)
      SettingsView.swift            Units, tessellation, theme, autosave, console
      WelcomeView.swift             First-launch sheet
      GlassStyle.swift              Liquid Glass (iOS 26) + material fallback
  Resources/
    welcome.cascade                 Same welcome script, as a plain file
    sample-project.cascade          Same sample project, as a plain file
```

The target also compiles the canonical Shared core from `../../Shared/`
(models, settings keys, engine protocol + StubEngine, command history,
the Metal viewer Swift + `Shaders.metal`) and bundles
`Shared/Resources/catalog.json` plus the OCCT licence texts as
resources. The per-app model/engine/settings files that used to live
here were deleted at build time — they duplicated the Shared types in
the same module (see the repo-root FIXLOG.md). No third-party packages
are required.

## UI structure

- **iPad (regular width):** `NavigationSplitView` — sidebar = object list +
  file shortcuts; detail = viewport on top, console below it (drag-free
  fixed split, roughly 55/45, natural proportions). Toolbar: Run, Clear Log,
  Files, Settings.
- **Compact width:** `TabView` — Console / 3D View / Objects / Files.
- **Input:** hardware keyboard (Return runs, Up/Down = history, Cmd-Return
  also runs), on-screen keyboard, and Apple Pencil (scribble works in the
  command field automatically; the viewport placeholder reserves Pencil
  gestures for Agent 5's viewer). No artificially inflated UI: system fonts
  and the device text-size setting are respected throughout.
- **Liquid Glass:** `GlassStyle.swift` provides `.glassPanel()` —
  `glassEffect(.regular, in:)` on iOS 26+, `ultraThinMaterial` fallback
  below that. Applied to toolbar chips, the command bar, and cards only,
  keeping contrast high and clutter low.

## File handling — read this, it is load-bearing

This user's sideloading certificate **breaks the system document picker**
in sideloaded apps. Therefore the app ships **both**:

1. **System picker** (`fileImporter` / `fileExporter` in `FileBrowserView`)
   — works in App Store / properly signed builds.
2. **In-app file browser** (`FileBrowserView` + `FileStore`) — lists,
   opens, saves, renames-by-save-as and deletes files directly in the
   app's own `Documents/` folder. This path uses only `FileManager` and
   needs no picker, so the app is fully usable sideloaded.

Supported types (by extension, content-agnostic at this layer):
scripts `.cascade`, `.txt`; models `.step`, `.stp`, `.iges`, `.igs`,
`.stl`, `.brep`. Import copies the picked file **into** Documents so it
stays reachable through the in-app browser afterwards.

## Connection points

### Agent 2 — core OCCT facade
- `Shared/Engine/EngineProtocol.swift` defines the unified
  `CascadeEngine` protocol: `execute(command:) async -> CommandResult`,
  plus `executeScript(_:)` and `knownCommands` (from catalog.json).
- Today it is satisfied by the Shared `StubEngine`, which handles
  `help`, `clear`, `echo` locally and otherwise answers
  NOT_IMPLEMENTED (E5002 / CC-SYS-000). **No fake geometry is ever
  produced.**
- To link the real core: add Agent 2's C facade (bridging header /
  C Swift package target), implement `OCCTEngine: CascadeEngine`
  calling the facade, and change one line in
  `CascadeConsoleApp.swift` (`engine: OCCTEngine()` instead of
  `StubEngine()`).
- Shape results should come back as opaque shape IDs (strings) in
  `CommandResult.producedShapeIDs`; `AppState` turns them into
  `SceneObjectItem`s and forwards them to the viewer bridge.

### Agent 5 — Metal viewer
- `Viewer/ViewerBridge.swift` keeps only `PlaceholderViewerBridge`
  (the normative protocol is Agent 5's `ViewerBridge` in
  `Shared/Viewer/Swift/ViewerBridge.swift`, implemented by
  `CascadeRenderer`): `displayObject(id:name:)`, `removeObject(id:)`,
  `clearScene()`, `fitAll()`, `setWireframe(_:)`, and an
  `onObjectPicked` callback.
- `PlaceholderViewerBridge` + `ViewportPlaceholderView` satisfy it now:
  a labelled placeholder with grid backdrop, object count, Fit / Wireframe
  buttons wired to the bridge (so wiring is testable before Metal lands).
- To swap in the real viewer: replace the placeholder view in
  `ContentView` / compact tabs with Agent 5's `MTKView` wrapper, keep the
  same bridge object from `AppState.viewer`, done.

### Settings
`Shared/Settings/SettingsKeys.swift` is the single source of
`@AppStorage` keys (canonical `cc.*` scheme for both apps):
`units` (mm/cm/inch), `tessellationQuality` (low/medium/high/fine),
`appearance` (system/light/dark), `highContrast` (bool), `autosave`
(bool), `autosaveIntervalMinutes`, `consoleFontSize` (points) and
`consoleFontSizeStep` (the iPad's relative step), `showTimestamps`,
`confirmBeforeClear`. The engine and viewer should read
tessellation/units from here at call time.

## First launch

- `CascadeConsoleApp` seeds `Documents/welcome.cascade` and
  `Documents/sample-project.cascade` on first launch only (flag in
  `UserDefaults`), loads the welcome script into the console, and shows
  `WelcomeView` once. All seeding is `do/catch` — a failed seed logs and
  continues; there is no launch path that can crash on missing files.
- No force-unwraps, no `try!`, no implicitly unwrapped optionals anywhere
  in `Sources/` (verified by grep before delivery).

## Known risks

1. **Uncompiled** — first CI will likely surface small SwiftUI type-check
   nits (especially around `fileExporter` document plumbing). Files are
   kept small and standard to make those one-line fixes.
2. `glassEffect` needs the iOS 26 SDK (Xcode 26 on the runner); the
   availability guard means the code also compiles against older SDKs
   only if the deployment target guard is kept — if CI uses an older
   Xcode, remove `GlassStyle`'s iOS 26 branch.
3. System picker may still fail sideloaded — that is expected; the
   in-app browser is the supported path there, and the UI says so.
4. External display: not implemented. Note for later — on iPadOS a
   second scene for the viewer only (console stays on iPad) is the
   natural design; `ViewerBridge` already isolates the viewer enough
   to allow it.
