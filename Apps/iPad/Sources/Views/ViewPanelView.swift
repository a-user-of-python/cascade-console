import SwiftUI

/// The View panel (v0.3.2): the UI home for every view control
/// that used to exist only as a console `view ...` command —
/// grid, axes, face/edge number labels, display mode, camera
/// rotation sliders, standard views, fit/reset, and the measure
/// flow. It is the left panel's fourth segment.
///
/// Nothing here owns state: every control reads AppState.viewState
/// (a mirror re-read from the renderer after every change) and
/// acts through AppState.applyViewChange, which applies the exact
/// ViewerCommand the console parser produces for the equivalent
/// `view ...` line. Console and panel can be used interchangeably
/// and always agree.
struct ViewPanelView: View {
    @EnvironmentObject private var state: AppState

    // Camera slider drafts: the sliders apply live while dragging
    // (each tick is one setRotation, exactly like `view rotate`),
    // and the drafts re-sync from the mirror whenever the camera
    // moves any other way (viewport drag, console, snapshot) and
    // the user is not mid-drag.
    @State private var azimuthDraft: Double = 45
    @State private var elevationDraft: Double = 30
    @State private var editingRotation = false

    var body: some View {
        List {
            Section("Display") {
                Toggle("Grid", isOn: toggleBinding(\.gridVisible, ViewStateChange.setGrid))
                Toggle("Axes", isOn: toggleBinding(\.axesVisible, ViewStateChange.setAxes))
                Toggle("Face number labels",
                       isOn: toggleBinding(\.faceLabelsEnabled, ViewStateChange.setFaceLabels))
                Toggle("Edge number labels",
                       isOn: toggleBinding(\.edgeLabelsEnabled, ViewStateChange.setEdgeLabels))
                Picker("Mode", selection: modeBinding) {
                    Text("Shaded").tag(DisplayMode.shaded)
                    Text("Shaded + Edges").tag(DisplayMode.shadedWithEdges)
                    Text("Wireframe").tag(DisplayMode.wireframe)
                    Text("X-Ray").tag(DisplayMode.xray)
                    Text("Transparent").tag(DisplayMode.transparent)
                }
            }

            Section("Camera") {
                rotationRow("Azimuth", value: $azimuthDraft,
                            range: -180...180)
                rotationRow("Elevation", value: $elevationDraft,
                            range: -89.9...89.9)
                HStack(spacing: 8) {
                    ForEach([("Top", StandardView.top),
                             ("Front", StandardView.front),
                             ("Right", StandardView.right),
                             ("Iso", StandardView.iso)],
                            id: \.0) { label, view in
                        Button(label) {
                            state.applyViewChange(.standardView(view))
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        state.applyViewChange(.fit)
                    } label: {
                        Label("Fit View", systemImage: "arrow.up.left.and.arrow.down.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        state.applyViewChange(.resetCamera)
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("Measure") {
                Toggle("Measure between two points",
                       isOn: toggleBinding(\.measureEnabled, ViewStateChange.setMeasure))
                if state.viewState.measureEnabled {
                    Text(measureText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Clear Measure") {
                        state.applyViewChange(.clearMeasure)
                    }
                    .disabled(state.viewState.measurePointCount == 0)
                }
            }
        }
        .listStyle(.plain)
        .onAppear { syncDrafts() }
        .onChange(of: state.viewState.azimuthDegrees) { _, _ in
            if !editingRotation { syncDrafts() }
        }
        .onChange(of: state.viewState.elevationDegrees) { _, _ in
            if !editingRotation { syncDrafts() }
        }
    }

    // MARK: - Pieces

    private func rotationRow(_ label: String, value: Binding<Double>,
                             range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: range, onEditingChanged: { editing in
                editingRotation = editing
                if !editing { applyRotation() }
            })
            .onChange(of: value.wrappedValue) { _, _ in
                if editingRotation { applyRotation() }
            }
            Text("\(Int(value.wrappedValue.rounded()))°")
                .font(.callout.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var measureText: String {
        if let distance = state.measureDistance {
            return String(format: "Distance: %.2f mm", Double(distance))
        }
        switch state.viewState.measurePointCount {
        case 1: return "One point picked — tap the model once more."
        default: return "Tap two points on the model to measure between them."
        }
    }

    // MARK: - Bindings (read the mirror, act through the one path)

    private func toggleBinding(_ keyPath: KeyPath<ViewState, Bool>,
                               _ change: @escaping (Bool) -> ViewStateChange)
        -> Binding<Bool> {
        Binding(
            get: { state.viewState[keyPath: keyPath] },
            set: { state.applyViewChange(change($0)) })
    }

    private var modeBinding: Binding<DisplayMode> {
        Binding(
            get: { state.viewState.displayMode },
            set: { state.applyViewChange(.setDisplayMode($0)) })
    }

    private func applyRotation() {
        state.applyViewChange(.setRotation(
            azimuthDegrees: Float(azimuthDraft),
            elevationDegrees: Float(elevationDraft)))
    }

    private func syncDrafts() {
        azimuthDraft = Double(state.viewState.azimuthDegrees)
        elevationDraft = Double(state.viewState.elevationDegrees)
    }
}
