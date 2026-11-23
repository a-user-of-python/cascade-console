// INTEGRATION: superseded by Shared/Engine/EngineProtocol.swift
// (unified async CascadeEngine protocol + StubEngine). The
// CascadeEngineFacing name here is deprecated; see INTEGRATION-NOTES (f).
import Foundation

/// Connection point for Agent 2's Open CASCADE core facade.
///
/// Implement this protocol over the C facade (bridging header / C Swift
/// package) and inject the implementation in `CascadeConsoleApp`.
/// Commands are the app's bare text commands; results carry plain-text
/// output plus opaque shape IDs for anything the command produced.
protocol CascadeEngineFacing: AnyObject {
    func execute(command: String) async -> CommandResult
    func executeScript(_ script: String) async -> [CommandResult]
}

extension CascadeEngineFacing {
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
final class StubEngine: CascadeEngineFacing {

    func execute(command: String) async -> CommandResult {
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
                "so '\(verb)' cannot run. Commands available now: help, echo, clear.")
        }
    }

    static let helpText = """
    Cascade Console commands (console-local ones work today):
      help              show this text
      echo <text>       print text to the console
      clear             clear the console log
      load <file>       load a script from Documents into the console
    All modelling commands (box, cylinder, fuse, cut, fillet, view, \
    export, ...) are provided by the Open CASCADE core once it is \
    linked — see the user guide for the full catalogue.
    """
}
