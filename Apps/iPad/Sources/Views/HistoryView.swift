import SwiftUI

/// History panel (v0.3.0): the parametric step list, in order.
/// Selecting a step loads its parameters into the right-hand editor;
/// editing or deleting replays the whole list into a fresh session
/// (see AppState.replayProject). A failed replay leaves the model
/// untouched and the error is shown here, naming the failing step.
struct HistoryView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
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
