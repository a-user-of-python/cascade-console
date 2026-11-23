// INTEGRATION: superseded by Shared/Settings/SettingsKeys.swift
// (canonical cc.* keys for BOTH apps). This file's settings.* key
// strings are deprecated — no shipped build used them, so no
// migration is needed. See INTEGRATION-NOTES (f).
import Foundation
import SwiftUI

/// Single source of truth for @AppStorage keys. Every screen and the
/// engine / viewer bridges read through these keys — never stringly
/// typed duplicates elsewhere.
enum SettingsKeys {
    static let units = "settings.units"
    static let tessellationQuality = "settings.tessellationQuality"
    static let appearance = "settings.appearance"
    static let highContrast = "settings.highContrast"
    static let autosave = "settings.autosave"
    static let autosaveIntervalMinutes = "settings.autosaveIntervalMinutes"
    static let consoleFontSizeStep = "settings.consoleFontSizeStep"
    static let showTimestamps = "settings.showTimestamps"
    static let confirmBeforeClear = "settings.confirmBeforeClear"
    static let welcomeSeeded = "app.welcomeSeeded"
    static let welcomeShown = "app.welcomeShown"
}

enum LengthUnit: String, CaseIterable, Identifiable {
    case mm
    case cm
    case inch

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mm: return "Millimetres (mm)"
        case .cm: return "Centimetres (cm)"
        case .inch: return "Inches (in)"
        }
    }
}

enum TessellationQuality: String, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case fine

    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: return "Low (fast)"
        case .medium: return "Medium"
        case .high: return "High"
        case .fine: return "Fine (slow)"
        }
    }

    /// Linear deflection hint passed to the viewer / mesher.
    var deflection: Double {
        switch self {
        case .low: return 1.0
        case .medium: return 0.5
        case .high: return 0.2
        case .fine: return 0.05
        }
    }
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
