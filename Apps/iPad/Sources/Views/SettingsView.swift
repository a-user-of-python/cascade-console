import SwiftUI

/// Settings screen. Every control is backed by real @AppStorage state
/// (canonical keys in Shared/Settings/SettingsKeys.swift) and takes
/// effect immediately.
struct SettingsView: View {
    @AppStorage(SettingsKeys.units) private var unitsRaw = LengthUnit.mm.rawValue
    @AppStorage(SettingsKeys.tessellationQuality)
    private var tessellationRaw = TessellationQuality.medium.rawValue
    @AppStorage(SettingsKeys.appearance) private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage(SettingsKeys.highContrast) private var highContrast = false
    @AppStorage(SettingsKeys.autosave) private var autosave = true
    @AppStorage(SettingsKeys.autosaveIntervalMinutes) private var autosaveMinutes = 5
    @AppStorage(SettingsKeys.consoleFontSizeStep) private var fontStep = 0
    @AppStorage(SettingsKeys.showTimestamps) private var showTimestamps = false
    @AppStorage(SettingsKeys.confirmBeforeClear) private var confirmBeforeClear = true

    var body: some View {
        Form {
            Section("Modeling") {
                Picker("Units", selection: $unitsRaw) {
                    ForEach(LengthUnit.allCases) { unit in
                        Text(unit.label).tag(unit.rawValue)
                    }
                }
                Picker("Tessellation quality", selection: $tessellationRaw) {
                    ForEach(TessellationQuality.allCases) { quality in
                        Text(quality.label).tag(quality.rawValue)
                    }
                }
                Text("Tessellation controls how finely curved surfaces are meshed for the 3D view. Higher is smoother and slower.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Text(choice.label).tag(choice.rawValue)
                    }
                }
                Toggle("High contrast", isOn: $highContrast)
                Text("Text sizes follow your device's text-size setting; nothing in the app forces a larger size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Autosave") {
                Toggle("Autosave script buffer", isOn: $autosave)
                Stepper("Preferred interval: \(autosaveMinutes) min",
                        value: $autosaveMinutes, in: 1...30)
                    .disabled(!autosave)
                Text("Currently autosave also runs when the app goes to the background; the interval is stored for the timer refinement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Console") {
                Stepper("Log text size step: \(fontStep)",
                        value: $fontStep, in: -1...1)
                Toggle("Show timestamps", isOn: $showTimestamps)
                Toggle("Confirm before clearing log", isOn: $confirmBeforeClear)
            }

            Section("About") {
                LabeledContent("Engine", value: "Open CASCADE (OCCT)")
                LabeledContent("Licence", value: "LGPL 2.1 + OCCT exception")
                Text("Modelling commands are executed by the OCCT core. Simulation and analysis features report real computed results only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
