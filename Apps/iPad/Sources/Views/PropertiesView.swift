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

    @State private var simForm = SimFormState()
    @State private var showingRename = false
    @State private var renameText = ""

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
                    Button("Rename…") {
                        renameText = CascadeNames.display(of: item.shapeID)
                        showingRename = true
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
                Section("Export") {
                    HStack(spacing: 8) {
                        Button {
                            state.exportPart(qualifiedName: item.shapeID,
                                             format: "step")
                        } label: {
                            Label("STEP", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        Button {
                            state.exportPart(qualifiedName: item.shapeID,
                                             format: "stl")
                        } label: {
                            Label("STL", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                simSection(for: item)
            }
            .listStyle(.plain)
            .alert("Rename Part", isPresented: $showingRename) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    state.renameTreeEntry(qualifiedName: item.shapeID,
                                          to: renameText)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The part keeps its directory (\(CascadeNames.directory(of: item.shapeID))/); the new name is claimed inside it.")
            }
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

    // MARK: - Simulation (v0.3.2)
    //
    // The form generates the existing `sim ...` commands verbatim
    // (SimScriptBuilder) and runs them through the engine; results
    // land in the console log from the real solver. Statics only —
    // thermal stays console-only (its temperature/flux/convection
    // boundary conditions are a second form family; see FIXLOG).

    @ViewBuilder
    private func simSection(for item: SceneObjectItem) -> some View {
        let setup = SimScriptBuilder.setupLines(object: item.shapeID,
                                                form: simForm)
        Section("Simulation — Statics") {
            Picker("Material", selection: $simForm.material) {
                ForEach(SimFormState.materials, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            simFaceRow("Fixed face", text: $simForm.fixedFace)
            simFaceRow("Load face", text: $simForm.loadFace)
            Picker("Load type", selection: $simForm.loadKind) {
                Text("Force").tag(SimFormState.LoadKind.force)
                Text("Pressure").tag(SimFormState.LoadKind.pressure)
            }
            .pickerStyle(.segmented)
            if simForm.loadKind == .force {
                simNumberRow("Force X (N)", text: $simForm.forceX)
                simNumberRow("Force Y (N)", text: $simForm.forceY)
                simNumberRow("Force Z (N)", text: $simForm.forceZ)
            } else {
                simNumberRow("Pressure (MPa)", text: $simForm.pressureMPa)
            }
            simNumberRow("Mesh size (mm)", text: $simForm.meshSize)
            Button {
                if let setup { state.runSimLines(setup) }
            } label: {
                Label("Set Up Simulation", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(setup == nil || state.isRunning)
            Button {
                state.runSimLines(
                    [SimScriptBuilder.runLine(object: item.shapeID)])
            } label: {
                Label("Run Simulation", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isRunning)
            Button("Clear Sim Setup") {
                state.runSimLines(
                    [SimScriptBuilder.clearLine(object: item.shapeID)])
            }
            .disabled(state.isRunning)
            Text("Face numbers are the viewer's census indices — turn on face labels in the View panel to see them on the model. Results appear in the console. Thermal simulation stays in the console (sim thermal …).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func simFaceRow(_ label: String,
                            text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .noAutocapitalization()
                .autocorrectionDisabled(true)
                .numericKeyboard()
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
        }
    }

    private func simNumberRow(_ label: String,
                              text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .noAutocapitalization()
                .autocorrectionDisabled(true)
                .numericKeyboard()
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
        }
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
