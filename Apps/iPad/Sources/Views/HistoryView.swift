import SwiftUI

/// History panel (v0.3.0): the parametric step list, in order.
/// Selecting a step loads its parameters into the right-hand editor;
/// editing or deleting replays the whole list into a fresh session
/// (see AppState.replayProject). A failed replay leaves the model
/// untouched and the error is shown here, naming the failing step.
struct HistoryView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            sessionControls
            Divider()
            if let error = state.lastReplayError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                Divider()
            }
            if state.project.steps.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "list.number",
                    description: Text("Every part you create from the Build panel becomes a step here. Select a step to edit it — the model rebuilds from the list."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(state.project.steps.enumerated()),
                            id: \.element.id) { index, step in
                        row(index: index, step: step)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            if state.project.steps.indices.contains(index) {
                                state.deleteStep(
                                    id: state.project.steps[index].id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .confirmationDialog(
            "Clear the whole scene?",
            isPresented: $showingClearConfirm,
            titleVisibility: .visible) {
            Button("Clear Scene", role: .destructive) {
                state.newProject()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes every part and every history step and starts a fresh session. Save the project first if you need it.")
        }
    }

    /// Session controls (v0.3.2 — these existed only as console
    /// commands in v0.3.0). Undo/Redo are the ENGINE's session
    /// undo/redo, the same commands the console runs: they act on
    /// the live session, so undoing a step-created part removes it
    /// from the session while its step stays in the list (a later
    /// replay rebuilds it) — the step list remains the model's
    /// source of truth, exactly as with console commands. Clear is
    /// the coherent full reset: fresh session, empty history.
    private var sessionControls: some View {
        HStack(spacing: 8) {
            Button {
                state.run(command: "undo")
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(state.isRunning)
            Button {
                state.run(command: "redo")
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(state.isRunning)
            Spacer()
            Button(role: .destructive) {
                showingClearConfirm = true
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(state.isRunning)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
    }

    private func row(index: Int, step: ModelStep) -> some View {
        let selected = state.selectedStepID == step.id
        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.displayTitle)
                    .foregroundStyle(.primary)
                Text(step.isScript
                     ? "Imported script — replays verbatim"
                     : (step.assignedName ?? step.command))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
            }
            Button(role: .destructive) {
                state.deleteStep(id: step.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete step \(index + 1)")
        }
        .contentShape(Rectangle())
        .onTapGesture { state.selectedStepID = step.id }
        .listRowBackground(selected ? Color.accentColor.opacity(0.15) : nil)
    }
}
