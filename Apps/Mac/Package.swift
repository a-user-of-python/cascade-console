// swift-tools-version: 5.9
// Cascade Console — macOS app (BUILD agent, verified 2026-11-23).
//
// One executable target, `CascadeConsoleMac`, path `CascadeConsoleMac/`.
// All 12 Swift files in that folder exist and are picked up by SwiftPM
// automatically (no per-file list to drift):
//   AppState, CascadeConsoleMacApp, ConsoleView, ContentView,
//   EngineProtocol, FileService, GlassStyle, Models, SettingsView,
//   SidebarView, ViewerBridge, WelcomeScript.
//
// Shared/ dependency — EXPLICITLY RESOLVED (not silently missing):
// the Mac target does NOT depend on ../../Shared today, on purpose.
// The Mac scaffold is internally consistent with its own per-app types
// (Models.swift SceneObjectItem/LogEntry, EngineProtocol.swift sync
// ConsoleEngine + StubConsoleEngine, SettingsView.swift SettingsKey
// with the canonical cc.* strings). Adding Shared/ to this target now
// would create duplicate type definitions in one module
// (SceneObjectItem, Color(hexString:), and near-duplicate
// StubEngine/SettingsKeys/CommandResult surfaces) — the exact
// collisions INTEGRATION-NOTES.md resolution (f) leaves to the
// AppState-adaptation pass. That adaptation (repoint AppState at the
// Shared async CascadeEngine + CascadeRenderer, delete the per-app
// copies) is the documented TODO; until it lands, the Mac app builds
// standalone against its stub engine, which is the honest state.
// The iPad target (Apps/iPad/CascadeConsole.xcodeproj) DOES include
// Shared/ — the two apps are at different adaptation stages, and this
// file + INTEGRATION-NOTES.md are where that difference is recorded.
import PackageDescription

let package = Package(
    name: "CascadeConsoleMac",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CascadeConsoleMac",
            path: "CascadeConsoleMac"
        )
    ]
)

// MARK: - Native engine (ENGINE agent, 2026-11-23)
// The Mac target does NOT gain a native-engine target in this pass, for
// the structural reason already recorded above: this target carries its
// own per-app EngineProtocol/StubConsoleEngine types, and the Shared
// adaptation pass (INTEGRATION-NOTES resolution (f)) has not landed.
// Adding Shared/Engine/NativeEngine.swift now would duplicate those
// types in one module and break the build. When the adaptation lands:
//   1. add a SwiftPM target:
//        .target(name: "CCascadeConsole", path: "../../NativeEngine/swiftpm")
//      wrapping module.modulemap + cc_facade.h (see enginework),
//   2. compile cc_interpreter.cpp + ccgeom_mc.cpp into a static library
//      in CI alongside CascadeKit and link both,
//   3. define CASCADE_NATIVE_ENGINE for the app target and call
//      EngineFactory.makeEngine() from AppState.
