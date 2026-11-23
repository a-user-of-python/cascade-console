import SwiftUI

/// App entry point. Builds the object graph once, seeds starter files
/// on first launch, and applies the appearance setting. No force
/// unwraps and no throwing calls on any launch path.
///
/// ENGINE (v0.2): EngineFactory.makeEngine() is the single switch
/// point — NativeEngine (OCCT Layer-2) when the build defines
/// CASCADE_NATIVE_ENGINE and links CascadeKit + libCascadeConsoleEngine
/// (see .github/workflows/build-ipa.yml), the honest StubEngine
/// otherwise.
/// VIEWER (v0.2): the real CascadeRenderer (Shared/Viewer) is created
/// here and fed by AppState's viewer feed; it is nil only on a device
/// with no Metal device, which the viewport reports honestly.
@main
struct CascadeConsoleApp: App {
    @StateObject private var state: AppState
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue

    init() {
        let fileStore = FileStore()
        let viewer = CascadeRenderer()
        let appState = AppState(
            engine: EngineFactory.makeEngine(),
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
