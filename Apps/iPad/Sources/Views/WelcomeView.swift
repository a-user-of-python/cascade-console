import SwiftUI

/// One-time first-launch sheet: what the app is, three starter actions.
struct WelcomeView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("Cascade Console", systemImage: "cube.transparent")
                    .font(.title2.weight(.semibold))
                Text("3D modelling powered by Open CASCADE — now built from a UI, not typed commands. Pick a command in the Build panel on the right, set its values with the sliders and fields, and the part appears in the 3D view. Everything you make becomes a step in the History (left panel): select a step to change its values and the model rebuilds.")
                Text("Parts live in the tree on the left, grouped by the command that made them (box/, cut/, ...) and in folders you create — a box and a cut can share the same name. Save Project (toolbar) stores the history, folders and view as a .cascadeproj file; older .cascade scripts still open from the Files tab (Import makes one a project). The text console is still there — toolbar, terminal icon — for scripts, exports and simulation.")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        state.scriptBuffer = ExampleScript.welcome
                        state.currentFileName = ExampleScript.welcomeFileName
                        dismiss()
                    } label: {
                        Label("Open the welcome script", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        state.scriptBuffer = ExampleScript.sampleProject
                        state.currentFileName = ExampleScript.sampleFileName
                        dismiss()
                    } label: {
                        Label("Open the sample project", systemImage: "cube")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        dismiss()
                        state.runScript(ExampleScript.sampleProject)
                    } label: {
                        Label("Run the sample project now", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
