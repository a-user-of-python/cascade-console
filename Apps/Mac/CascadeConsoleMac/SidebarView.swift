import SwiftUI

/// Object list sidebar: every named object in the scene, with a visibility
/// toggle and a colour control per row. Selection drives the Delete action
/// and (later) the viewer's highlight, through `AppState.selectedObjectID`.
struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if state.objects.isEmpty {
                emptyState
            } else {
                List(selection: $state.selectedObjectID) {
                    ForEach(state.objects) { item in
                        objectRow(item)
                            .tag(item.id)
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            footer
        }
        .navigationTitle("Objects")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.transparent")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No objects yet")
                .font(.headline)
            Text("Create one from the console —\ntry:  box base")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func objectRow(_ item: SceneObjectItem) -> some View {
        HStack(spacing: 8) {
            Button {
                state.toggleVisibility(item)
            } label: {
                Image(systemName: item.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.plain)
            .help(item.isVisible ? "Hide \(item.name)" : "Show \(item.name)")
            .accessibilityLabel(item.isVisible ? "Hide \(item.name)" : "Show \(item.name)")

            Circle()
                .fill(item.color)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(.separator))

            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .lineLimit(1)
                Text(item.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                ForEach(ObjectPalette.swatches) { swatch in
                    Button(swatch.name) {
                        state.setColor(item, hex: swatch.hex)
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("Colour for \(item.name)")
            .accessibilityLabel("Colour for \(item.name)")
        }
        .opacity(item.isVisible ? 1.0 : 0.55)
    }

    private var footer: some View {
        HStack {
            Text("\(state.objects.count) object\(state.objects.count == 1 ? "" : "s")")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                state.deleteSelected()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(state.selectedObject == nil)
            .help("Delete the selected object")
        }
        .padding(8)
    }
}
