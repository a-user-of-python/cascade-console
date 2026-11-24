//
//  SceneStore.swift
//  Cascade Console - Viewer
//
//  Owns the viewer's scene state and the CPU copies of every mesh.
//
//  PERFORMANCE CONTRACT (see README "Performance rules"):
//   * Meshes are cached by (objectID, geometryVersion). Loading a mesh
//     whose key is already resident is a no-op - the renderer keeps its
//     GPU buffers. Camera moves, display-mode changes, colour/opacity/
//     visibility changes NEVER touch geometry.
//   * Re-tessellation happens only on the core side, only when the core
//     bumps geometryVersion (a modelling change) or when the user
//     changes tessellation quality in Settings.
//   * Picking and measuring run against these CPU copies; no GPU
//     readback, no re-tessellation.
//

import Foundation
import simd

public final class SceneStore {
    public struct Entry {
        public var mesh: MeshObject
        public var props: ObjectDisplayProps
    }

    public private(set) var entries: [String: Entry] = [:]
    public private(set) var order: [String] = []        // stable draw order

    public var camera = OrbitCamera()
    public var displayMode: DisplayMode = .shaded
    public var section: SectionPlane?
    public var explodeFactor: Float = 0
    public var gridVisible = true
    public var axesVisible = true
    public var measureEnabled = false
    public private(set) var measurePoints: [SIMD3<Float>] = []
    public var backgroundTop = SIMD4<Float>(0.10, 0.11, 0.13, 1)
    public var backgroundBottom = SIMD4<Float>(0.05, 0.05, 0.06, 1)

    public init() {}

    // MARK: Scene data

    /// Returns true if geometry actually changed (new GPU upload needed).
    @discardableResult
    public func load(_ mesh: MeshObject, props: ObjectDisplayProps) -> Bool {
        if let existing = entries[mesh.id],
           existing.mesh.geometryVersion == mesh.geometryVersion,
           existing.mesh.vertices.count == mesh.vertices.count,
           existing.mesh.indices.count == mesh.indices.count {
            entries[mesh.id]?.props = props
            return false
        }
        if entries[mesh.id] == nil { order.append(mesh.id) }
        entries[mesh.id] = Entry(mesh: mesh, props: props)
        return true
    }

    /// Replace the display props of one entry. `entries` is
    /// private(set), so outside owners (the Renderer) mutate display
    /// state through here instead of writing `entries[id]?.props`
    /// directly, which the access control rightly rejects.
    public func setProps(id: String, props: ObjectDisplayProps) {
        entries[id]?.props = props
    }

    /// Mutate one entry's display props in place (visibility, opacity,
    /// colour) without touching its geometry.
    public func mutateProps(id: String, _ change: (inout ObjectDisplayProps) -> Void) {
        guard var entry = entries[id] else { return }
        change(&entry.props)
        entries[id] = entry
    }

    public func remove(id: String) {
        entries[id] = nil
        order.removeAll { $0 == id }
    }

    public func clear() {
        entries.removeAll()
        order.removeAll()
        measurePoints.removeAll()
    }

    // MARK: Scene-wide bounds

    public var sceneCentre: SIMD3<Float> {
        guard let b = sceneBounds else { return .zero }
        return (b.0 + b.1) / 2
    }

    public var sceneBounds: (SIMD3<Float>, SIMD3<Float>)? {
        var lo: SIMD3<Float>?
        var hi: SIMD3<Float>?
        for entry in entries.values where entry.props.isVisible {
            lo = lo.map { simd_min($0, entry.mesh.boundingBoxMin) } ?? entry.mesh.boundingBoxMin
            hi = hi.map { simd_max($0, entry.mesh.boundingBoxMax) } ?? entry.mesh.boundingBoxMax
        }
        guard let lo, let hi else { return nil }
        return (lo, hi)
    }

    public func fitCamera() {
        guard let (lo, hi) = sceneBounds else { return }
        let centre = (lo + hi) / 2
        let radius = simd_length(hi - lo) / 2
        camera.fit(centre: centre, radius: max(radius, 0.001))
    }

    /// Model matrix for one object, including the explode offset:
    /// parts move away from the scene centre along their own centre line.
    public func modelMatrix(for id: String) -> float4x4 {
        guard explodeFactor != 0, let entry = entries[id] else {
            return matrix_identity_float4x4
        }
        let offset = (entry.mesh.centre - sceneCentre) * explodeFactor
        return float4x4(translation: offset)
    }

    // MARK: View commands (store-side state)

