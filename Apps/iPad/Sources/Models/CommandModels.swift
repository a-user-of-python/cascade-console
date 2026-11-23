// INTEGRATION: superseded by Shared/Models/SharedModels.swift
// (unified CommandResult / ConsoleLogEntry / SceneObjectItem).
// Kept for the iPad scaffold's internal references until the first
// device build adapts AppState; do not extend.
import Foundation

/// One line (or block) of console output.
struct LogEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case input
        case output
        case error
        case info
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let text: String

    init(kind: Kind, text: String, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.kind = kind
        self.text = text
    }
}

/// Result of running one command (or one script line) through the engine.
struct CommandResult: Equatable {
    var output: String
    var isError: Bool
    /// Opaque OCCT shape IDs produced by the command, if any.
    var producedShapeIDs: [String]
    /// Human-readable names parallel to producedShapeIDs (may be shorter).
    var producedNames: [String]

    init(output: String, isError: Bool = false,
         producedShapeIDs: [String] = [], producedNames: [String] = []) {
        self.output = output
        self.isError = isError
        self.producedShapeIDs = producedShapeIDs
        self.producedNames = producedNames
    }

    static func ok(_ text: String) -> CommandResult {
        CommandResult(output: text)
    }

    static func error(_ text: String) -> CommandResult {
        CommandResult(output: text, isError: true)
    }
}

/// One object in the scene, as shown in the object list.
struct SceneObjectItem: Identifiable, Equatable {
    let id: UUID
    /// Opaque shape ID from the OCCT core.
    let shapeID: String
    var name: String
    var isVisible: Bool

    init(shapeID: String, name: String) {
        self.id = UUID()
        self.shapeID = shapeID
        self.name = name
        self.isVisible = true
    }
}

/// File kinds the app understands, keyed by lowercase path extension.
enum CascadeFileKind: Equatable {
    case script
    case model
    case other

    static func kind(forExtension ext: String) -> CascadeFileKind {
        switch ext.lowercased() {
        case "cascade", "txt":
            return .script
        case "step", "stp", "iges", "igs", "stl", "brep":
            return .model
        default:
            return .other
        }
    }

    static var scriptExtensions: Set<String> { ["cascade", "txt"] }
    static var modelExtensions: Set<String> {
        ["step", "stp", "iges", "igs", "stl", "brep"]
    }
}
