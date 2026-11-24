//
//  SceneHelpers.swift
//  Cascade Console - Viewer
//
//  The line-vertex type and the PURE line builders for everything the
//  renderer draws with the line pipeline: the floor grid, the XYZ axis
//  arrows, and the per-object edge overlay. No Metal in this file, so
//  the CI Swift harness compiles it from production sources and runs
//  the builders against real engine data (see
//  Shared/Viewer/Verification/swift-harness).
//
//  WHY THIS FILE EXISTS (v0.2.4): LineVertex used to live privately in
//  Renderer.swift with a hand-written comment claiming "colour at
//  offset 16, stride 32", and the renderer's line vertex descriptor +
//  every line-buffer copy used those constants. They were wrong in
//  exactly the way v0.2.3's mesh constants were wrong: SIMD3<Float>
//  is 16-byte aligned with a 16-byte stride, so the real layout is
//  position @0 (16 bytes), padding @16, colour @32, stride 48. The
//  GPU strode 32 bytes per vertex through 48-byte records, reading
//  colours as positions (all components in [0,1] — a point inside the
//  unit cube at the origin) and positions as colours: on the default
//  scene 0 of 53 grid/axes segments survived intact and all 53 had an
//  endpoint collapsed to the origin — the fan of thin coloured lines
//  radiating from the box's origin corner in the v0.2.3 device
//  verdict (reproduced numerically, FIXLOG v0.2.4). The layout
//  constants below are derived from MemoryLayout, like MeshVertex's,
//  so they cannot drift from the type again.
//

import Foundation
import simd

/// One vertex of a line strip for the line pipeline.
public struct LineVertex: Equatable {
    public var position: SIMD3<Float>
    public var padding: Float = 0
    public var color: SIMD4<Float>
    public init(_ p: SIMD3<Float>, _ c: SIMD4<Float>) {
        position = p
        color = c
    }

    /// In-memory layout of LineVertex as an element of [LineVertex] —
    /// the ONLY layout the line vertex descriptor may declare and the
    /// ONLY byte count a line buffer copy may use. Derived from
    /// MemoryLayout (stride 48, colour at 32 on current toolchains).
    public static let bufferStride = MemoryLayout<LineVertex>.stride
    public static let bufferColorOffset = MemoryLayout<LineVertex>.offset(of: \.color)!
}

/// Pure builders for the line pipeline's vertex lists.
public enum SceneLineBuilder {

    // Axis colours — unchanged from the pre-v0.2.4 axis lines.
    public static let axisXColor = SIMD4<Float>(0.9, 0.25, 0.25, 1)
    public static let axisYColor = SIMD4<Float>(0.25, 0.85, 0.35, 1)
    public static let axisZColor = SIMD4<Float>(0.3, 0.45, 0.95, 1)
    public static let gridColor = SIMD4<Float>(0.35, 0.37, 0.40, 1)
    public static let edgeOverlayColor = SIMD4<Float>(0.08, 0.08, 0.09, 1)

    /// The fraction of the scene-bounds diagonal the axis arrows span
    /// (v0.2.4 design target: small enough never to cross the model —
    /// the pre-fix axis lines were `half` = 1.2x the scene extent).
    public static let axisArrowFraction: Float = 0.2
    /// Absolute floor for the arrow length so the arrows stay visible
    /// on sub-unit scenes before a fit.
    public static let axisArrowMinimum: Float = 0.5

    public static func sceneDiagonal(lo: SIMD3<Float>, hi: SIMD3<Float>) -> Float {
        simd_length(hi - lo)
    }

    /// Arrow length for a scene with the given bounds diagonal:
    /// `axisArrowFraction` of the diagonal, floored at the minimum.
    public static func axisArrowLength(diagonal: Float) -> Float {
        max(axisArrowFraction * diagonal, axisArrowMinimum)
    }

