import SwiftUI

/// Cascade Console — macOS entry point.
///
/// First-launch guarantees kept deliberately simple:
///  * state starts empty except for three welcome log lines,
///  * no file is read and no panel is shown at launch,
///  * there are no force-unwraps or fatal paths in any app-owned file,
/// so a clean first launch cannot crash on missing data.
@main
struct CascadeConsoleMacApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // File menu: panels are performed by ContentView via
            // `pendingFileAction` (menu commands only set the request).
            CommandGroup(after: .newItem) {
                Button("Open Script…") {
                    state.pendingFileAction = .openScript
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Save Session Script…") {
                    state.pendingFileAction = .saveScript
                }
                .keyboardShortcut("s", modifiers: [.command])

                Divider()

                Button("Import Model…") {
                    state.pendingFileAction = .importModel
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Export Model…") {
                    state.pendingFileAction = .exportModel
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            // Console menu: driving the console from the keyboard anywhere.
            CommandMenu("Console") {
                Button("Run Welcome Example") {
                    state.runWelcomeScript()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Clear Log") {
                    state.clearLog()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button("Fit View to Objects") {
                    state.requestFitAll()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Clear View") {
                    state.requestClearView()
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}
