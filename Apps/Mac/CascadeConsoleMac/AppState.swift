import Foundation
import Combine

/// All mutable app state for the macOS window. Main-actor isolated; views
/// observe it through `@EnvironmentObject`. No force-unwraps anywhere in
/// this file — every lookup is guarded and every failure becomes a log line.
@MainActor
final class AppState: ObservableObject {

    // MARK: Published state

    @Published var objects: [SceneObjectItem] = []
    @Published var log: [LogEntry] = []
    @Published var input: String = ""
    @Published var selectedObjectID: UUID?
    /// Incremented (new UUID) whenever the viewer should fit everything.
    @Published var fitAllToken = UUID()
    /// Set by menu-bar commands; observed and cleared by ContentView, which
    /// owns the actual panel presentation.
    @Published var pendingFileAction: FileAction?

    // MARK: Command history

    private(set) var history: [String] = []
    /// nil = not browsing history; otherwise the index being shown.
    private var historyIndex: Int?

    // MARK: Collaborators

    /// Swappable so Agent 2's real engine replaces the stub in one line
    /// (in the app entry point) without touching any view code.
    var engine: ConsoleEngine
    let viewer: ViewerBridge

    init(engine: ConsoleEngine = StubConsoleEngine(),
         viewer: ViewerBridge = PlaceholderViewerBridge()) {
        self.engine = engine
        self.viewer = viewer
        for line in WelcomeScript.welcomeLines {
            appendLog(level: .info, text: line)
        }
    }

    // MARK: - Command entry

    /// Runs the current input line. Bound to Return in the console field.
    func submitInput() {
        let raw = input
        input = ""
        runCommand(raw)
    }

    /// Runs one command line: records history, handles the app-level
    /// commands (clear / view), delegates everything else to the engine,
    /// and mirrors the engine's scene changes into the sidebar + viewer.
    func runCommand(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        if history.last != line {
            history.append(line)
        }
        historyIndex = nil

        appendLog(level: .info, text: "> " + line)

        let lowered = line.lowercased()
        if lowered == "clear" {
            log.removeAll()
            return
        }
        if lowered == "view fit" {
            requestFitAll()
            appendLog(level: .result, text: "View fitted to the visible objects.")
            return
        }
        if lowered == "view clear" {
            viewer.clearScene()
            appendLog(level: .result, text: "View cleared. The scene itself is unchanged.")
            return
        }

        let result = engine.execute(line, objects: objects)
        for message in result.messages {
            appendLog(level: message.level, text: message.text, code: message.code)
        }
        applySceneChanges(upserted: result.upserted, removedNames: result.removedNames)
    }

    /// Runs a multi-line script (from a file or the welcome example).
    /// Comment lines ("#...") and blank lines are skipped.
    func runScript(_ text: String, sourceName: String) {
        appendLog(level: .info, text: "Running script \"\(sourceName)\"…")
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            runCommand(line)
        }
        appendLog(level: .info, text: "Script \"\(sourceName)\" finished.")
    }

    func runWelcomeScript() {
        runScript(WelcomeScript.text, sourceName: "Welcome example")
    }

    // MARK: - History navigation (Up / Down in the console field)

    func historyBack() {
        guard !history.isEmpty else { return }
        if let index = historyIndex {
            historyIndex = max(0, index - 1)
        } else {
            historyIndex = history.count - 1
        }
        if let index = historyIndex, history.indices.contains(index) {
            input = history[index]
        }
    }

    func historyForward() {
        guard let index = historyIndex else { return }
        let next = index + 1
        if next >= history.count {
            historyIndex = nil
            input = ""
        } else {
            historyIndex = next
            input = history[next]
        }
    }

    // MARK: - Autocomplete

    /// Command completions for the current input, from the engine's catalog.
    var suggestions: [String] {
        let text = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return [] }
        return engine.knownCommands
            .filter { $0.hasPrefix(text) && $0 != text }
            .sorted()
            .prefix(6)
            .map { $0 }
    }

    func applySuggestion(_ suggestion: String) {
        input = suggestion
    }

    // MARK: - Sidebar actions

    var selectedObject: SceneObjectItem? {
        guard let id = selectedObjectID else { return nil }
        return objects.first(where: { $0.id == id })
    }

    func toggleVisibility(_ item: SceneObjectItem) {
        guard let index = objects.firstIndex(where: { $0.id == item.id }) else { return }
        objects[index].isVisible.toggle()
        pushSceneToViewer()
    }

    func setColor(_ item: SceneObjectItem, hex: String) {
        guard let index = objects.firstIndex(where: { $0.id == item.id }) else { return }
        objects[index].colorHex = hex
        pushSceneToViewer()
    }

    func deleteSelected() {
        guard let item = selectedObject else { return }
        objects.removeAll(where: { $0.id == item.id })
        selectedObjectID = nil
        appendLog(level: .result, text: "Deleted \"\(item.name)\".")
        pushSceneToViewer()
    }

    // MARK: - Viewer actions

    func requestFitAll() {
        viewer.fitAll()
        fitAllToken = UUID()
    }

    func requestClearView() {
        viewer.clearScene()
    }

    // MARK: - Log

    func appendLog(level: LogLevel, text: String, code: String? = nil) {
        log.append(LogEntry(level: level, text: text, code: code))
        // Keep the log bounded so a long session stays responsive.
        if log.count > 2000 {
            log.removeFirst(log.count - 2000)
        }
    }

    func clearLog() {
        log.removeAll()
    }

    // MARK: - Private helpers

    private func applySceneChanges(upserted: [SceneObjectItem], removedNames: [String]) {
        var changed = false
        for name in removedNames {
            let before = objects.count
            objects.removeAll(where: { $0.name == name })
            if objects.count != before { changed = true }
        }
        for item in upserted {
            if let index = objects.firstIndex(where: { $0.name == item.name }) {
                // Preserve the UI identity of an existing object on replace.
                let replacement = SceneObjectItem(id: objects[index].id,
                                              name: item.name,
                                              kind: item.kind,
                                              isVisible: item.isVisible,
                                              colorHex: item.colorHex)
                objects[index] = replacement
            } else {
                objects.append(item)
            }
            changed = true
        }
        if changed {
            pushSceneToViewer()
        }
    }

    private func pushSceneToViewer() {
        viewer.render(objects: objects.map { $0.snapshot })
    }
}
