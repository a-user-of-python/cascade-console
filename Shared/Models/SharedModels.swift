import Foundation
import SwiftUI

// MARK: - Shared console / scene models (INTEGRATION — canonical for BOTH apps)
//
// Merges the Mac scaffold's Models.swift and the iPad scaffold's
// CommandModels.swift. Differences resolved:
//  * Scene object: Mac carried `kind` + `colorHex`; iPad carried the
//    opaque core `shapeID`. The unified item carries BOTH — the core
//    refers to shapes by name, the façade by handle; `shapeID` is the
//    session name for Layer-2 (cc_facade.h refers to shapes by NAME).
//  * Log entry: one type with a `kind` and an optional unified error
//    code string (see docs/ERROR-CODES.md — codes are printed in the
//    canonical `E#### / CC-<DOMAIN>-###` pair form).
// Platform AppState types remain in the app folders and adapt to these
// models; see INTEGRATION-NOTES.md resolution (f).

/// One line (or block) of console output.
public struct ConsoleLogEntry: Identifiable, Equatable {
    public enum Kind: Equatable { case input, output, result, warning, error, info }
    public let id: UUID
    public let date: Date
    public var kind: Kind
    public var text: String
    /// Unified error code pair, e.g. "E1002 / CC-PARSE-001". Nil on success.
    public var code: String?

    public init(kind: Kind, text: String, code: String? = nil, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.kind = kind
        self.text = text
        self.code = code
    }
}

/// Result of running one command (or one script line) through the engine.
public struct CommandResult: Equatable {
    public var output: String
    public var isError: Bool
    /// Session names of shapes produced by the command.
    public var producedNames: [String]
    /// Unified error code pair when `isError` is true.
    public var code: String?

    public init(output: String, isError: Bool = false,
                producedNames: [String] = [], code: String? = nil) {
        self.output = output
        self.isError = isError
        self.producedNames = producedNames
        self.code = code
    }
    public static func ok(_ text: String) -> CommandResult { CommandResult(output: text) }
    public static func error(_ text: String, code: String? = nil) -> CommandResult {
        CommandResult(output: text, isError: true, code: code)
    }
}

/// One named object in the scene, as shown in the object/sidebar list.
/// UI mirror only — authoritative geometry lives in the core session.
public struct SceneObjectItem: Identifiable, Equatable {
    public let id: UUID
    /// Layer-2 session name of the shape (the façade's handle-by-name).
    public var shapeID: String
    public var name: String
    /// Human-readable kind, e.g. "Box", "Cylinder", "Cut result".
    public var kind: String
    public var isVisible: Bool
    /// "#RRGGBB" display colour.
    public var colorHex: String

    public init(shapeID: String, name: String, kind: String = "Shape",
                isVisible: Bool = true, colorHex: String = "#4F8FF7") {
        self.id = UUID()
        self.shapeID = shapeID
        self.name = name
        self.kind = kind
        self.isVisible = isVisible
        self.colorHex = colorHex
    }

    public var color: Color { Color(hexString: colorHex) ?? .blue }
}

public extension Color {
    /// Parses "#RRGGBB". Returns nil for anything malformed (no trapping).
    init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self = Color(red: Double((value >> 16) & 0xFF) / 255.0,
                     green: Double((value >> 8) & 0xFF) / 255.0,
                     blue: Double(value & 0xFF) / 255.0)
    }
}

/// File kinds the apps understand, keyed by lowercase path extension.
public enum CascadeFileKind: Equatable {
    case script, model, project, other
    public static func kind(forExtension ext: String) -> CascadeFileKind {
        switch ext.lowercased() {
        case "cascade", "ccs", "txt": return .script
        case "cascadeproj": return .project
        case "step", "stp", "iges", "igs", "stl", "brep", "obj", "gltf", "ply", "vrml": return .model
        default: return .other
        }
    }
}
