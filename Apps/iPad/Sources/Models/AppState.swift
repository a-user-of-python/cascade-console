import Foundation
import SwiftUI

/// Central observable state: console log, command history, scene
/// objects, selection, and the loaded script buffer. Owns the engine
/// and viewer bridge references (injected at app launch).
/// All mutation happens from SwiftUI (main thread) or from the
/// explicitly @MainActor task in `run(command:)`.
final class AppState: ObservableObject {

    @Published var log: [ConsoleLogEntry] = []
    @Published var objects: [SceneObjectItem] = []
    @Published var selectedObjectID: UUID?
    @Published var scriptBuffer: String = ""
    @Published var currentFileName: String = "untitled.cascade"
    @Published var isRunning: Bool = false

    let engine: CascadeEngine
    let viewer: PlaceholderViewerBridge
    let fileStore: FileStore

    private var history: [String] = []
    private var historyIndex: Int?

    init(engine: CascadeEngine,
         viewer: PlaceholderViewerBridge,
         fileStore: FileStore) {
        self.engine = engine
        self.viewer = viewer
        self.fileStore = fileStore

        viewer.onObjectPicked = { [weak self] picked in
            guard let self else { return }
            if let match = self.objects.first(where: { $0.id.uuidString == picked }) {
                self.selectedObjectID = match.id
            }
        }

        appendLog(.info, "Cascade Console ready. Type 'help' and press Return.")
    }

    // MARK: - Console

    func appendLog(_ kind: ConsoleLogEntry.Kind, _ text: String) {
        guard !text.isEmpty else { return }
        log.append(ConsoleLogEntry(kind: kind, text: text))
        // Keep the log bounded so a long session cannot grow forever.
        if log.count > 2000 {
            log.removeFirst(log.count - 2000)
        }
    }

    func clearLog() {
        log.removeAll()
    }

    // MARK: - History

    func historyPrevious(current: String) -> String {
        guard !history.isEmpty else { return current }
        if let index = historyIndex {
            historyIndex = max(0, index - 1)
        } else {
            historyIndex = history.count - 1
        }
        if let index = historyIndex, history.indices.contains(index) {
            return history[index]
        }
        return current
    }

    func historyNext(current: String) -> String {
        guard let index = historyIndex else { return current }
        let next = index + 1
        if next >= history.count {
            historyIndex = nil
            return ""
        }
        historyIndex = next
        return history[next]
    }

    // MARK: - Running commands

    func run(command raw: String) {
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        history.append(command)
        historyIndex = nil
        appendLog(.input, "> \(command)")

        let verb = command.split(separator: " ").first.map {
            String($0).lowercased()
        } ?? ""

        if verb == "clear" {
            clearLog()
            return
        }
        if verb == "load" {
            loadScriptFromDocuments(command: command)
            return
        }

        isRunning = true
        Task { @MainActor in
            let result = await engine.execute(command: command)
            apply(result)
            isRunning = false
        }
    }

    func runScript(_ script: String) {
        let lines = script.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            run(command: trimmed)
        }
    }

    private func apply(_ result: CommandResult) {
        if result.isError {
            appendLog(.error, result.output)
        } else {
            appendLog(.output, result.output)
        }
        // Shared CommandResult carries session names only; in the
        // Layer-2 design the session name IS the shape handle (shapeID).
        for name in result.producedNames {
            let item = SceneObjectItem(shapeID: name, name: name)
            objects.append(item)
            viewer.displayObject(id: item.id, name: item.name)
            selectedObjectID = item.id
        }
    }

    // MARK: - Objects

    func toggleVisibility(_ item: SceneObjectItem) {
        guard let index = objects.firstIndex(where: { $0.id == item.id })
        else { return }
        objects[index].isVisible.toggle()
        if objects[index].isVisible {
            viewer.displayObject(id: item.id, name: item.name)
        } else {
            viewer.removeObject(id: item.id)
        }
    }

    func removeObject(_ item: SceneObjectItem) {
        objects.removeAll { $0.id == item.id }
        viewer.removeObject(id: item.id)
        if selectedObjectID == item.id {
            selectedObjectID = nil
        }
    }

    func clearScene() {
        objects.removeAll()
        selectedObjectID = nil
        viewer.clearScene()
        appendLog(.info, "Scene cleared (console-side list only; core objects are cleared by the core's own clear command).")
    }

    // MARK: - Files (via FileStore, picker-free)

    func loadScriptFromDocuments(command: String) {
        let parts = command.split(separator: " ", maxSplits: 1)
        guard parts.count > 1 else {
            appendLog(.error, "Usage: load <file name in Documents>")
            return
        }
        let name = String(parts[1])
        fileStore.refresh()
        guard let item = fileStore.items.first(where: { $0.name == name })
        else {
            appendLog(.error, "No file named '\(name)' in Documents. Open the Files tab to see what is there.")
            return
        }
        switch fileStore.readText(item) {
        case .success(let text):
            scriptBuffer = text
            currentFileName = item.name
            appendLog(.info, "Loaded \(item.name) into the script buffer. Use Run Script to execute it.")
        case .failure(let error):
            appendLog(.error, "Could not read \(item.name): \(error.localizedDescription)")
        }
    }

    func saveBuffer() {
        switch fileStore.writeText(scriptBuffer, fileName: currentFileName) {
        case .success(let url):
            appendLog(.info, "Saved \(url.lastPathComponent) to Documents.")
        case .failure(let error):
            appendLog(.error, "Save failed: \(error.localizedDescription)")
        }
    }
}
