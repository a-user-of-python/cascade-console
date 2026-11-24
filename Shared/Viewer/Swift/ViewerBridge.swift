//
//  ViewerBridge.swift
//  Cascade Console - Viewer
//
//  THE protocol between the apps (macOS app, iPad app) and the viewer.
//  Both apps conform to this exact surface; the console/engine talk to
//  the viewer only through ViewerBridge. See ../README.md for the
//  normative description. Summary:
//
//   App -> Viewer : loadMesh / updateObjectProps / removeObject /
//                   clearScene / apply(ViewerCommand) / pick
//   Viewer -> App : ViewerBridgeDelegate callbacks (camera changed,
//                   object picked, measure updated, screenshot written,
//                   error) - all delivered on the main queue.
//

import Foundation
import simd

/// Per-object display properties. Geometry is separate (MeshObject);
/// changing any of these NEVER triggers re-tessellation.
public struct ObjectDisplayProps: Equatable {
    public var color: SIMD4<Float>          // RGBA, linear, a ignored unless transparent
    public var opacity: Float               // 1 = opaque
    public var isVisible: Bool
    public var showEdges: Bool              // per-object edge overlay override
    public init(color: SIMD4<Float> = SIMD4<Float>(0.75, 0.78, 0.82, 1),
                opacity: Float = 1, isVisible: Bool = true, showEdges: Bool = false) {
        self.color = color
        self.opacity = opacity
        self.isVisible = isVisible
        self.showEdges = showEdges
    }
}

public enum DisplayMode: String, Equatable, CaseIterable {
    case shaded                 // direct-lit shading only (no ray tracing, ever)
    case wireframe
    case shadedWithEdges
    case xray                   // everything at 25% opacity, depth-write off
    case transparent            // per-object opacity honoured, back-to-front
}

public enum StandardView: String, Equatable, CaseIterable {
    case top, bottom, front, back, left, right, iso
}

public enum ProjectionMode: String, Equatable {
    case perspective, orthographic
}

/// A clipping plane in world space: points with
/// dot(point, normal) + constant > 0 are clipped away.
public struct SectionPlane: Equatable {
    public var normal: SIMD3<Float>
    public var constant: Float
    public var isEnabled: Bool
    public init(normal: SIMD3<Float>, constant: Float, isEnabled: Bool = true) {
        self.normal = simd_normalize(normal)
        self.constant = constant
        self.isEnabled = isEnabled
    }
    /// Plane through `distance` along a principal axis, e.g. axis "z",
    /// distance 5 keeps z <= 5.
    public static func axis(_ axis: String, distance: Float) -> SectionPlane? {
        switch axis.lowercased() {
        case "x": return SectionPlane(normal: SIMD3<Float>(-1, 0, 0), constant: distance)
        case "y": return SectionPlane(normal: SIMD3<Float>(0, -1, 0), constant: distance)
        case "z": return SectionPlane(normal: SIMD3<Float>(0, 0, -1), constant: distance)
        default: return nil
        }
    }
}

/// Every view action the console can command. ViewCommands.swift parses
/// the user's text into these; apps may also construct them directly.
public enum ViewerCommand: Equatable {
    case fit
    case standardView(StandardView)
    case displayMode(DisplayMode)
    case setSection(SectionPlane?)          // nil disables
    case setExplode(factor: Float)          // 0 = assembled, 1 = parts at 2x offset
    case screenshot(path: String, width: Int, height: Int)
    case setMeasureEnabled(Bool)
    case clearMeasure
    case setGridVisible(Bool)
    case setAxesVisible(Bool)
    case setBackground(top: SIMD4<Float>, bottom: SIMD4<Float>)
    case setProjection(ProjectionMode)
    case setFaceLabelsEnabled(Bool)     // face-number labels (v0.2)
    case setEdgeLabelsEnabled(Bool)     // edge-number labels (v0.2.4)
    case setCameraRotation(azimuthDegrees: Float, elevationDegrees: Float)  // view rotate (v0.2.4)
    case rotateCameraBy(azimuthDegrees: Float, elevationDegrees: Float)     // view rotate by (v0.2.4)
    case setObjectVisible(id: String, Bool)
    case setObjectOpacity(id: String, Float)
    case setObjectColor(id: String, SIMD4<Float>)
    case resetCamera
}

public struct PickResult: Equatable {
    public var objectID: String
    public var point: SIMD3<Float>          // world space, model units
    public var distanceFromCamera: Float
    public var sourceFaceIndex: UInt32?     // via MeshFaceGroup lookup
}

public protocol ViewerBridgeDelegate: AnyObject {
    func viewerDidChangeCamera(_ viewer: ViewerBridge)
    func viewer(_ viewer: ViewerBridge, didPick result: PickResult?)
    func viewer(_ viewer: ViewerBridge, measureDistanceChanged distance: Float?)
    func viewer(_ viewer: ViewerBridge, didWriteScreenshotTo path: String)
    func viewer(_ viewer: ViewerBridge, didFailWith message: String)
}

/// The viewer's public face. Renderer + SceneStore implement this;
/// CascadeMetalView owns an instance and forwards gestures to it.
public protocol ViewerBridge: AnyObject {
    var delegate: ViewerBridgeDelegate? { get set }

    // Scene data (geometry arrives pre-tessellated from the core)
    func loadMesh(_ object: MeshObject, props: ObjectDisplayProps)
    func updateObjectProps(id: String, props: ObjectDisplayProps)
    func removeObject(id: String)
    func clearScene()

    // Commands
    func apply(_ command: ViewerCommand)

    // Queries
    var objectIDs: [String] { get }
    func props(id: String) -> ObjectDisplayProps?
    /// Ray pick at a view-space point (points, origin top-left of view).
    func pick(at viewPoint: SIMD2<Float>, viewSize: SIMD2<Float>) -> PickResult?

    /// Face-number labels on/off (default off). The numbers are the
    /// census face indices carried in MeshObject.faceGroups.
    var faceLabelsEnabled: Bool { get set }

    /// Edge-number labels on/off (default off, v0.2.4). The numbers
    /// are the census edge indices carried in MeshObject.edges — the
    /// indices `fillet/chamfer ... edges i,j,...` accept.
    var edgeLabelsEnabled: Bool { get set }

    // Live view state, for the console's `view status` report
    var displayMode: DisplayMode { get }
    var projectionMode: ProjectionMode { get }
    var explodeFactor: Float { get }
    var sectionPlane: SectionPlane? { get }
}
