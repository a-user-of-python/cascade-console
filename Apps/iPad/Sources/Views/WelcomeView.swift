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
                Text("Text-command 3D modelling powered by Open CASCADE. Type commands in the console, create objects, then look at them in the 3D view.")
                Text("A welcome script and a sample project were saved into the app's Documents folder — open them from the Files tab. Files there are browsed in-app, so everything works even if the system file picker does not.")
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
                        state.run(command: "help")
                    } label: {
                        Label("Just show me the commands", systemImage: "terminal")
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
