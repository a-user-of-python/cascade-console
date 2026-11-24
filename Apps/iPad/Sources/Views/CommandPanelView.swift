import SwiftUI

/// The right sidebar (v0.3.0): the command UI that replaces typing
/// commands. Two modes on ONE editor surface:
///
///  * ADD mode — the big grouped command list (only commands the
///    engine actually implements; see CommandCatalog) with the
///    selected command's parameter form below it: sliders paired
///    with numeric fields (typing an exact value always wins),
///    pickers for object/profile references fed from the session,
///    and a name field that may be left blank (the name is then
///    auto-assigned in the command's directory, and the panel shows
///    exactly which name will be claimed).
///  * EDIT mode — entered by selecting a history step or a part in
///    the tree: the form shows THAT step's parameters; Apply replays
///    the whole history with the edit (a failure is reported in the
///    History panel and changes nothing).
struct CommandPanelView: View {
    @EnvironmentObject private var state: AppState

    @State private var draftCommandID: String = "box"
    @State private var draftParams: [String: String] =
        CommandCatalog.spec(for: "box")?.defaultParams ?? [:]
    @State private var draftName: String = ""

    private var selectedStep: ModelStep? {
        guard let id = state.selectedStepID else { return nil }
        return state.project.steps.first { $0.id == id }
    }

    private var addSpec: CommandSpec {
        CommandCatalog.spec(for: draftCommandID) ?? CommandCatalog.all[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let step = selectedStep {
                    editHeader(step)
                    if step.isScript {
                        scriptStepNote(step)
                    } else if let spec = CommandCatalog.spec(for: step.command) {
                        form(for: spec)
                        editActions(step)
                    }
                } else {
                    commandList
                    Divider()
                    form(for: addSpec)
                    addAction
                }
            }
            .padding(12)
        }
        .onChange(of: state.selectedStepID) { _, newID in
            loadDraft(for: newID)
        }
        .onAppear { loadDraft(for: state.selectedStepID) }
    }

    // MARK: - Draft loading

    private func loadDraft(for stepID: UUID?) {
        if let stepID,
           let step = state.project.steps.first(where: { $0.id == stepID }),
           !step.isScript {
            draftCommandID = step.command
            draftParams = mergedDefaults(for: step)
            draftName = step.name
        } else if stepID == nil {
            draftParams = addSpec.defaultParams
            draftName = ""
        }
    }

    /// A step's stored params over the spec's defaults (a step saved
    /// by an older form still edits completely).
    private func mergedDefaults(for step: ModelStep) -> [String: String] {
        var params = CommandCatalog.spec(for: step.command)?.defaultParams ?? [:]
        for (key, value) in step.params { params[key] = value }
        return params
    }

    // MARK: - Add mode

    private var commandList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commands")
                .font(.headline)
            ForEach(Array(CommandCatalog.grouped().enumerated()),
                    id: \.offset) { _, group in
                Text(group.group)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(group.specs, id: \.id) { spec in
                    Button {
                        draftCommandID = spec.id
                        draftParams = spec.defaultParams
                        draftName = ""
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(spec.title)
                                    .foregroundStyle(.primary)
                                Text(spec.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            if spec.id == draftCommandID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var addAction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(predictedNameText(for: addSpec))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                state.addStepFromUI(command: addSpec.id,
                                    params: draftParams,
                                    name: draftName)
                draftName = ""
            } label: {
                Label("Add \(addSpec.title)", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isRunning)
        }
    }

    /// The exact qualified name the engine will claim for this form,
    /// computed with the same rules the engine uses (CascadeNames) —
    /// shown before creating so auto-naming is never a surprise.
    private func predictedNameText(for spec: CommandSpec) -> String {
        let existing = state.objects.map { $0.shapeID } + state.profiles
        let requested = draftName.trimmingCharacters(in: .whitespaces).isEmpty
            ? CascadeNames.autoName(directory: spec.directory, existing: existing)
            : draftName.trimmingCharacters(in: .whitespaces)
        let final = CascadeNames.uniqueName(
            directory: spec.directory, requested: requested, existing: existing)
        return "Will be created as \(spec.directory):\(final)"
    }

    // MARK: - Edit mode

    private func editHeader(_ step: ModelStep) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Editing step")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(step.displayTitle)
                    .font(.headline)
            }
            Spacer()
            Button("Done") { state.selectedStepID = nil }
                .buttonStyle(.bordered)
        }
    }

    private func scriptStepNote(_ step: ModelStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This step is an imported script. It replays verbatim and has no parameters to edit — its text is the script itself (open it from the Files tab). Deleting the step removes the whole import from the history.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(role: .destructive) {
                state.deleteStep(id: step.id)
            } label: {
                Label("Delete Step", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(state.isRunning)
        }
    }

    private func editActions(_ step: ModelStep) -> some View {
        VStack(spacing: 8) {
            Button {
                state.applyStepEdit(id: step.id,
                                    params: draftParams,
                                    name: draftName)
            } label: {
                Label("Apply Edit (rebuild)", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isRunning)
            Button(role: .destructive) {
                state.deleteStep(id: step.id)
            } label: {
                Label("Delete Step", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(state.isRunning)
        }
    }

    // MARK: - Parameter form

    @ViewBuilder
    private func form(for spec: CommandSpec) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(spec.title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("Blank = auto-assign", text: $draftName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
            }
            ForEach(spec.params, id: \.key) { param in
                paramRow(param)
            }
        }
    }

    @ViewBuilder
    private func paramRow(_ param: ParamSpec) -> some View {
        switch param.type {
        case .length, .number, .angle:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(param.label)
                        .font(.callout)
                    Spacer()
                    TextField(param.defaultValue,
                              text: stringBinding(for: param))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 84)
                        .multilineTextAlignment(.trailing)
                }
                if param.hasSlider {
                    Slider(value: sliderBinding(for: param),
                           in: (param.sliderMin ?? 0)...(param.sliderMax ?? 1))
                }
            }
        case .objectRef, .profileRef:
            VStack(alignment: .leading, spacing: 4) {
                Text(param.label)
                    .font(.callout)
                Picker(param.label, selection: stringBinding(for: param)) {
                    Text("Choose…").tag("")
                    ForEach(refCandidates(for: param), id: \.self) { name in
                        Text("\(CascadeNames.display(of: name)) (\(CascadeNames.directory(of: name)))")
                            .tag(name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .pointList, .edgeList, .text:
            VStack(alignment: .leading, spacing: 4) {
                Text(param.label)
                    .font(.callout)
                TextField(param.defaultValue, text: stringBinding(for: param))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .textFieldStyle(.roundedBorder)
                if param.type == .edgeList {
                    Text("Edge numbers from the viewer's edge labels; blank fillets/chamfers every edge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func refCandidates(for param: ParamSpec) -> [String] {
        param.type == .profileRef
            ? state.profiles
            : state.objects.map { $0.shapeID }
    }

    private func stringBinding(for param: ParamSpec) -> Binding<String> {
        Binding(
            get: { draftParams[param.key] ?? param.defaultValue },
            set: { draftParams[param.key] = $0 })
    }

    private func sliderBinding(for param: ParamSpec) -> Binding<Double> {
        Binding(
            get: { Double(draftParams[param.key] ?? param.defaultValue)
                ?? Double(param.defaultValue) ?? 0 },
            set: { newValue in
                draftParams[param.key] = StepLineBuilder.formatNumber(
                    String(format: "%.4g", newValue)) ?? param.defaultValue
            })
    }
}
