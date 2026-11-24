//
//  ViewState.swift
//  Cascade Console - Viewer
//
//  The view panel's state contract (v0.3.2). Before v0.3.2 the
//  view controls (grid, axes, face/edge labels, display mode,
//  camera rotation, measure) existed only as console `view ...`
//  commands; the v0.3.0 UI redesign gave them no home. The panel
//  now drives the SAME state the console commands drive:
//
//   * `ViewState` is a read-only SNAPSHOT of the live viewer state
//     (SceneStore flags + the renderer's label flags + the camera
//     angles). It is never a second source of truth: the app
//     re-reads it from the renderer after every change.
//   * `ViewStateChange` is one panel action. Its `viewerCommand`
//     is the exact ViewerCommand the console parser produces for
//     the equivalent `view ...` line, and the app applies it
//     through CascadeRenderer.apply — the same path the console
//     takes. SceneStore.apply performs the store-side mutation
//     (SceneStore is what the Swift harness compiles, so the
//     panel's state transitions are executed by the gate, not
//     just compiled — see the harness's view-state section).
//

import Foundation
import simd

/// A snapshot of everything the View panel shows. Angles are in
/// degrees (the panel's sliders work in degrees, like the
/// `view rotate` command); the store keeps radians.
public struct ViewState: Equatable {
    public var gridVisible: Bool
    public var axesVisible: Bool
    public var faceLabelsEnabled: Bool
    public var edgeLabelsEnabled: Bool
    public var displayMode: DisplayMode
    public var measureEnabled: Bool
    /// How many measure points are currently picked (0, 1 or 2) —
    /// the panel's measure readout needs it (a single picked point
    /// has no distance yet).
    public var measurePointCount: Int
    public var azimuthDegrees: Float
    public var elevationDegrees: Float

    public init(gridVisible: Bool = true,
                axesVisible: Bool = true,
                faceLabelsEnabled: Bool = false,
                edgeLabelsEnabled: Bool = false,
                displayMode: DisplayMode = .shaded,
                measureEnabled: Bool = false,
                measurePointCount: Int = 0,
                azimuthDegrees: Float = 45,
                elevationDegrees: Float = 30) {
        self.gridVisible = gridVisible
        self.axesVisible = axesVisible
        self.faceLabelsEnabled = faceLabelsEnabled
        self.edgeLabelsEnabled = edgeLabelsEnabled
        self.displayMode = displayMode
        self.measureEnabled = measureEnabled
        self.measurePointCount = measurePointCount
        self.azimuthDegrees = azimuthDegrees
        self.elevationDegrees = elevationDegrees
    }

    /// Read the live state out of a store + the renderer's label
    /// flags. This is the ONLY way a ViewState comes into being in
    /// the app — from the truth, never edited in place.
    public init(store: SceneStore, faceLabels: Bool, edgeLabels: Bool) {
        self.init(gridVisible: store.gridVisible,
                  axesVisible: store.axesVisible,
                  faceLabelsEnabled: faceLabels,
                  edgeLabelsEnabled: edgeLabels,
                  displayMode: store.displayMode,
                  measureEnabled: store.measureEnabled,
                  measurePointCount: store.measurePoints.count,
                  azimuthDegrees: store.camera.azimuth * 180 / .pi,
                  elevationDegrees: store.camera.elevation * 180 / .pi)
    }
}

/// One action from the View panel. Each case maps to exactly the
/// ViewerCommand the console's ViewCommandParser produces for the
/// equivalent text command (the harness pins the pairs).
public enum ViewStateChange: Equatable {
    case setGrid(Bool)
    case setAxes(Bool)
    case setFaceLabels(Bool)
    case setEdgeLabels(Bool)
    case setDisplayMode(DisplayMode)
    case setMeasure(Bool)
    case clearMeasure
    case setRotation(azimuthDegrees: Float, elevationDegrees: Float)
    case standardView(StandardView)
    case fit
    case resetCamera

    public var viewerCommand: ViewerCommand {
        switch self {
        case .setGrid(let on): return .setGridVisible(on)
        case .setAxes(let on): return .setAxesVisible(on)
        case .setFaceLabels(let on): return .setFaceLabelsEnabled(on)
        case .setEdgeLabels(let on): return .setEdgeLabelsEnabled(on)
        case .setDisplayMode(let mode): return .displayMode(mode)
        case .setMeasure(let on): return .setMeasureEnabled(on)
        case .clearMeasure: return .clearMeasure
        case .setRotation(let az, let el):
            return .setCameraRotation(azimuthDegrees: az,
                                      elevationDegrees: el)
        case .standardView(let view): return .standardView(view)
        case .fit: return .fit
        case .resetCamera: return .resetCamera
        }
    }
}
