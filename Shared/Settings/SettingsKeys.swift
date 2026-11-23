import Foundation
import SwiftUI

// MARK: - Unified settings keys (INTEGRATION — canonical for BOTH apps)
//
// Resolution: the Mac scaffold used `cc.*` keys (enum `SettingsKey`) and
// the iPad scaffold used `settings.*` keys (enum `SettingsKeys`). Neither
// app has shipped, so no stored values exist to migrate. The canonical
// scheme is the Mac `cc.*` prefix, extended with the iPad-only keys.
// Platform Settings views must read THESE keys; the per-app enums are
// deprecated (see INTEGRATION-NOTES.md, resolution (f)).
//
// The console-font size is the Mac form (absolute points, Double). The
// iPad scaffold's relative `consoleFontSizeStep` is folded into it: the
// iPad Settings view converts step -> points when it is adapted (TODO,
// listed in INTEGRATION-NOTES.md).

public enum SettingsKeys {
    public static let units = "cc.units"                        // "mm" | "cm" | "in"
    public static let tessellationQuality = "cc.tessellation"   // "low"|"medium"|"high"|"fine"
    public static let appearance = "cc.appearance"              // "system"|"light"|"dark"
    public static let highContrast = "cc.highContrast"          // Bool
    public static let autosave = "cc.autosave"                  // Bool
    public static let autosaveIntervalMinutes = "cc.autosaveMinutes" // Int
    public static let consoleFontSize = "cc.consoleFontSize"    // Double (points)
    public static let consoleFontSizeStep = "cc.consoleFontSizeStep" // Int (iPad relative step, -1...1)
    public static let keepLogLines = "cc.keepLogLines"          // Int
    // Keys that originated in the iPad scaffold:
    public static let showTimestamps = "cc.showTimestamps"      // Bool
    public static let confirmBeforeClear = "cc.confirmBeforeClear" // Bool
    public static let welcomeSeeded = "cc.welcomeSeeded"        // Bool
    public static let welcomeShown = "cc.welcomeShown"          // Bool
    // Default export format (user-guide §7 setting; one shared key):
    public static let defaultExportFormat = "cc.defaultExportFormat" // "step"|"iges"|"brep"|"stl"|"obj"
}

public enum LengthUnit: String, CaseIterable, Identifiable {
    case mm, cm, inch
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .mm: return "Millimetres (mm)"
        case .cm: return "Centimetres (cm)"
        case .inch: return "Inches (in)"
        }
    }
}

public enum TessellationQuality: String, CaseIterable, Identifiable {
    case low, medium, high, fine
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .low: return "Low (fast)"
        case .medium: return "Medium"
        case .high: return "High"
        case .fine: return "Fine (slow)"
        }
    }
    /// Linear deflection (mm) handed to the core tessellator.
    public var deflection: Double {
        switch self {
        case .low: return 1.0
        case .medium: return 0.5
        case .high: return 0.2
        case .fine: return 0.05
        }
    }
}

public enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
