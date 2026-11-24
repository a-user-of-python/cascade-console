//
//  Camera.swift
//  Cascade Console - Viewer
//
//  Orbit camera. Pure value type, no rendering dependencies, so both
//  apps and the console's `view status` can share it. Model space is
//  Z-up, right-handed (OCCT convention); the camera works in that space
//  directly - no axis conversion, so a "top" view is truly +Z down.
//

import Foundation
import simd

public struct OrbitCamera: Equatable {
    public var target: SIMD3<Float> = .zero
    /// Spherical orbit around target, radians. Azimuth 0 = looking from
    /// +Y (front), increasing counter-clockwise seen from above.
    public var azimuth: Float = .pi / 4
    /// Elevation above the XY plane, clamped to (-89.9°, +89.9°).
    public var elevation: Float = .pi / 6
    public var distance: Float = 100
    public var projection: ProjectionMode = .perspective
    public var fieldOfViewDegrees: Float = 45
    /// World height of the view when orthographic (set by fit).
    public var orthographicHeight: Float = 100

    public init() {}

    public var eyePosition: SIMD3<Float> {
        let ce = cos(elevation)
        let offset = SIMD3<Float>(sin(azimuth) * ce,
                                  cos(azimuth) * ce,
                                  sin(elevation)) * distance
        return target + offset
    }

    public var upVector: SIMD3<Float> {
        // Camera up: world +Z projected; flips only via elevation clamp,
        // which never reaches the poles, so this is always well-defined.
        SIMD3<Float>(-sin(azimuth) * sin(elevation),
                     -cos(azimuth) * sin(elevation),
                     cos(elevation))
    }

    public mutating func orbit(azimuthDelta: Float, elevationDelta: Float) {
        azimuth += azimuthDelta
        let limit: Float = 89.9 * .pi / 180
        elevation = min(limit, max(-limit, elevation + elevationDelta))
    }

    /// Absolute orbit position from degrees — `view rotate <az> <el>`
    /// (v0.2.4). Elevation clamps to the same pole limit as orbiting.
    public mutating func setRotation(azimuthDegrees: Float, elevationDegrees: Float) {
        azimuth = azimuthDegrees * .pi / 180
        let limit: Float = 89.9 * .pi / 180
        elevation = min(limit, max(-limit, elevationDegrees * .pi / 180))
    }

    /// Relative orbit from degrees — `view rotate by <dAz> <dEl>`
    /// (v0.2.4); identical semantics to orbit(azimuthDelta:...).
    public mutating func rotateBy(azimuthDegrees: Float, elevationDegrees: Float) {
        orbit(azimuthDelta: azimuthDegrees * .pi / 180,
              elevationDelta: elevationDegrees * .pi / 180)
    }

    /// Pan in the camera's screen plane. `scale` = world units per point.
    public mutating func pan(right: Float, up: Float, scale: Float) {
        let forward = simd_normalize(target - eyePosition)
        let rightVec = simd_normalize(simd_cross(forward, upVector))
        let upVec = simd_cross(rightVec, forward)
        target += (-rightVec * right + upVec * up) * scale
    }

    /// Multiplicative zoom; also scales the orthographic height so a
    /// projection toggle mid-gesture does not jump.
    public mutating func zoom(by factor: Float) {
        let f = max(factor, 0.0001)
        distance = min(1e7, max(0.001, distance / f))
        orthographicHeight = min(1e7, max(0.001, orthographicHeight / f))
    }

    /// World units per screen point at the target depth - the pan scale.
    public func worldPerPoint(viewHeightPoints: Float) -> Float {
        switch projection {
        case .orthographic:
            return orthographicHeight / max(viewHeightPoints, 1)
        case .perspective:
            let h = 2 * distance * tan(fieldOfViewDegrees * .pi / 360)
            return h / max(viewHeightPoints, 1)
        }
    }