    /// The floor grid in the z=0 plane, centred on the scene centre —
    /// the exact construction the renderer has always used (extent /
    /// step / half math unchanged), extracted so CI executes it.
    public static func gridLines(lo: SIMD3<Float>, hi: SIMD3<Float>,
                                 centre: SIMD3<Float>) -> [LineVertex] {
        let size = hi - lo
        let extent = max(size.x, size.y, 10)
        let step: Float = pow(10, floor(log10(extent / 5)))
        let half = (extent * 1.2 / step).rounded() * step
        var lines: [LineVertex] = []
        var v = -half
        while v <= half {
            lines.append(LineVertex(SIMD3<Float>(centre.x - half, centre.y + v, 0), gridColor))
            lines.append(LineVertex(SIMD3<Float>(centre.x + half, centre.y + v, 0), gridColor))
            lines.append(LineVertex(SIMD3<Float>(centre.x + v, centre.y - half, 0), gridColor))
            lines.append(LineVertex(SIMD3<Float>(centre.x + v, centre.y + half, 0), gridColor))
            v += step
        }
        return lines
    }

    /// The three axis arrows for a scene: compact arrows anchored at
    /// the world origin, length from `axisArrowLength(diagonal:)`,
    /// each a shaft plus a cone arrowhead drawn as lines (4 spokes +
    /// a 4-segment base ring). 18 vertices per arrow, 54 total.
    public static func axisArrowLines(diagonal: Float) -> [LineVertex] {
        let length = axisArrowLength(diagonal: diagonal)
        var lines: [LineVertex] = []
        for (dir, color) in [(SIMD3<Float>(1, 0, 0), axisXColor),
                             (SIMD3<Float>(0, 1, 0), axisYColor),
                             (SIMD3<Float>(0, 0, 1), axisZColor)] {
            lines.append(contentsOf: arrow(origin: .zero, direction: dir,
                                           length: length, color: color))
        }
        return lines
    }

    /// Arrow tip positions + labels, for the X/Y/Z letter chips.
    public static func axisArrowTips(diagonal: Float)
        -> [(label: String, tip: SIMD3<Float>, color: SIMD4<Float>)] {
        let length = axisArrowLength(diagonal: diagonal)
        return [("X", SIMD3<Float>(length, 0, 0), axisXColor),
                ("Y", SIMD3<Float>(0, length, 0), axisYColor),
                ("Z", SIMD3<Float>(0, 0, length), axisZColor)]
    }

    /// One arrow as line vertices: shaft from `origin` to the cone
    /// base centre, then the cone (apex at the tip, base ring of
    /// radius 0.10 * length in the plane perpendicular to `direction`).
    public static func arrow(origin: SIMD3<Float>, direction: SIMD3<Float>,
                             length: Float, color: SIMD4<Float>) -> [LineVertex] {
        let dir = simd_normalize(direction)
        let tip = origin + dir * length
        let headLength = 0.3 * length
        let baseCentre = tip - dir * headLength
        let radius = 0.10 * length
        // Two unit vectors perpendicular to dir (dir is axis-aligned
        // for the scene arrows; the fallback keeps this total).
        let helper = abs(dir.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let p1 = simd_normalize(simd_cross(dir, helper))
        let p2 = simd_cross(dir, p1)
        let ring = [baseCentre + p1 * radius, baseCentre + p2 * radius,
                    baseCentre - p1 * radius, baseCentre - p2 * radius]
        var lines: [LineVertex] = [LineVertex(origin, color),
                                   LineVertex(baseCentre, color)]
        for point in ring {
            lines.append(LineVertex(tip, color))
            lines.append(LineVertex(point, color))
        }
        for i in ring.indices {
            lines.append(LineVertex(ring[i], color))
            lines.append(LineVertex(ring[(i + 1) % ring.count], color))
        }
        return lines
    }

    /// The edge overlay's line list: unique undirected edges of the
    /// triangle soup, extracted from the renderer so CI executes it.
    public static func meshEdgeLines(vertices: [MeshVertex], indices: [UInt32],
                                     color: SIMD4<Float> = edgeOverlayColor) -> [LineVertex] {
        var seen = Set<UInt64>()
        var lines: [LineVertex] = []
        var i = 0
        while i + 2 < indices.count {
            let tri = (indices[i], indices[i + 1], indices[i + 2])
            for (a, b) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                if seen.insert(key).inserted {
                    lines.append(LineVertex(vertices[Int(a)].position, color))
                    lines.append(LineVertex(vertices[Int(b)].position, color))
                }
            }
            i += 3
        }
        return lines
    }
}
