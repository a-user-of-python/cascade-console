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

    // MARK: - Project state (v0.3.0)
    //
    // The UI-first model: `project` holds the parametric step list
    // (history), the folder tree and the viewer snapshot. Steps are
    // executed against `engine`; editing or deleting a step replays
    // the list into a FRESH engine and swaps it in only when the
    // whole replay succeeds (see replayProject). `profiles` mirrors
    // the session's profile names (qualified) for the part tree;
    // `objectStats` caches the last view-data pull per object for
    // the Properties panel.
    @Published var project = ProjectFile()
    @Published var currentProjectName: String = "untitled.cascadeproj"
    @Published var profiles: [String] = []
    @Published var objectStats: [String: EngineViewObject] = [:]
    @Published var selectedStepID: UUID?
    /// Set when a replay fails; the History panel shows it and the
    /// failing step stays selected. Cleared by the next success.
    @Published var lastReplayError: String?
    /// Number of objects actually loaded in the 3D viewer, shown in
    /// the viewport header. Published and updated AFTER the meshes
    /// are loaded in refreshScene: v0.2.2's header read the
    /// renderer's object list directly from the view body, but the
    /// only published changes in refreshScene (the sidebar sync)
    /// happen BEFORE loadMesh, so the header was evaluated while
    /// the renderer was still empty and never re-evaluated — it
    /// showed "0 object(s)" over a drawn scene (FIXLOG v0.2.3).
    @Published private(set) var viewerObjectCount: Int = 0

    /// The live engine. `private(set)` because a successful project
    /// replay REPLACES it with the fresh session it replayed into
    /// (v0.3.0) — the old session is never mutated by an edit that
    /// might fail halfway.
    private(set) var engine: CascadeEngine
    /// The real Metal viewer (Shared/Viewer). Optional only because a
    /// device with no Metal device cannot create one; on any such
    /// device the viewport shows an honest message instead of a crash
    /// (the app entry point passes CascadeRenderer() straight through).
    let renderer: CascadeRenderer?
    var viewer: ViewerBridge? { renderer }
    let fileStore: FileStore

    private var history: [String] = []
    private var historyIndex: Int?

    init(engine: CascadeEngine,
         viewer: CascadeRenderer?,
         fileStore: FileStore) {
        self.engine = engine
        self.renderer = viewer
        self.fileStore = fileStore

        renderer?.delegate = self

        appendLog(.info, "Cascade Console ready. Build from the command panel on the right, or open the console tab and type 'help'.")
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
        if verb == "view" {
            // `view` lines are app-layer commands and NEVER reach the
            // engine (v0.2.1 fix). In v0.2 the parser rejected
            // `view <name>` and the line fell through to the engine,
            // whose own `view` is the host-debug `view <path.json>`
            // form — it treated the object name as a file path and
            // failed writing to the app sandbox's working directory
            // ("Could not write view data to 'test'.").
            handleViewCommand(command)
            return
        }

        // Export commands: the engine writes to the path it is given,
        // and on device a bare relative file name resolves against
        // the process working directory — not writable, and not the
        // Documents folder the user can browse (the v0.2
        // `export-stl test test.stl` failure). The app layer owns
        // device file paths: rewrite a bare name into Documents.
        let routed = (verb == "export" || verb == "export-step" || verb == "export-stl")
            ? routeExportToDocuments(command)
            : (line: command, rewroteToDocuments: false)

        isRunning = true
        Task { @MainActor in
            let result = await engine.execute(command: routed.line)
            if routed.rewroteToDocuments && !result.isError {
                // Name the saved location the way the user can find
                // it: Documents/... instead of the sandbox path.
                let docsPrefix = fileStore.documentsURL.path + "/"
                let display = result.output.replacingOccurrences(
                    of: docsPrefix, with: "Documents/")
                apply(result, displayOutput: display)
            } else {
                apply(result)
            }
            if !result.isError {
                await refreshScene(fit: false)
            }
            isRunning = false
        }
    }

    // MARK: - View commands (app layer)

    /// Handles every `view ...` line in the app layer:
    /// (a) ViewCommandParser subcommands (fit / standard views /
    ///     display modes / labels / section / ...) go to the renderer;
    /// (b) `view <name>` / `view <name> fit` for an existing session
    ///     object selects it and refreshes the scene;
    /// (c) `view <name>` for a nonexistent name is a clear console
    ///     error, not an engine error;
    /// (d) bare `view` shows everything;
    /// (e) anything else is a console usage error. The engine's
    ///     host-debug `view <path.json>` form stays available to the
    ///     host CLI/tests only — the app never forwards `view` lines.
    private func handleViewCommand(_ command: String) {
        if case .success(let viewCommand) = ViewCommandParser.parse(command) {
            if let renderer {
                renderer.apply(viewCommand)
                appendLog(.info, "view: applied to the 3D viewer.")
            } else {
                appendLog(.error, "view: the 3D view is unavailable on this device (no Metal device).")
            }
            return
        }
        let tokens = command.split(separator: " ").map(String.init)
        if tokens.count == 1 {
            Task { @MainActor in await refreshScene(fit: true) }
            appendLog(.info, "Showing all objects.")
            return
        }
        let isNameForm = tokens.count == 2
            || (tokens.count == 3 && tokens[2].lowercased() == "fit")
        if isNameForm {
            let name = tokens[1]
            Task { @MainActor in
                let names: [String]
                if let provider = engine as? EngineViewDataProviding {
                    names = await provider.objectNames()
                } else {
                    names = objects.map { $0.shapeID }
                }
                guard names.contains(name) else {
                    appendLog(.error, "view: no object named '\(name)'.")
                    return
                }
                await refreshScene(fit: true)
                if let item = objects.first(where: { $0.shapeID == name }) {
                    selectedObjectID = item.id
                }
                appendLog(.info, "Showing '\(name)'.")
            }
            return
        }
        appendLog(.error, "view: unrecognized view command. Try 'view', 'view <name>', 'view fit', 'view iso', 'view rotate 45 30', 'view labels faces on', 'view labels edges on'.")
    }

    // MARK: - Export path routing (app layer)

    /// Rewrites the target of an export command into the app's
    /// Documents folder when — and only when — the user gave a bare
    /// file name (no directory component). A path with any directory
    /// component, relative or absolute, is the user's explicit choice
    /// and passes through unchanged. Grammar (engine's own):
    /// `export-step <shape> <file>`, `export-stl <shape> <file>`,
    /// `export step|stl <path> [name]` — the path is token 2 in all
    /// three forms. The engine's multi-target `_<name>` insertion
    /// operates on the rewritten absolute path, so per-object files
    /// still land in Documents.
    private func routeExportToDocuments(_ command: String)
        -> (line: String, rewroteToDocuments: Bool) {
        var tokens = command.split(separator: " ").map(String.init)
        guard tokens.count > 2 else { return (command, false) }
        if tokens[0].lowercased() == "export" {
            let kind = tokens[1].lowercased()
            guard kind == "step" || kind == "stl" else { return (command, false) }
        }
        let target = tokens[2]
        guard !target.hasPrefix("/"), !target.contains("/") else {
            return (command, false)
        }
        tokens[2] = fileStore.documentsURL.appendingPathComponent(target).path
        return (tokens.joined(separator: " "), true)
    }

    func runScript(_ script: String) {
        let lines = script.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            run(command: trimmed)
        }
    }

    private func apply(_ result: CommandResult, displayOutput: String? = nil) {
        if result.isError {
            appendLog(.error, result.output)
        } else {
            appendLog(.output, displayOutput ?? result.output)
        }
        // Shared CommandResult carries session names only; in the
        // Layer-2 design the session name IS the shape handle (shapeID).
        for name in result.producedNames where !objects.contains(where: { $0.shapeID == name }) {
            let item = SceneObjectItem(shapeID: name, name: name)
            objects.append(item)
            selectedObjectID = item.id
        }
    }

    // MARK: - Viewer feed (v0.2)
    //
    // After every successful command, pull the session's tessellation
    // from the engine (cc_view_data via EngineViewDataProviding),
    // convert it through the CCM1 adapter, and load it into the real
    // Metal renderer through the normative ViewerBridge. The object
    // list is re-synced from the session at the same time, so deletes,
    // renames and undo are all reflected without the console guessing.
    // Engines that cannot tessellate (StubEngine) do not conform, and
    // the viewer honestly stays empty.

    @MainActor
    func refreshScene(fit: Bool) async {
        guard let provider = engine as? EngineViewDataProviding,
              let renderer else { return }
        let names = await provider.objectNames()
        profiles = await provider.profileNames()
        let feed = await provider.viewData(name: nil)
        if let message = feed.errorMessage {
            appendLog(.error, "Viewer feed failed: \(message)")
        } else {
            // Cache per-object stats for the Properties panel.
            objectStats = Dictionary(
                uniqueKeysWithValues: feed.objects.map { ($0.name, $0) })
        }
        let viewObjects = feed.objects
        if !names.isEmpty && viewObjects.isEmpty && feed.errorMessage == nil {
            appendLog(.error, "Viewer feed: the session has \(names.count) object(s) but the engine returned no view data — the 3D view will be empty.")
        }

        let nameSet = Set(names)
        objects.removeAll { !nameSet.contains($0.shapeID) }
        for name in names where !objects.contains(where: { $0.shapeID == name }) {
            objects.append(SceneObjectItem(shapeID: name, name: name))
        }
        if let selectedObjectID,
           !objects.contains(where: { $0.id == selectedObjectID }) {
            self.selectedObjectID = nil
        }

        do {
            let meshes = try EngineMeshAdapter.meshObjects(from: viewObjects)
            let liveIDs = Set(meshes.map { $0.id })
            for stale in renderer.objectIDs where !liveIDs.contains(stale) {
                renderer.removeObject(id: stale)
            }
            for mesh in meshes {
                let visible = objects.first(where: { $0.shapeID == mesh.id })?.isVisible ?? true
                var props = ObjectDisplayProps()
                props.isVisible = visible
                renderer.loadMesh(mesh, props: props)
            }
            if !viewObjects.isEmpty && meshes.isEmpty {
                appendLog(.error, "Viewer feed: the engine returned \(viewObjects.count) object(s) with no triangles to render.")
            }
            if fit && !meshes.isEmpty {
                renderer.apply(.fit)
            }
        } catch {
            appendLog(.error, "Viewer feed failed: \(error)")
        }
        // Publish the header count only now that the renderer
        // actually holds the meshes (see viewerObjectCount).
        viewerObjectCount = renderer.objectIDs.count
    }

    // MARK: - Objects

    func toggleVisibility(_ item: SceneObjectItem) {
        guard let index = objects.firstIndex(where: { $0.id == item.id })
        else { return }
        objects[index].isVisible.toggle()
        renderer?.apply(.setObjectVisible(id: item.shapeID, objects[index].isVisible))
    }

    func removeObject(_ item: SceneObjectItem) {
        objects.removeAll { $0.id == item.id }
        renderer?.removeObject(id: item.shapeID)
        viewerObjectCount = renderer?.objectIDs.count ?? 0
        if selectedObjectID == item.id {
            selectedObjectID = nil
        }
    }

    func clearScene() {
        objects.removeAll()
        selectedObjectID = nil
        renderer?.clearScene()
        viewerObjectCount = renderer?.objectIDs.count ?? 0
        appendLog(.info, "Scene cleared (console-side list only; core objects are cleared by the core's own clear command).")
    }

    // MARK: - Steps + replay (v0.3.0)
    //
    // The project is the step list; the engine session is its
    // materialisation. Creating from the UI executes one step against
    // the live session. Editing or deleting a step replays the whole
    // list into a FRESH engine and adopts it only on full success —
    // a failed replay changes nothing and names the failing step.
    // Objects created by typing console commands live in the session
    // only: they are not steps, and the next replay rebuilds the
    // session from the step list alone (documented in FIXLOG).

    /// Every qualified name the step layer should treat as taken:
    /// the live session's objects + profiles.
    private func sessionNames() async -> [String] {
        guard let provider = engine as? EngineViewDataProviding else { return [] }
        let objs = await provider.objectNames()
        let profs = await provider.profileNames()
        return objs + profs
    }

    /// Create a step from the command panel and execute it against
    /// the live session. The assigned name is learned from the
    /// session diff afterwards — the engine's own record (including
    /// any suffix it applied) is the truth, the builder's prediction
    /// only the expectation.
    func addStepFromUI(command: String, params: [String: String], name: String) {
        var step = ModelStep(command: command, params: params, name: name)
        isRunning = true
        Task { @MainActor in
            defer { isRunning = false }
            let before = await sessionNames()
            let built = ReplayBuilder.build(steps: [step], initialNames: before)
            guard let b = built.first, let line = b.line else {
                appendLog(.error, built.first?.buildError
                    ?? "Could not build that step.")
                return
            }
            let result = await engine.execute(command: line)
            apply(result)
            if result.isError { return }
            let after = await sessionNames()
            let fresh = after.filter { !before.contains($0) }
            step.assignedName = fresh.first(where: {
                CascadeNames.directory(of: $0) == command
            }) ?? b.predictedName
            project.steps.append(step)
            selectedStepID = step.id
            lastReplayError = nil
            await refreshScene(fit: false)
        }
    }

    /// Edit a step's parameters/name, then rebuild by replay.
    func applyStepEdit(id: UUID, params: [String: String], name: String) {
        guard let idx = project.steps.firstIndex(where: { $0.id == id })
        else { return }
        var steps = project.steps
        steps[idx].params = params
        steps[idx].name = name
        replayProject(steps: steps, selectStepID: id)
    }

    /// Delete a step, then rebuild by replay.
    func deleteStep(id: UUID) {
        replayProject(steps: project.steps.filter { $0.id != id },
                      selectStepID: nil)
    }

    /// Replay `steps` into a fresh engine; adopt it (and the step
    /// list, with assigned names refreshed from the session diffs)
    /// only when every step succeeds. On failure the live engine and
    /// the project's step list are left exactly as they were, and
    /// `lastReplayError` names the failing step.
    func replayProject(steps: [ModelStep], selectStepID: UUID?) {
        isRunning = true
        Task { @MainActor in
            defer { isRunning = false }
            let scratch = EngineFactory.makeEngine()
            let built = ReplayBuilder.build(steps: steps)
            var newSteps = steps
            var knownNames: [String] = []
            func scratchNames() async -> [String] {
                guard let provider = scratch as? EngineViewDataProviding
                else { return [] }
                let objs = await provider.objectNames()
                let profs = await provider.profileNames()
                return objs + profs
            }
            for (i, b) in built.enumerated() {
                if let error = b.buildError {
                    lastReplayError = "Step \(i + 1) (\(b.step.displayTitle)): \(error) The model was left unchanged."
                    appendLog(.error, lastReplayError ?? error)
                    return
                }
                if b.step.isScript {
                    let results = await scratch.executeScript(
                        b.step.scriptText ?? "")
                    if let bad = results.first(where: { $0.isError }) {
                        lastReplayError = "Step \(i + 1) (imported script) failed: \(bad.output) The model was left unchanged."
                        appendLog(.error, lastReplayError ?? bad.output)
                        return
                    }
                    knownNames = await scratchNames()
                    continue
                }
                guard let line = b.line else {
                    lastReplayError = "Step \(i + 1) (\(b.step.displayTitle)) could not be built. The model was left unchanged."
                    appendLog(.error, lastReplayError ?? "Replay failed.")
                    return
                }
                let result = await scratch.execute(command: line)
                if result.isError {
                    lastReplayError = "Step \(i + 1) (\(b.step.displayTitle)) failed: \(result.output) The model was left unchanged."
                    appendLog(.error, lastReplayError ?? result.output)
                    return
                }
                let now = await scratchNames()
                let fresh = now.filter { !knownNames.contains($0) }
                newSteps[i].assignedName = fresh.first(where: {
                    CascadeNames.directory(of: $0) == b.step.command
                }) ?? b.predictedName
                knownNames = now
            }
            engine = scratch
            project.steps = newSteps
            selectedStepID = selectStepID
            lastReplayError = nil
            objects.removeAll()
            selectedObjectID = nil
            await refreshScene(fit: false)
            appendLog(.info, "History replayed: \(newSteps.count) step(s).")
        }
    }

    /// Start over: fresh session, empty project.
    func newProject() {
        engine = EngineFactory.makeEngine()
        project = ProjectFile()
        currentProjectName = "untitled.cascadeproj"
        selectedStepID = nil
        lastReplayError = nil
        objects.removeAll()
        selectedObjectID = nil
        Task { @MainActor in await refreshScene(fit: false) }
        appendLog(.info, "New project.")
    }

    // MARK: - Project files (v0.3.0)

    func saveProject() {
        captureViewerSnapshot()
        do {
            let data = try project.encoded()
            switch fileStore.writeText(String(decoding: data, as: UTF8.self),
                                       fileName: currentProjectName) {
            case .success(let url):
                appendLog(.info, "Saved project \(url.lastPathComponent) to Documents.")
            case .failure(let error):
                appendLog(.error, "Project save failed: \(error.localizedDescription)")
            }
        } catch {
            appendLog(.error, "Project save failed: \(error.localizedDescription)")
        }
    }

    func openProject(item: FileStore.FileItem) {
        switch fileStore.readText(item) {
        case .success(let text):
            do {
                let file = try ProjectFile.decoded(from: Data(text.utf8))
                loadProject(file, fileName: item.name)
            } catch {
                appendLog(.error, "Could not open \(item.name): \(error.localizedDescription)")
            }
        case .failure(let error):
            appendLog(.error, "Could not read \(item.name): \(error.localizedDescription)")
        }
    }

    /// Open a legacy .cascade script AS a project: the migration is
    /// one verbatim "Imported script" step (see ProjectFile).
    func importScriptAsProject(item: FileStore.FileItem) {
        switch fileStore.readText(item) {
        case .success(let text):
            let file = ProjectFile.migrateLegacyScript(text)
            let base = (item.name as NSString).deletingPathExtension
            loadProject(file, fileName: base + ".cascadeproj")
        case .failure(let error):
            appendLog(.error, "Could not read \(item.name): \(error.localizedDescription)")
        }
    }

    private func loadProject(_ file: ProjectFile, fileName: String) {
        currentProjectName = fileName
        project = file
        applyViewerSnapshot(file.viewer)
        replayProject(steps: file.steps, selectStepID: nil)
        appendLog(.info, "Opened project \(fileName) (\(file.steps.count) step(s)).")
    }

    // MARK: - Viewer snapshot (v0.3.0)

    func captureViewerSnapshot() {
        guard let renderer else { return }
        var snap = ViewerStateSnapshot()
        snap.grid = renderer.store.gridVisible
        snap.axes = renderer.store.axesVisible
        snap.faceLabels = renderer.faceLabelsEnabled
        snap.edgeLabels = renderer.edgeLabelsEnabled
        snap.displayMode = renderer.store.displayMode.rawValue
        snap.cameraAzimuthDegrees = Double(renderer.store.camera.azimuth) * 180 / .pi
        snap.cameraElevationDegrees = Double(renderer.store.camera.elevation) * 180 / .pi
        project.viewer = snap
    }

    func applyViewerSnapshot(_ snap: ViewerStateSnapshot) {
        guard let renderer else { return }
        renderer.apply(.setGridVisible(snap.grid))
        renderer.apply(.setAxesVisible(snap.axes))
        renderer.apply(.setFaceLabelsEnabled(snap.faceLabels))
        renderer.apply(.setEdgeLabelsEnabled(snap.edgeLabels))
        renderer.apply(.displayMode(
            DisplayMode(rawValue: snap.displayMode) ?? .shaded))
        if let az = snap.cameraAzimuthDegrees,
           let el = snap.cameraElevationDegrees {
            renderer.apply(.setCameraRotation(
                azimuthDegrees: Float(az), elevationDegrees: Float(el)))
        }
    }

    // MARK: - Part tree operations (v0.3.0)

    /// Selecting a tree entry selects the scene object and, when a
    /// step produced it, that step (so the right panel edits it).
    func selectTreeEntry(qualifiedName: String) {
        if let item = objects.first(where: { $0.shapeID == qualifiedName }) {
            selectedObjectID = item.id
        }
        if let step = project.steps.first(where: {
            $0.assignedName == qualifiedName
        }) {
            selectedStepID = step.id
        }
    }

    /// Deleting from the tree: a step-owned entry deletes its STEP
    /// (history is the source of truth; the replay rebuilds without
    /// it and honestly reports anything that depended on it). A
    /// console-created entry is deleted in the session directly.
    func deleteTreeEntry(qualifiedName: String) {
        project.objectFolders.removeValue(forKey: qualifiedName)
        if let step = project.steps.first(where: {
            $0.assignedName == qualifiedName
        }) {
            deleteStep(id: step.id)
        } else {
            run(command: "delete \(qualifiedName)")
        }
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

// MARK: - ViewerBridgeDelegate

extension AppState: ViewerBridgeDelegate {
    func viewerDidChangeCamera(_ viewer: ViewerBridge) {}

    func viewer(_ viewer: ViewerBridge, didPick result: PickResult?) {
        guard let result else { return }
        // MeshObject.id is the session shape name (== shapeID).
        if let match = objects.first(where: { $0.shapeID == result.objectID }) {
            selectedObjectID = match.id
        }
    }

    func viewer(_ viewer: ViewerBridge, measureDistanceChanged distance: Float?) {}
    func viewer(_ viewer: ViewerBridge, didWriteScreenshotTo path: String) {}
    func viewer(_ viewer: ViewerBridge, didFailWith message: String) {
        appendLog(.error, "Viewer: \(message)")
    }
}