    /// Apply a view command to the store's own state — the single
    /// implementation behind CascadeRenderer.apply, the console's
    /// `view ...` commands and (v0.3.2) the View panel. Returns
    /// false for the commands the store does not own — screenshots
    /// (GPU readback) and the renderer's face/edge label flags —
    /// so the caller handles exactly those itself. Extracted from
    /// CascadeRenderer.apply in v0.3.2 so the Swift harness, which
    /// compiles this file, executes the panel's real state
    /// transitions instead of a copy of them.
    @discardableResult
    public func apply(_ command: ViewerCommand) -> Bool {
        switch command {
        case .fit:
            fitCamera()
        case .standardView(let view):
            camera.setStandardView(view)
        case .displayMode(let mode):
            displayMode = mode
        case .setSection(let plane):
            section = plane
        case .setExplode(let factor):
            explodeFactor = max(0, factor)
        case .setMeasureEnabled(let on):
            measureEnabled = on
            if !on { clearMeasure() }
        case .clearMeasure:
            clearMeasure()
        case .setCameraRotation(let azimuthDeg, let elevationDeg):
            camera.setRotation(azimuthDegrees: azimuthDeg,
                               elevationDegrees: elevationDeg)
        case .rotateCameraBy(let dAzimuthDeg, let dElevationDeg):
            camera.rotateBy(azimuthDegrees: dAzimuthDeg,
                            elevationDegrees: dElevationDeg)
        case .setGridVisible(let on):
            gridVisible = on
        case .setAxesVisible(let on):
            axesVisible = on
        case .setBackground(let top, let bottom):
            backgroundTop = top
            backgroundBottom = bottom
        case .setProjection(let mode):
            camera.projection = mode
        case .setObjectVisible(let id, let on):
            mutateProps(id: id) { $0.isVisible = on }
        case .setObjectOpacity(let id, let value):
            mutateProps(id: id) { $0.opacity = min(1, max(0, value)) }
        case .setObjectColor(let id, let color):
            mutateProps(id: id) { $0.color = color }
        case .resetCamera:
            camera = OrbitCamera()
            fitCamera()
        case .screenshot, .setFaceLabelsEnabled, .setEdgeLabelsEnabled:
            return false
        }
        return true
    }

    // MARK: Measure

    public var measureDistance: Float? {
        guard measurePoints.count == 2 else { return nil }
        return simd_distance(measurePoints[0], measurePoints[1])
    }

    public func addMeasurePoint(_ p: SIMD3<Float>) {
        if measurePoints.count >= 2 { measurePoints.removeAll() }
        measurePoints.append(p)
    }

    public func clearMeasure() { measurePoints.removeAll() }

    // MARK: Picking (CPU ray vs triangles, Moller-Trumbore)

    /// Build a world-space ray through a view point. View points are in
    /// points with origin at the TOP-LEFT, y down (both platforms'
    /// gesture coordinates); NDC y is flipped here, once.
    public func ray(at viewPoint: SIMD2<Float>, viewSize: SIMD2<Float>) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let aspect = viewSize.x / max(viewSize.y, 1)
        let ndc = SIMD2<Float>((viewPoint.x / max(viewSize.x, 1)) * 2 - 1,
                               1 - (viewPoint.y / max(viewSize.y, 1)) * 2)
        let invProj = camera.projectionMatrix(aspect: aspect).inverse
        let invView = camera.viewMatrix().inverse
        // Unproject a near and a far point, then take the direction.
        let nearClip = SIMD4<Float>(ndc.x, ndc.y, 0, 1)
        let farClip = SIMD4<Float>(ndc.x, ndc.y, 1, 1)
        var nearView = invProj * nearClip; nearView /= nearView.w
        var farView = invProj * farClip; farView /= farView.w
        let nearWorld = invView * nearView
        let farWorld = invView * farView
        let origin = SIMD3<Float>(nearWorld.x, nearWorld.y, nearWorld.z)
        let farP = SIMD3<Float>(farWorld.x, farWorld.y, farWorld.z)
        return (origin, simd_normalize(farP - origin))
    }

    public func pick(at viewPoint: SIMD2<Float>, viewSize: SIMD2<Float>) -> PickResult? {
        let (origin, dir) = ray(at: viewPoint, viewSize: viewSize)
        var best: PickResult?
        var bestT = Float.greatestFiniteMagnitude
        for id in order {
            guard let entry = entries[id], entry.props.isVisible else { continue }
            let model = modelMatrix(for: id)
            let mesh = entry.mesh
            var i = 0
            while i + 2 < mesh.indices.count {
                let a = transformed(mesh.vertices[Int(mesh.indices[i])].position, by: model)
                let b = transformed(mesh.vertices[Int(mesh.indices[i + 1])].position, by: model)
                let c = transformed(mesh.vertices[Int(mesh.indices[i + 2])].position, by: model)
                if let t = rayTriangle(origin: origin, dir: dir, a: a, b: b, c: c),
                   t > 0, t < bestT {
                    bestT = t
                    let face = mesh.faceGroups.first {
                        Int($0.indexStart) <= i && i < Int($0.indexStart + $0.indexCount)
                    }
                    best = PickResult(objectID: id,
                                      point: origin + dir * t,
                                      distanceFromCamera: t,
                                      sourceFaceIndex: face?.sourceFaceIndex)
                }
                i += 3
            }
        }
        return best
    }

    private func transformed(_ p: SIMD3<Float>, by m: float4x4) -> SIMD3<Float> {
        let v = m * SIMD4<Float>(p.x, p.y, p.z, 1)
        return SIMD3<Float>(v.x, v.y, v.z)
    }

    private func rayTriangle(origin: SIMD3<Float>, dir: SIMD3<Float>,
                             a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) -> Float? {
        let e1 = b - a
        let e2 = c - a
        let p = simd_cross(dir, e2)
        let det = simd_dot(e1, p)
        guard abs(det) > 1e-9 else { return nil }
        let invDet = 1 / det
        let tVec = origin - a
        let u = simd_dot(tVec, p) * invDet
        guard u >= 0, u <= 1 else { return nil }
        let q = simd_cross(tVec, e1)
        let v = simd_dot(dir, q) * invDet
        guard v >= 0, u + v <= 1 else { return nil }
        let t = simd_dot(e2, q) * invDet
        return t > 0 ? t : nil
    }
}
