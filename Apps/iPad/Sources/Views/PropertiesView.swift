import SwiftUI

/// Properties panel (v0.3.0): the inspector that used to sit on the
/// right, moved to the left panel per the redesign. Shows the
/// selected part's identity (display name, directory, qualified
/// name) and its measured geometry from the last viewer feed —
/// volume, census face/edge counts, bounding box — plus the display
/// toggles. Numbers come from the engine's own view data
/// (AppState.objectStats), never from the tessellation.
struct PropertiesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let item = selectedItem {
            List {
                Section("Part") {
                    LabeledContent("Name",
                                   value: CascadeNames.display(of: item.shapeID))
                    LabeledContent("Directory",
                                   value: CascadeNames.directory(of: item.shapeID) + "/")
                    LabeledContent("Qualified name", value: item.shapeID)
                    if let step = state.project.steps.first(where: {
                        $0.assignedName == item.shapeID
                    }) {
                        LabeledContent("Created by step",
                                       value: step.displayTitle)
                    }
                }
                if let stats = state.objectStats[item.shapeID] {
                    Section("Geometry (engine)") {
                        LabeledContent("Volume",
                                       value: format(stats.volume) + " mm³")
                        LabeledContent("Faces",
                                       value: "\(stats.faceRanges.count)")
                        LabeledContent("Edges",
                                       value: "\(stats.edges.count)")
                        LabeledContent("Bounding box",
                                       value: bboxText(stats.bbox))
                    }
                }
                Section("Display") {
                    Toggle("Visible", isOn: Binding(
                        get: { item.isVisible },
                        set: { _ in state.toggleVisibility(item) }))
                }
            }
            .listStyle(.plain)
        } else if let profile = selectedProfile {
            List {
                Section("Profile") {
                    LabeledContent("Name",
                                   value: CascadeNames.display(of: profile))
                    LabeledContent("Qualified name", value: profile)
                    Text("Profiles are 2D: extrude one from the Build panel to make a solid.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
        } else {
            ContentUnavailableView(
                "Nothing Selected",
                systemImage: "info.circle",
                description: Text("Select a part in the tree to see its properties."))
        }
    }

    private var selectedItem: SceneObjectItem? {
        guard let id = state.selectedObjectID else { return nil }
        return state.objects.first { $0.id == id }
    }

    /// A profile selected via its creating step (profiles have no
    /// scene item of their own).
    private var selectedProfile: String? {
        guard selectedItem == nil,
              let stepID = state.selectedStepID,
              let step = state.project.steps.first(where: { $0.id == stepID }),
              let assigned = step.assignedName,
              CascadeNames.directory(of: assigned) == "profile"
        else { return nil }
        return assigned
    }

    private func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e12 {
            return String(Int(value))
        }
        return String(format: "%.3f", value)
    }

    private func bboxText(_ bbox: [Double]) -> String {
        guard bbox.count == 6 else { return "—" }
        let dx = bbox[3] - bbox[0], dy = bbox[4] - bbox[1], dz = bbox[5] - bbox[2]
        return "\(format(dx)) × \(format(dy)) × \(format(dz)) mm"
    }
}
