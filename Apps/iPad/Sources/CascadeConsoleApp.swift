import SwiftUI

/// App entry point. Builds the object graph once, seeds starter files
/// on first launch, and applies the appearance setting. No force
/// unwraps and no throwing calls on any launch path.
///
/// LINKING THE REAL CORE (Agent 2): replace `StubEngine()` below with
/// the OCCT-backed implementation of `CascadeEngineFacing`.
/// LINKING THE REAL VIEWER (Agent 5): `PlaceholderViewerBridge` stays
/// as the bridge type if Agent 5 conforms to `CascadeViewerBridging`
/// behind it, or swap the type here and in AppState together.
@main
struct CascadeConsoleApp: App {
    @StateObject private var state: AppState
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue

    init() {
        let fileStore = FileStore()
        let viewer = PlaceholderViewerBridge()
        let appState = AppState(
            engine: StubEngine(),
            viewer: viewer,
            fileStore: fileStore)
        _state = StateObject(wrappedValue: appState)

        // First-launch seeding: starter files in Documents, welcome
        // script in the buffer. All best-effort (FileStore swallows
        // errors into lastError); a failure here must never block launch.
        let seeded = UserDefaults.standard.bool(forKey: SettingsKeys.welcomeSeeded)
        if !seeded {
            fileStore.seedIfMissing(
                fileName: ExampleScript.welcomeFileName,
                contents: ExampleScript.welcome)
            fileStore.seedIfMissing(
                fileName: ExampleScript.sampleFileName,
                contents: ExampleScript.sampleProject)
            UserDefaults.standard.set(true, forKey: SettingsKeys.welcomeSeeded)
        }
        appState.scriptBuffer = ExampleScript.welcome
        appState.currentFileName = ExampleScript.welcomeFileName
        fileStore.refresh()
    }

    private var appearance: AppearanceChoice {
        AppearanceChoice(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
