# Cascade Console — MacApp (macOS half)

Owner: Agent 3. This folder contains **only** the macOS app. It does not
contain the modeling core, the Metal viewer, or the iPad app.

A text-command 3D CAD app powered by Open CASCADE (OCCT): you type modeling
commands in a console, and the model appears in a 3D viewport. This scaffold
is the full macOS shell — console, object sidebar, viewport area, file
pickers, settings, menus, keyboard shortcuts — with the core and the viewer
plugged in behind two narrow protocols (below).

## Honest status

- **Not compiled in the sandbox.** There is no SwiftUI/macOS toolchain in
  the Linux environment this was written in, so no build has been run here.
  Every file was syntax-reviewed line by line and kept to simple, standard
  SwiftUI/AppKit so the first macOS CI build should need minimal fixes
  (known risk areas are listed at the bottom).
- The engine and viewer are **stubs on purpose**: a `StubConsoleEngine`
  that understands a handful of commands and a placeholder viewport panel
  that honestly labels itself. No fake geometry, no pretend 3D.

## Layout

```
MacApp/
  Package.swift                     SwiftPM manifest (macOS 14+, executable)
  CascadeConsoleMac/
    CascadeConsoleMacApp.swift      @main, window, menu bar commands, Settings scene
    ContentView.swift               split layout, glass toolbar, file-action handling
    ConsoleView.swift               output log, input line, history, autocomplete
    SidebarView.swift               object list: visibility, colour, delete
    AppState.swift                  all window state; command dispatch; history
    Models.swift                    SceneObjectItem, LogEntry, FileAction, palette
    EngineProtocol.swift            ConsoleEngine contract + StubConsoleEngine
    ViewerBridge.swift              ViewerBridge contract + placeholder viewer
    FileService.swift               NSOpenPanel/NSSavePanel + plain text IO
    SettingsView.swift              settings form (UserDefaults via @AppStorage)
    GlassStyle.swift                Liquid Glass with material fallback
    WelcomeScript.swift             first-launch welcome lines + example script
  README.md                         this file
```

## How to build

- **SwiftPM:** open `Package.swift` in Xcode on a Mac, or `swift build` in
  this folder, then run the produced `CascadeConsoleMac` executable.
- **Xcode app target:** create a macOS App target named
  `CascadeConsoleMac`, delete its template files, and add every file in
  `CascadeConsoleMac/` to it. No extra dependencies, no build settings
  beyond the defaults. Minimum deployment target used by the code: macOS 14
  (glass paths are availability-guarded to macOS 26).

## Interface contracts

### Core façade — Agent 2 (`EngineProtocol.swift`)

The app talks to the modeling core **only** through:

```swift
protocol ConsoleEngine {
    var knownCommands: [String] { get }   // drives autocomplete + help
    func execute(_ command: String, objects: [SceneObjectItem]) -> EngineResult
}
```

`EngineResult` carries log messages (plain language + stable error codes
such as `CC-E100`) and scene changes (`upserted` / `removedNames`, matched
by object name). Rules for the real engine:

- Never throw across this boundary and never crash on bad input — return an
  `.error` message with a code instead.
- `knownCommands` must be the **full** OCCT command catalog, not a subset:
  autocomplete and `help` are only as complete as this list.
- Import/export go through the engine as commands: the app's file pickers
  produce a path and then run `import "<path>"` / `export "<path>"`, so
  file models share exactly one code path with typed commands.
- To plug the real engine in, replace `StubConsoleEngine()` with the real
  type where `AppState` is created in `CascadeConsoleMacApp.swift`
  (AppState's `engine` is an injected property for exactly this).

App-level commands handled by `AppState` itself, never sent to the engine:
`clear` (log), `view fit`, `view clear`.

### Metal viewer — Agent 5 (`ViewerBridge.swift`)

```swift
protocol ViewerBridge: AnyObject {
    func render(objects: [SceneObjectSnapshot])  // names, visibility, colours
    func fitAll()
    func clearScene()
}
```

The viewer receives tessellated meshes from the core façade itself; this
bridge carries only snapshots (name / kind / visibility / colour) and view
actions. To plug the real viewer in: conform the Metal view's controller to
`ViewerBridge`, replace `PlaceholderViewerBridge` in `AppState.init`, and
replace `ViewportPlaceholderView` in `ContentView` with the real
`NSViewRepresentable`. Nothing else changes.

## UI notes

- **Liquid Glass:** all glass goes through `GlassStyle.swift`
  (`glassPanel()`, `glassButton()`, `GlassToolbarGroup`). On macOS 26 these
  use `glassEffect` / `GlassEffectContainer`; on older macOS they fall back
  to `ultraThinMaterial` / `thinMaterial` with a separator outline. The
  user's Mac (2019 Intel, macOS 26) takes the glass path; the fallback is
  there so the app still looks right anywhere else.
- **Accessibility / design rules:** high contrast, low clutter, natural
  proportions. Text sizes follow the system setting; the only size control
  is the console's own monospaced font size in Settings. No artificially
  inflated UI anywhere.
- **Settings** (all real, all `@AppStorage` / UserDefaults, keys in
  `SettingsView.swift` under `SettingsKey`): units (mm/cm/in), tessellation
  quality, theme (system/light/dark — applied via `preferredColorScheme`
  in `ContentView`), higher-contrast toggle, console text size, log length
  cap, autosave on/off + interval. The core reads units/tessellation from
  the same keys when it lands.
- **Keyboard:** Return runs a command; Up/Down in the input field walk
  command history; Cmd-O open script, Cmd-S save session script,
  Cmd-Shift-I import, Cmd-Shift-E export, Cmd-Shift-R welcome example,
  Cmd-K clear log, Cmd-Shift-F fit view. Settings is the standard
  Cmd-, scene.
- **First launch:** empty scene, three welcome log lines, input focused,
  nothing read from disk, no panel shown, no force-unwraps in any
  app-owned file — a clean launch has no crash paths.
- **Errors:** every failure surfaces in the console log as plain language
  plus a stable code (stub engine: `CC-E100`–`CC-E104`; files:
  `CC-E200`/`CC-E201`). The user guide explains each code.

## Risks for the first CI build

1. **Liquid Glass APIs** (`glassEffect`, `GlassEffectContainer`,
   `.glassEffect(.regular.interactive(), in:)`) require the macOS 26 SDK.
   Building with an older SDK will fail to resolve them even though the
   calls are availability-guarded at runtime — CI must use the macOS 26
   SDK / Xcode 26. This is the single most likely first-build failure.
2. `.onKeyPress(.upArrow / .downArrow)` requires macOS 14+; the package
   floor is set to macOS 14 for this. If the deployment target is raised,
   no change is needed; if lowered, history navigation needs an
   `NSViewRepresentable` input field instead.
3. `VSplitView`/`NavigationSplitView` column-width APIs are standard but
   worth a visual pass on the first run (layout, not compile, risk).
4. SwiftPM executable vs. Xcode app bundle: menu-bar `Settings` scene and
   `NSOpenPanel` behave identically in both, but bundle-only niceties
   (icon, document-type associations for `.ccs` / model files) can only be
   added in the Xcode target's Info.plist — not done here.
5. The stub engine does not implement `import` / `export`, so until
   Agent 2's engine lands, Import/Export pick a file and then log an
   "unknown command" error. That is deliberate scaffolding honesty, not a
   bug — but it should be re-checked once the real engine is wired in.
