// INTEGRATION: superseded by Shared/Engine/EngineProtocol.swift
// (unified async CascadeEngine protocol + StubEngine). The sync
// ConsoleEngine form here is deprecated; see INTEGRATION-NOTES (f).
import Foundation

// MARK: - Console engine contract (Agent 2 plugs the real OCCT façade in here)
//
// The macOS app talks to the modeling core ONLY through `ConsoleEngine`.
// Agent 2's core (OCCT façade + full command dispatcher) provides a
// conforming type; this app never calls OCCT directly.
//
// Contract:
//  * `execute(_:objects:)` runs ONE command line and returns everything the
//    UI needs: log messages (plain language + error codes) and the scene
//    changes to mirror in the sidebar.
//  * It must never throw across this boundary and never crash on bad input:
//    malformed commands come back as `.error` messages with a stable code.
//  * `knownCommands` drives autocomplete and the `help` listing, so the real
//    engine should return its full command catalog, not a demo subset.

struct EngineMessage {
    var level: LogLevel
    var text: String
    var code: String?
}

struct EngineResult {
    var messages: [EngineMessage] = []
    /// Objects created or replaced by the command (matched by name).
    var upserted: [SceneObjectItem] = []
    /// Names of objects removed by the command.
    var removedNames: [String] = []
}

protocol ConsoleEngine {
    var knownCommands: [String] { get }
    func execute(_ command: String, objects: [SceneObjectItem]) -> EngineResult
}

// MARK: - Stub engine (first-launch placeholder)
//
// Deliberately tiny. It exists so the app launches, the console works, and
// the sidebar/viewer wiring can be exercised before Agent 2's engine lands.
// It is clearly labelled in its own output and must be replaced, not extended.

final class StubConsoleEngine: ConsoleEngine {

    let knownCommands: [String] = [
        "help", "list", "clear",
        "box", "cylinder", "sphere", "cone", "torus",
        "delete", "hide", "show", "color",
        "view fit", "view clear"
    ]

    func execute(_ command: String, objects: [SceneObjectItem]) -> EngineResult {
        let parts = command.split(separator: " ").map(String.init)
        guard let verb = parts.first?.lowercased() else {
            return EngineResult()
        }

        switch verb {
        case "help":
            return EngineResult(messages: [
                EngineMessage(
                    level: .info,
                    text: "Stub engine commands: " + knownCommands.joined(separator: ", ")
                        + ". The full Open CASCADE command catalog arrives with the core engine.",
                    code: nil)
            ])

        case "list":
            if objects.isEmpty {
                return EngineResult(messages: [
                    EngineMessage(level: .info, text: "The scene is empty.", code: nil)
                ])
            }
            let names = objects.map { "\($0.name) (\($0.kind))" }.joined(separator: ", ")
            return EngineResult(messages: [
                EngineMessage(level: .result, text: "Objects: " + names, code: nil)
            ])

        case "box", "cylinder", "sphere", "cone", "torus":
            let name = parts.count > 1 ? parts[1] : verb + "1"
            if objects.contains(where: { $0.name == name }) {
                return EngineResult(messages: [
                    EngineMessage(level: .error,
                                  text: "An object named \"\(name)\" already exists. Pick a different name.",
                                  code: "CC-E102")
                ])
            }
            let kind = verb.prefix(1).uppercased() + verb.dropFirst()
            let item = SceneObjectItem(name: name, kind: kind)
            return EngineResult(
                messages: [EngineMessage(level: .result,
                                         text: "Created \(kind.lowercased()) \"\(name)\" (stub engine — no real geometry yet).",
                                         code: nil)],
                upserted: [item])

        case "delete":
            guard parts.count > 1 else {
                return missingNameError(verb: verb)
            }
            let name = parts[1]
            guard objects.contains(where: { $0.name == name }) else {
                return noSuchObjectError(name: name)
            }
            return EngineResult(
                messages: [EngineMessage(level: .result, text: "Deleted \"\(name)\".", code: nil)],
                removedNames: [name])

        case "hide", "show":
            guard parts.count > 1 else {
                return missingNameError(verb: verb)
            }
            let name = parts[1]
            guard var item = objects.first(where: { $0.name == name }) else {
                return noSuchObjectError(name: name)
            }
            item.isVisible = (verb == "show")
            return EngineResult(
                messages: [EngineMessage(level: .result,
                                         text: "\(verb == "show" ? "Showing" : "Hiding") \"\(name)\".",
                                         code: nil)],
                upserted: [item])

        case "color":
            guard parts.count > 2 else {
                return EngineResult(messages: [
                    EngineMessage(level: .error,
                                  text: "Usage: color <object-name> <colour-name>. Colours: "
                                    + ObjectPalette.swatches.map { $0.name.lowercased() }.joined(separator: ", ") + ".",
                                  code: "CC-E101")
                ])
            }
            let name = parts[1]
            guard var item = objects.first(where: { $0.name == name }) else {
                return noSuchObjectError(name: name)
            }
            guard let swatch = ObjectPalette.swatches.first(where: {
                $0.name.lowercased() == parts[2].lowercased()
            }) else {
                return EngineResult(messages: [
                    EngineMessage(level: .error,
                                  text: "\"\(parts[2])\" is not a known colour name.",
                                  code: "CC-E103")
                ])
            }
            item.colorHex = swatch.hex
            return EngineResult(
                messages: [EngineMessage(level: .result,
                                         text: "\"\(name)\" is now \(swatch.name.lowercased()).",
                                         code: nil)],
                upserted: [item])

        case "view", "clear":
            // View/clear commands are handled by AppState (they act on the
            // viewer and the log, not on geometry).
            return EngineResult()

        default:
            return EngineResult(messages: [
                EngineMessage(level: .error,
                              text: "Unknown command \"\(verb)\". Type \"help\" to see what is available.",
                              code: "CC-E100")
            ])
        }
    }

    private func missingNameError(verb: String) -> EngineResult {
        EngineResult(messages: [
            EngineMessage(level: .error,
                          text: "Usage: \(verb) <object-name>. The command needs the name of an object.",
                          code: "CC-E101")
        ])
    }

    private func noSuchObjectError(name: String) -> EngineResult {
        EngineResult(messages: [
            EngineMessage(level: .error,
                          text: "There is no object named \"\(name)\". Type \"list\" to see the current objects.",
                          code: "CC-E104")
        ])
    }
}
