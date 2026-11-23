// INTEGRATION: the SettingsKey enum in this file uses the canonical
// cc.* strings for the keys it has; the single source of truth is now
// Shared/Settings/SettingsKeys.swift (which adds the iPad-only keys).
// Prefer Shared keys in new code. See INTEGRATION-NOTES (f).
import SwiftUI

// MARK: - Settings keys
//
// Every setting is stored in UserDefaults through `@AppStorage` with the
// keys below. The console and viewer read the same keys, so a change in the
// Settings window takes effect immediately — nothing here is decorative.

enum SettingsKey {
    static let units = "cc.units"                    // "mm" | "cm" | "in"
    static let tessellation = "cc.tessellation"      // "low"|"medium"|"high"|"fine"
    static let appearance = "cc.appearance"          // "system"|"light"|"dark"
    static let highContrast = "cc.highContrast"      // Bool
    static let autosave = "cc.autosave"              // Bool
    static let autosaveMinutes = "cc.autosaveMinutes" // Int
    static let consoleFontSize = "cc.consoleFontSize" // Double (points)
    static let keepLogLines = "cc.keepLogLines"      // Int
}

struct SettingsView: View {
    @AppStorage(SettingsKey.units) private var units = "mm"
    @AppStorage(SettingsKey.tessellation) private var tessellation = "medium"
    @AppStorage(SettingsKey.appearance) private var appearance = "system"
    @AppStorage(SettingsKey.highContrast) private var highContrast = false
    @AppStorage(SettingsKey.autosave) private var autosave = true
    @AppStorage(SettingsKey.autosaveMinutes) private var autosaveMinutes = 5
    @AppStorage(SettingsKey.consoleFontSize) private var consoleFontSize = 13.0
    @AppStorage(SettingsKey.keepLogLines) private var keepLogLines = 2000

    var body: some View {
        Form {
            Section("Modeling") {
                Picker("Units", selection: $units) {
                    Text("Millimetres (mm)").tag("mm")
                    Text("Centimetres (cm)").tag("cm")
                    Text("Inches (in)").tag("in")
                }
                Picker("Tessellation quality", selection: $tessellation) {
                    Text("Low — fastest").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                    Text("Fine — smoothest, slowest").tag("fine")
                }
                Text("Tessellation controls how finely curved surfaces are "
                     + "meshed for the 3D view. It does not change the "
                     + "underlying exact geometry.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("Match system").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Higher contrast text", isOn: $highContrast)
                // Note: text sizes in the app follow the system text-size
                // setting; nothing here overrides or inflates them.
            }

            Section("Console") {
                HStack {
                    Text("Console text size")
                    Slider(value: $consoleFontSize, in: 11...18, step: 1)
                    Text("\(Int(consoleFontSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Stepper("Keep up to \(keepLogLines) log lines",
                        value: $keepLogLines, in: 200...10000, step: 200)
            }

            Section("Autosave") {
                Toggle("Autosave the session script", isOn: $autosave)
                Stepper("Every \(autosaveMinutes) minutes",
                        value: $autosaveMinutes, in: 1...60)
                    .disabled(!autosave)
                Text("Autosave writes the commands you have run to a session "
                     + "script you can reopen later. It never overwrites a "
                     + "file you saved yourself.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
