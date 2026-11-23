import SwiftUI

/// Scene object list: selection, visibility toggle, delete, clear all.
struct ObjectListView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if state.objects.isEmpty {
                ContentUnavailableView(
                    "No Objects",
                    systemImage: "cube",
                    description: Text("Objects you create with commands will appear here."))
            } else {
                List {
                    ForEach(state.objects) { item in
                        row(for: item)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            if state.objects.indices.contains(index) {
                                state.removeObject(state.objects[index])
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    state.clearScene()
                } label: {
                    Label("Clear Scene", systemImage: "trash")
                }
                .disabled(state.objects.isEmpty)
            }
        }
    }

    private func row(for item: SceneObjectItem) -> some View {
        HStack {
            Button {
                state.selectedObjectID = item.id
            } label: {
                HStack {
                    Image(systemName: item.isVisible ? "cube.fill" : "cube")
                        .foregroundStyle(.secondary)
                    Text(item.name)
                        .foregroundStyle(.primary)
                    if state.selectedObjectID == item.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                state.toggleVisibility(item)
            } label: {
                Image(systemName: item.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isVisible ? "Hide \(item.name)" : "Show \(item.name)")
        }
        .contentShape(Rectangle())
    }
}
