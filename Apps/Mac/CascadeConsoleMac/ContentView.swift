import SwiftUI

/// Main window layout:
///   sidebar (objects) | viewport (top) over console (bottom), glass toolbar.
/// File actions arrive via `AppState.pendingFileAction` (set by the menu
/// bar) and are performed here, where panel presentation belongs.
struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(SettingsKey.appearance) private var appearance = "system"

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                VSplitView {
                    ViewportPlaceholderView(objects: state.objects.map { $0.snapshot },
                                            fitAllToken: state.fitAllToken)
                        .frame(minHeight: 220)
                    ConsoleView()
                        .frame(minHeight: 170)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .preferredColorScheme(colorScheme)
        .onChange(of: state.pendingFileAction) { _, action in
            guard let action else { return }
            state.pendingFileAction = nil
            perform(action)
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // MARK: Toolbar (Liquid Glass on macOS 26, material fallback below)

    private var toolbar: some View {
        HStack(spacing: 12) {
            GlassToolbarGroup {
                toolbarButton("Welcome example", systemImage: "sparkles") {
                    state.runWelcomeScript()
                }
                toolbarButton("Fit view", systemImage: "arrow.up.left.and.arrow.down.right") {
                    state.requestFitAll()
                }
                toolbarButton("Clear view", systemImage: "eye.slash") {
                    state.requestClearView()
                }
            }
            Spacer()
            GlassToolbarGroup {
                toolbarButton("Open script…", systemImage: "doc.badge.plus") {
                    perform(.openScript)
                }
                toolbarButton("Import…", systemImage: "square.and.arrow.down") {
                    perform(.importModel)
                }
                toolbarButton("Export…", systemImage: "square.and.arrow.up") {
                    perform(.exportModel)
                }
            }
        }
        .padding(10)
    }

    private func toolbarButton(_ title: String,
                               systemImage: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .glassButton()
        .help(title)
    }

    // MARK: File actions

    private func perform(_ action: FileAction) {
        switch action {
        case .openScript:
            guard let url = FileService.pickOpenFile(
                title: "Open a command script",
                allowedTypes: FileService.scriptTypes) else { return }
            do {
                let text = try FileService.readText(at: url)
                state.runScript(text, sourceName: url.lastPathComponent)
            } catch let error as FileServiceError {
                state.appendLog(level: .error, text: error.description, code: "CC-E200")
            } catch {
                state.appendLog(level: .error,
                                text: "Could not open that script.",
                                code: "CC-E200")
            }

        case .saveScript:
            guard let url = FileService.pickSaveFile(
                title: "Save the session as a script",
                defaultName: "session.ccs",
                allowedTypes: FileService.scriptTypes) else { return }
            let text = state.history.joined(separator: "\n") + "\n"
            do {
                try FileService.writeText(text, to: url)
                state.appendLog(level: .result,
                                text: "Saved the session script to \"\(url.lastPathComponent)\".")
            } catch let error as FileServiceError {
                state.appendLog(level: .error, text: error.description, code: "CC-E201")
            } catch {
                state.appendLog(level: .error,
                                text: "Could not save that script.",
                                code: "CC-E201")
            }

        case .importModel:
            guard let url = FileService.pickOpenFile(
                title: "Import a model (STEP, IGES, STL, BREP)",
                allowedTypes: FileService.modelTypes) else { return }
            // The real import runs in the core façade (Agent 2): the engine
            // gets an `import <path>` command so all imports share one path.
            state.runCommand("import \"\(url.path)\"")

        case .exportModel:
            guard let url = FileService.pickSaveFile(
                title: "Export the model",
                defaultName: "model.step",
                allowedTypes: FileService.exportTypes) else { return }
            state.runCommand("export \"\(url.path)\"")
        }
    }
}
