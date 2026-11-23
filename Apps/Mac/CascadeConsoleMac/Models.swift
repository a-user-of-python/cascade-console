// INTEGRATION: superseded by Shared/Models/SharedModels.swift (unified
// SceneObjectItem / ConsoleLogEntry). Kept for the Mac scaffold's
// internal references until the first device build adapts AppState;
// do not extend — extend the Shared model instead.
import SwiftUI

// MARK: - Scene objects (UI-side mirror of the core scene)

/// One named object in the scene, as shown in the sidebar.
/// This is a lightweight UI mirror only — the authoritative geometry lives
/// in the core façade (Agent 2). The UI never stores OCCT shapes.
struct SceneObjectItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Human-readable kind, e.g. "Box", "Cylinder", "Cut result".
    var kind: String
    var isVisible: Bool
    /// "#RRGGBB" display colour.
    var colorHex: String

    init(id: UUID = UUID(),
         name: String,
         kind: String,
         isVisible: Bool = true,
         colorHex: String = "#4F8FF7") {
        self.id = id
        self.name = name
        self.kind = kind
        self.isVisible = isVisible
        self.colorHex = colorHex
    }

    var color: Color {
        Color(hexString: colorHex) ?? .blue
    }
}

/// Value snapshot handed to the viewer (Agent 5) so the viewer never needs
/// to know about UI model types.
struct SceneObjectSnapshot: Equatable {
    var name: String
    var kind: String
    var isVisible: Bool
    var colorHex: String
}

extension SceneObjectItem {
    var snapshot: SceneObjectSnapshot {
        SceneObjectSnapshot(name: name, kind: kind,
                            isVisible: isVisible, colorHex: colorHex)
    }
}

// MARK: - Console log

enum LogLevel: String, Equatable {
    case info
    case result
    case warning
    case error

    var tint: Color {
        switch self {
        case .info: return .secondary
        case .result: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }

    var symbolName: String {
        switch self {
        case .info: return "info.circle"
        case .result: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

/// One line (or block) in the console output log.
/// Errors always carry a stable error code (e.g. "CC-E100") plus plain
/// language text — never a raw exception string alone.
struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    var level: LogLevel
    var text: String
    var code: String?

    init(level: LogLevel, text: String, code: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.level = level
        self.text = text
        self.code = code
    }
}

// MARK: - File actions routed from the menu bar to the content view

enum FileAction: Equatable {
    case openScript
    case saveScript
    case importModel
    case exportModel
}

// MARK: - Colour helper

extension Color {
    /// Parses "#RRGGBB". Returns nil for anything malformed (no trapping).
    init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}

/// One preset colour offered in the sidebar.
struct PaletteSwatch: Identifiable, Equatable {
    var name: String
    var hex: String
    var id: String { hex }
}

/// Preset swatches offered in the sidebar (kept small on purpose: low clutter).
enum ObjectPalette {
    static let swatches: [PaletteSwatch] = [
        PaletteSwatch(name: "Blue", hex: "#4F8FF7"),
        PaletteSwatch(name: "Green", hex: "#3FA34D"),
        PaletteSwatch(name: "Orange", hex: "#E8833A"),
        PaletteSwatch(name: "Red", hex: "#D64545"),
        PaletteSwatch(name: "Purple", hex: "#8B5CF6"),
        PaletteSwatch(name: "Gray", hex: "#8A8F98")
    ]
}
