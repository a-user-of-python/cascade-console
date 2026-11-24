import Foundation

// MARK: - Unified engine protocol (INTEGRATION — canonical for BOTH apps)
//
// Merges the Mac scaffold's `ConsoleEngine` (synchronous, objects passed
// in, EngineResult out) and the iPad scaffold's `CascadeEngineFacing`
// (async, CommandResult out). The unified protocol is the iPad async
// form, because the real Layer-2 session (Core/facade/cc_facade.h) runs
// on a serial console queue and must never block the main thread:
//   execute(command:) -> cc_execute() on the console queue.
// `knownCommands` comes from Shared/Resources/catalog.json (the 251-
// command catalog) so autocomplete and `help` are complete by
// construction. Scene mirroring is the AppState's job, driven by
// CommandResult.producedNames + cc_object_* queries — the engine does
// NOT receive the UI object list (the Mac form's `objects:` parameter
// is dropped; duplicate-name errors are the core's E1006, not the UI's).

public protocol CascadeEngine: AnyObject {
    /// Command names from catalog.json, for autocomplete and `help`.
    var knownCommands: [String] { get }
    func execute(command: String) async -> CommandResult
    func executeScript(_ script: String) async -> [CommandResult]
}

public extension CascadeEngine {
    func executeScript(_ script: String) async -> [CommandResult] {
        var results: [CommandResult] = []
        for rawLine in script.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            results.append(await execute(command: line))
        }
        return results
    }
}

/// Placeholder engine used until the OCCT core is linked. It answers
/// `help`, `clear` (handled by the console itself), and `echo` locally,
/// and is honest about everything else: no fake geometry, ever.
/// Commands whose OCCT toolkit is not in the current build must return
/// the NOT_IMPLEMENTED pair (E5002 / CC-SYS-000) — see
/// docs/ERROR-CODES.md and COMMAND-COVERAGE.md.
public final class StubEngine: CascadeEngine {
    public init() {}
    public var knownCommands: [String] { ["help", "echo", "clear"] }

    public func execute(command: String) async -> CommandResult {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .ok("") }
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        let verb = parts.first.map { String($0).lowercased() } ?? ""
        let rest = parts.count > 1 ? String(parts[1]) : ""
        switch verb {
        case "help":
            return .ok(StubEngine.helpText)
        case "echo":
            return .ok(rest)
        default:
            return .error(
                "Open CASCADE core is not linked in this build yet, " +
                "so '\(verb)' cannot run. Commands available now: help, echo, clear.",
                code: "E5002 / CC-SYS-000")
        }
    }

    public static let helpText = """
    Cascade Console commands (console-local ones work today):
      help              show this text
      echo <text>       print text to the console
      clear             clear the console log
      history           show the numbered command log
    All modelling commands (box, cylinder, fuse, cut, fillet, view, \
    export-step, ...) are provided by the Open CASCADE core once it is \
    linked — see the user guide and docs/catalog/ for the full catalogue.
    """
}

// MARK: - View-data feed (v0.2)
//
// The bridge between a geometry engine and the Metal viewer. An engine
// that can tessellate conforms to this; AppState, after any successful
// command, pulls the full scene through it and loads the result into
// the ViewerBridge (CascadeRenderer) via the CCM1 adapter in
// Shared/Viewer/Swift/EngineMeshAdapter.swift. StubEngine deliberately
// does NOT conform: with no core linked there is nothing to render,
// and the viewer honestly stays empty.

/// One tessellated object as returned by the native session's
/// cc_view_data: positions only (the C API carries no normals or face
/// groups; the CCM1 adapter derives flat normals and a single face
/// group — see EngineMeshAdapter).
public struct EngineViewObject: Equatable {
    /// One census face's slice of the tessellation index buffer.
    /// faceIndex is the 0-based census index — the number @face <n>
    /// references — carried from the backend's own face enumeration
    /// (ccgeom_face_ranges), never re-derived in the viewer.
    public struct FaceRange: Equatable {
        public var faceIndex: Int32
        public var indexStart: Int32
        public var indexCount: Int32
        public init(faceIndex: Int32, indexStart: Int32, indexCount: Int32) {
            self.faceIndex = faceIndex
            self.indexStart = indexStart
            self.indexCount = indexCount
        }
    }
    /// One census edge (v0.2.4): the backend's 0-based census index —
    /// the number `fillet/chamfer ... edges i,j,...` accepts — plus
    /// its endpoints, from ccgeom_edge_list (the backend's own edge
    /// enumeration, never re-derived in the viewer).
    public struct Edge: Equatable {
        public var edgeIndex: Int32
        public var start: [Double]   // xyz
        public var end: [Double]     // xyz
        public init(edgeIndex: Int32, start: [Double], end: [Double]) {
            self.edgeIndex = edgeIndex
            self.start = start
            self.end = end
        }
    }
    public var name: String
    public var vertices: [Float]   // 3 * vertexCount, xyz positions
    public var indices: [Int32]    // 3 * triangleCount
    public var volume: Double
    public var bbox: [Double]      // minX, minY, minZ, maxX, maxY, maxZ
    public var faceRanges: [FaceRange]
    public var edges: [Edge]
    public init(name: String, vertices: [Float], indices: [Int32],
                volume: Double, bbox: [Double], faceRanges: [FaceRange] = [],
                edges: [Edge] = []) {
        self.name = name
        self.vertices = vertices
        self.indices = indices
        self.volume = volume
        self.bbox = bbox
        self.faceRanges = faceRanges
        self.edges = edges
    }
}

/// Result of a view-data pull: the tessellated objects, plus the
/// engine's own error message when the pull failed. v0.2 returned a
/// bare array and NativeEngine silently mapped every cc_view_data
/// failure to [], so a broken viewer feed looked exactly like an
/// empty scene in the console. Failures are now data AppState logs
/// ("Viewer feed failed: ...") instead of silence.
public struct EngineViewDataResult {
    public var objects: [EngineViewObject]
    public var errorMessage: String?
    public init(objects: [EngineViewObject], errorMessage: String? = nil) {
        self.objects = objects
        self.errorMessage = errorMessage
    }
}

public protocol EngineViewDataProviding: AnyObject {
    /// Session object names, in session order.
    func objectNames() async -> [String]
    /// Session profile names (v0.3.0), qualified ("profile:prof").
    /// Profiles are 2D and never appear in view data, but the part
    /// tree lists them and the step layer needs their names for
    /// auto-naming parity with the engine.
    func profileNames() async -> [String]
    /// Tessellation for one object, or every object when `name` is nil.
    /// A failed pull returns empty `objects` WITH `errorMessage` set —
    /// never a silent empty result.
    func viewData(name: String?) async -> EngineViewDataResult
}

public extension EngineViewDataProviding {
    func profileNames() async -> [String] { [] }
}