    public mutating func setStandardView(_ view: StandardView) {
        switch view {
        case .top:    azimuth = .pi / 4; elevation = 89.9 * .pi / 180
        case .bottom: azimuth = .pi / 4; elevation = -89.9 * .pi / 180
        case .front:  azimuth = 0;       elevation = 0
        case .back:   azimuth = .pi;     elevation = 0
        case .left:   azimuth = -.pi / 2; elevation = 0
        case .right:  azimuth = .pi / 2; elevation = 0
        case .iso:    azimuth = .pi / 4; elevation = atan(1 / Float(2).squareRoot())
        }
    }

    /// Frame a bounding sphere: centre it and pick a distance/height
    /// that fits it vertically with a small margin.
    public mutating func fit(centre: SIMD3<Float>, radius: Float) {
        target = centre
        let r = max(radius, 0.001)
        let fitDistance = r / sin(fieldOfViewDegrees * .pi / 360) * 1.05
        distance = fitDistance
        orthographicHeight = 2 * r * 1.05
    }

    public func viewMatrix() -> float4x4 {
        float4x4(lookAtEye: eyePosition, centre: target, up: upVector)
    }

    public func projectionMatrix(aspect: Float) -> float4x4 {
        let aspect = max(aspect, 0.0001)
        switch projection {
        case .perspective:
            let near = max(distance / 1000, 0.001)
            let far = distance * 100 + 1000
            return float4x4(perspectiveFovDegrees: fieldOfViewDegrees,
                            aspect: aspect, near: near, far: far)
        case .orthographic:
            let h = orthographicHeight / 2
            let w = h * aspect
            let near = -distance * 10 - 1000
            let far = distance * 10 + 1000
            return float4x4(orthographicLeft: -w, right: w,
                            bottom: -h, top: h, near: near, far: far)
        }
    }
}

// MARK: - float4x4 helpers (column-major, matching Metal/simd)

public extension float4x4 {
    init(lookAtEye eye: SIMD3<Float>, centre: SIMD3<Float>, up: SIMD3<Float>) {
        let z = simd_normalize(eye - centre)            // backward
        let x = simd_normalize(simd_cross(up, z))       // right
        let y = simd_cross(z, x)                        // true up
        self.init(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)
        ))
    }

    init(perspectiveFovDegrees fov: Float, aspect: Float, near: Float, far: Float) {
        // Right-handed, matching the view matrix above and the OCCT
        // model space: the camera looks down -Z in view space, so
        // clip w must be -z_view (positive for everything in front),
        // and NDC z must run 0 at the near plane to 1 at the far
        // plane, INCREASING with distance, for the renderer's
        // less-than depth test to keep near surfaces on top.
        //
        // v0.2.1 shipped a LEFT-handed form here (w = +z_view, NDC z
        // decreasing with distance): every visible point had negative
        // clip w, which inverts the rasterizer's front/back facing
        // test, and the inverted depth let far surfaces win over near
        // ones — created geometry rendered inside-out ("inverted").
        // The mesh data was never wrong (signed-volume proven on both
        // engine backends); this matrix was the only inverted layer.
        // Guard: Shared/Viewer/Verification/verify_projection.py.
        let yScale = 1 / tan(fov * .pi / 360)
        let xScale = yScale / aspect
        let zScale = far / (near - far)          // negative
        self.init(columns: (
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, near * zScale, 0)
        ))
    }

    init(orthographicLeft l: Float, right r: Float, bottom b: Float,
         top t: Float, near n: Float, far f: Float) {
        // Metal NDC z is [0, 1]. View space is right-handed (camera
        // looks down -Z), so depth must DECREASE as view z increases:
        // the far end of the slab (view z = n, the negative bound the
        // caller passes) maps to 1 and the near end to 0, keeping the
        // less-than depth test correct. The pre-v0.2.2 form had the
        // opposite slope and inverted depth the same way the old
        // perspective matrix did.
        self.init(columns: (
            SIMD4<Float>(2 / (r - l), 0, 0, 0),
            SIMD4<Float>(0, 2 / (t - b), 0, 0),
            SIMD4<Float>(0, 0, -1 / (f - n), 0),
            SIMD4<Float>(-(r + l) / (r - l), -(t + b) / (t - b), f / (f - n), 1)
        ))
    }

    init(translation t: SIMD3<Float>) {
        self.init(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        ))
    }
}
