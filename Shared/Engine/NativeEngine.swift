import Foundation

// MARK: - NativeEngine (ENGINE agent, 2026-11-23)
//
// The OCCT-backed CascadeEngine: every command line goes to the native
// C++ Layer-2 session (Core/facade/cc_facade.h, implemented in
// NativeEngine/src/cc_interpreter.cpp over the cascade-port mc_*
// Layer-1 façade) on a serial console queue — the session is NOT
// thread-safe and geometry calls can take seconds, so nothing here ever
// runs on the main thread.
//
// Availability: this file imports the `CCascadeConsole` clang module
// (NativeEngine/bridge/module.modulemap, exposing cc_facade.h). When
// the native library is not linked into the app target, the import
// fails at BUILD time — so NativeEngine is compiled only in targets
// that link CascadeKit + the Layer-2 sources, and every other target
// keeps using StubEngine. `EngineFactory` below is the single switch
// point: it returns NativeEngine when the module is present in the
// build (the flag CASCADE_NATIVE_ENGINE is set by the project — see
// NativeEngine/README.md in enginework for the exact project change),
// otherwise the honest StubEngine. No fake geometry, ever: if the
// native engine is absent, commands still answer E5002.

#if CASCADE_NATIVE_ENGINE
import CCascadeConsole
#endif

#if CASCADE_NATIVE_ENGINE
public final class NativeEngine: CascadeEngine, EngineViewDataProviding {
    /// Serial queue owning the session (the "console queue" of
    /// cc_facade.h's threading contract).
    private let queue = DispatchQueue(label: "user.cascadeconsole.engine")
    // cc_facade.h forward-declares CCSession (incomplete struct), so
    // ClangImporter surfaces the handle as OpaquePointer.
    private var session: OpaquePointer?

    public init() {
        session = cc_session_create()
    }

    deinit {
        if let session { cc_session_destroy(session) }
    }

    public var knownCommands: [String] {
        // The interpreter's implemented set (the 24-command prototype
        // target plus its compact aliases and session commands). The
        // full 251-command catalog stays available to the UI from
        // catalog.json; commands outside this list reach cc_execute
        // anyway and answer with the interpreter's own codes
        // (E1002 unknown / E5002 not-implemented), never a fake result.
        ["set", "show-vars", "box", "cylinder", "sphere", "cone", "torus",
         "profile", "extrude", "union", "fuse", "cut", "intersect", "common",
         "fillet", "chamfer", "translate", "rotate", "copy", "duplicate",
         "rename", "delete", "clear", "list", "info", "volume",
         "measure-volume", "undo", "redo", "history", "shape-history",
         "export", "export-step", "export-stl", "view", "run", "echo", "help", "sim"]
    }

    public func execute(command: String) async -> CommandResult {
        let line = command
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let session else {
                    continuation.resume(returning: .error(
                        "Native engine session failed to start.",
                        code: "E5001 / CC-SYS-001"))
                    return
                }
                var out: UnsafeMutablePointer<CChar>?
                let rc = cc_execute(session, line, &out)
                let text = out.map { String(cString: $0) } ?? ""
                if let out { cc_free_string(out) }
                if rc == 0 {
                    continuation.resume(returning: .ok(text))
                } else {
                    let name = String(cString: cc_last_error_name(session))
                    let message = String(cString: cc_last_error_message(session))
                    continuation.resume(returning: .error(
                        message, code: "E\(rc) / \(name)"))
                }
            }
        }
    }

    /// Object names in the session, for AppState's scene mirroring
    /// (driven by cc_object_* queries, per EngineProtocol.swift).
    public func objectNames() async -> [String] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let session else { continuation.resume(returning: []); return }
                var names: [String] = []
                let count = cc_object_count(session)
                for i in 0..<count {
                    if let cName = cc_object_name(session, i) {
                        names.append(String(cString: cName))
                    }
                }
                continuation.resume(returning: names)
            }
        }
    }

    /// Tessellation for one object (or all when `name` is nil), in the
    /// cc_view_data layout the Metal viewer consumes (via the CCM1
    /// adapter in Shared/Viewer/Swift/EngineMeshAdapter.swift).
    /// A cc_view_data failure is reported in the result's
    /// `errorMessage` (the session's cc_last_error text) — v0.2
    /// silently returned [] here, which hid a broken viewer feed
    /// behind an apparently empty scene.
    public func viewData(name: String?) async -> EngineViewDataResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let session else {
                    continuation.resume(returning: EngineViewDataResult(
                        objects: [], errorMessage: "Native engine session failed to start."))
                    return
                }
                var objects: UnsafeMutablePointer<CCViewData>?
                var count: Int32 = 0
                let rc = name.map {
                    cc_view_data(session, $0, 0.5, &objects, &count)
                } ?? cc_view_data(session, nil, 0.5, &objects, &count)
                guard rc == 0, let objects else {
                    let errName = String(cString: cc_last_error_name(session))
                    let errMessage = String(cString: cc_last_error_message(session))
                    continuation.resume(returning: EngineViewDataResult(
                        objects: [],
                        errorMessage: errMessage.isEmpty ? errName : errMessage))
                    return
                }
                var result: [EngineViewObject] = []
                for i in 0..<Int(count) {
                    let d = objects[i]
                    let verts = (0..<Int(d.vertexCount) * 3).map { d.vertices[$0] }
                    let idx = (0..<Int(d.triangleCount) * 3).map { d.indices[$0] }
                    var ranges: [EngineViewObject.FaceRange] = []
                    if let fr = d.faceRanges {
                        for j in 0..<Int(d.faceRangeCount) {
                            ranges.append(EngineViewObject.FaceRange(
                                faceIndex: fr[j].faceIndex,
                                indexStart: fr[j].indexStart,
                                indexCount: fr[j].indexCount))
                        }
                    }
                    var edges: [EngineViewObject.Edge] = []
                    if let ed = d.edges {
                        for j in 0..<Int(d.edgeCount) {
                            edges.append(EngineViewObject.Edge(
                                edgeIndex: ed[j].edgeIndex,
                                start: [ed[j].start.0, ed[j].start.1, ed[j].start.2],
                                end: [ed[j].end.0, ed[j].end.1, ed[j].end.2]))
                        }
                    }
                    result.append(EngineViewObject(
                        name: String(cString: d.name),
                        vertices: verts, indices: idx,
                        volume: d.volume,
                        bbox: [d.bbox.0, d.bbox.1, d.bbox.2, d.bbox.3, d.bbox.4, d.bbox.5],
                        faceRanges: ranges, edges: edges))
                }
                cc_free_view_data(objects, count)
                continuation.resume(returning: EngineViewDataResult(objects: result))
            }
        }
    }
}
#endif

/// The one place the apps choose their engine. Native when the build
/// links it, StubEngine (honest E5002) otherwise.
public enum EngineFactory {
    public static func makeEngine() -> CascadeEngine {
        #if CASCADE_NATIVE_ENGINE
        return NativeEngine()
        #else
        return StubEngine()
        #endif
    }
}
