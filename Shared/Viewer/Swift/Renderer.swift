//
//  Renderer.swift
//  Cascade Console - Viewer
//
//  Metal renderer + ViewerBridge implementation. Shared verbatim by the
//  macOS and iPad apps; platform differences live only in
//  CascadeMetalView.swift (gestures / view hosting).
//
//  Rendering model: pre-tessellated triangle buffers from the core,
//  direct lighting in the shader, no ray tracing. GPU buffers are
//  uploaded once per (objectID, geometryVersion) and reused until the
//  core bumps the version - camera moves only rewrite a 176-byte
//  uniform buffer per object per frame.
//

import Foundation
import Metal
import MetalKit
import ImageIO
import CoreGraphics
import simd

// Must match `Uniforms` in Shaders.metal field-for-field.
private struct MeshUniforms {
    var mvp: float4x4
    var model: float4x4
    var color: SIMD4<Float>
    var sectionPlane: SIMD4<Float>
    var sectionEnabled: UInt32
    var padding0: UInt32 = 0
    var padding1: UInt32 = 0
    var padding2: UInt32 = 0
}

private struct LineUniforms { var mvp: float4x4 }
private struct BackgroundUniforms { var top: SIMD4<Float>; var bottom: SIMD4<Float> }

// LineVertex lives in SceneHelpers.swift (pure, harness-compiled)
// with its layout constants derived from MemoryLayout. v0.2.3 and
// earlier kept it here with a hand-written "offset 16, stride 32"
// comment that did not match the type's real layout (48/32) — the
// line-path twin of the v0.2.3 mesh bug, and the cause of the fan in
// the v0.2.3 device verdict. See SceneHelpers.swift / FIXLOG v0.2.4.

public final class CascadeRenderer: NSObject, ViewerBridge {
    public weak var delegate: ViewerBridgeDelegate?

    public let store = SceneStore()
    private let device: MTLDevice
    /// The device CascadeMetalView must be created with.
    public var metalDevice: MTLDevice { device }
    private let commandQueue: MTLCommandQueue
    private var meshPipeline: MTLRenderPipelineState!
    private var meshWirePipeline: MTLRenderPipelineState!
    private var linePipeline: MTLRenderPipelineState!
    private var backgroundPipeline: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!
    private var depthStateNoWrite: MTLDepthStencilState!
    private var depthStateAlways: MTLDepthStencilState!

    private struct GPUObject {
        var version: UInt64
        var vertexBuffer: MTLBuffer
        var indexBuffer: MTLBuffer
        var indexCount: Int
        var edgeBuffer: MTLBuffer?      // built lazily for edge modes
        var edgeCount: Int = 0
    }
    private var gpuObjects: [String: GPUObject] = [:]
    private var gridBuffer: MTLBuffer?
    private var gridCount = 0
    private var gridKey: String = ""

    public init?(device: MTLDevice? = nil) {
        guard let device = device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()
        buildPipelines()
    }

    // MARK: Pipelines

    private func buildPipelines() {
        // Default library first (app targets); fall back to the viewer's
        // own bundle when the viewer ships inside a framework target.
        let library = device.makeDefaultLibrary()
            ?? (try? device.makeDefaultLibrary(bundle: Bundle(for: CascadeRenderer.self)))
        guard let library else {
            delegate?.viewer(self, didFailWith: "Metal default library missing (Shaders.metal not in bundle)")
            return
        }
        let meshDesc = MTLVertexDescriptor()
        meshDesc.attributes[0].format = .float3
        meshDesc.attributes[0].offset = 0
        meshDesc.attributes[0].bufferIndex = 0
        meshDesc.attributes[1].format = .float3
        // The vertex buffer is the raw memory of [MeshVertex]
        // (see upload(_:)), so the descriptor must describe THAT
        // layout — bufferStride / bufferNormalOffset (32 / 16),
        // never the packed CCM1 file stride (24 / 12). v0.2.3 fix.
        meshDesc.attributes[1].offset = MeshVertex.bufferNormalOffset
        meshDesc.attributes[1].bufferIndex = 0
        meshDesc.layouts[0].stride = MeshVertex.bufferStride
        meshDesc.layouts[0].stepFunction = .perVertex

        // Fill vs wireframe is an encoder state (setTriangleFillMode),
        // not a pipeline property, so one pipeline serves both modes.
        func makeMeshPipeline() -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "meshVertex")
            d.fragmentFunction = library.makeFunction(name: "meshFragment")
            d.vertexDescriptor = meshDesc
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            d.depthAttachmentPixelFormat = .depth32Float
            // Blending configured per-draw via a second descriptor would
            // need separate pipelines; transparency uses the same pipeline
            // with blending enabled here and alpha 1 for opaque objects.
            d.colorAttachments[0].isBlendingEnabled = true
            d.colorAttachments[0].rgbBlendOperation = .add
            d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        meshPipeline = makeMeshPipeline()
        meshWirePipeline = meshPipeline

        let lineDesc = MTLVertexDescriptor()
        lineDesc.attributes[0].format = .float3
        lineDesc.attributes[0].offset = 0
        lineDesc.attributes[0].bufferIndex = 0
        lineDesc.attributes[1].format = .float4
        // The line buffers hold [LineVertex] in its memory layout, so
        // the descriptor declares THAT layout via the MemoryLayout-
        // derived constants (48/32) — never hand-written numbers.
        // v0.2.3 shipped 32/16 here: the GPU strode 32 bytes through
        // 48-byte records and drew the fan (FIXLOG v0.2.4).
        lineDesc.attributes[1].offset = LineVertex.bufferColorOffset
        lineDesc.attributes[1].bufferIndex = 0
        lineDesc.layouts[0].stride = LineVertex.bufferStride
        lineDesc.layouts[0].stepFunction = .perVertex
        let ld = MTLRenderPipelineDescriptor()
        ld.vertexFunction = library.makeFunction(name: "lineVertex")
        ld.fragmentFunction = library.makeFunction(name: "lineFragment")
        ld.vertexDescriptor = lineDesc
        ld.colorAttachments[0].pixelFormat = .bgra8Unorm
        ld.depthAttachmentPixelFormat = .depth32Float
        linePipeline = try? device.makeRenderPipelineState(descriptor: ld)

        let bd = MTLRenderPipelineDescriptor()
        bd.vertexFunction = library.makeFunction(name: "backgroundVertex")
        bd.fragmentFunction = library.makeFunction(name: "backgroundFragment")
        bd.colorAttachments[0].pixelFormat = .bgra8Unorm
        bd.depthAttachmentPixelFormat = .depth32Float
        backgroundPipeline = try? device.makeRenderPipelineState(descriptor: bd)

        let dd = MTLDepthStencilDescriptor()
        dd.depthCompareFunction = .less
        dd.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: dd)
        let dd2 = MTLDepthStencilDescriptor()
        dd2.depthCompareFunction = .less
        dd2.isDepthWriteEnabled = false
        depthStateNoWrite = device.makeDepthStencilState(descriptor: dd2)
        let dd3 = MTLDepthStencilDescriptor()
        dd3.depthCompareFunction = .always   // background sits at far plane (depth == clear value)
        dd3.isDepthWriteEnabled = false
        depthStateAlways = device.makeDepthStencilState(descriptor: dd3)
    }

    // MARK: ViewerBridge - scene data

    public func loadMesh(_ object: MeshObject, props: ObjectDisplayProps) {
        let changed = store.load(object, props: props)
        if changed { upload(object) }
    }

    public func updateObjectProps(id: String, props: ObjectDisplayProps) {
        store.setProps(id: id, props: props)
    }

    public func removeObject(id: String) {
        store.remove(id: id)
        gpuObjects[id] = nil
    }

    public func clearScene() {
        store.clear()
        gpuObjects.removeAll()
        gridBuffer = nil
        gridKey = ""
    }

    /// Face-number labels (v0.2): when on, each face of each visible
    /// object gets a text chip at its centroid showing its census
    /// face index (MeshObject.faceGroups' sourceFaceIndex — the same
    /// number @face <n> accepts). Default off. Overlay rendering
    /// runs on both platforms since v0.3.1 (see updateFaceLabels).
    public var faceLabelsEnabled: Bool = false

    /// Edge-number labels (v0.2.4): when on, each census edge of each
    /// visible object gets a text chip at its midpoint showing its
    /// census edge index (MeshObject.edges' edgeIndex — the same
    /// number `fillet/chamfer ... edges i,j,...` accepts). Default
    /// off. Same both-platform overlay as face labels (v0.3.1).
    public var edgeLabelsEnabled: Bool = false

    public var objectIDs: [String] { store.order }
    public func props(id: String) -> ObjectDisplayProps? { store.entries[id]?.props }
    public var displayMode: DisplayMode { store.displayMode }
    public var projectionMode: ProjectionMode { store.camera.projection }
    public var explodeFactor: Float { store.explodeFactor }
    public var sectionPlane: SectionPlane? { store.section }

    public func pick(at viewPoint: SIMD2<Float>, viewSize: SIMD2<Float>) -> PickResult? {
        let result = store.pick(at: viewPoint, viewSize: viewSize)
        if store.measureEnabled, let result {
            store.addMeasurePoint(result.point)
            delegate?.viewer(self, measureDistanceChanged: store.measureDistance)
        }
        delegate?.viewer(self, didPick: result)
        return result
    }

    // MARK: ViewerBridge - commands

    public func apply(_ command: ViewerCommand) {
        switch command {
        case .fit:
            store.fitCamera()
        case .standardView(let view):
            store.camera.setStandardView(view)
        case .displayMode(let mode):
            store.displayMode = mode
        case .setSection(let plane):
            store.section = plane
        case .setExplode(let factor):
            store.explodeFactor = max(0, factor)
        case .screenshot(let path, let width, let height):
            writeScreenshot(path: path, width: width, height: height)
        case .setMeasureEnabled(let on):
            store.measureEnabled = on
            if !on { store.clearMeasure() }
        case .clearMeasure:
            store.clearMeasure()
            delegate?.viewer(self, measureDistanceChanged: nil)
        case .setFaceLabelsEnabled(let on):
            faceLabelsEnabled = on
        case .setEdgeLabelsEnabled(let on):
            edgeLabelsEnabled = on
        case .setCameraRotation(let azimuthDeg, let elevationDeg):
            store.camera.setRotation(azimuthDegrees: azimuthDeg,
                                     elevationDegrees: elevationDeg)
        case .rotateCameraBy(let dAzimuthDeg, let dElevationDeg):
            store.camera.rotateBy(azimuthDegrees: dAzimuthDeg,
                                  elevationDegrees: dElevationDeg)
        case .setGridVisible(let on):
            store.gridVisible = on
        case .setAxesVisible(let on):
            store.axesVisible = on
        case .setBackground(let top, let bottom):
            store.backgroundTop = top
            store.backgroundBottom = bottom
        case .setProjection(let mode):
            store.camera.projection = mode
        case .setObjectVisible(let id, let on):
            store.mutateProps(id: id) { $0.isVisible = on }
        case .setObjectOpacity(let id, let value):
            store.mutateProps(id: id) { $0.opacity = min(1, max(0, value)) }
        case .setObjectColor(let id, let color):
            store.mutateProps(id: id) { $0.color = color }
        case .resetCamera:
            store.camera = OrbitCamera()
            store.fitCamera()
        }
        delegate?.viewerDidChangeCamera(self)
    }

    // MARK: GPU upload (once per geometry version)

    private func upload(_ object: MeshObject) {
        // makeBuffer(bytes:) takes an UnsafeRawPointer, not a Data -
        // pass each array's raw base address straight through. The
        // vertex buffer therefore holds [MeshVertex] in its memory
        // layout (stride 32, normal at 16); buildPipelines' vertex
        // descriptor declares exactly that via MeshVertex.bufferStride
        // / bufferNormalOffset. (v0.2.2 declared the CCM1 file layout
        // instead and the GPU fetched garbage — FIXLOG v0.2.3.)
        guard let vb = object.vertices.withUnsafeBytes({ raw in
                  device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared) }),
              let ib = object.indices.withUnsafeBytes({ raw in
                  device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared) })
        else {
            delegate?.viewer(self, didFailWith: "Metal buffer allocation failed for \(object.id)")
            return
        }
        gpuObjects[object.id] = GPUObject(version: object.geometryVersion,
                                          vertexBuffer: vb, indexBuffer: ib,
                                          indexCount: object.indices.count)
    }

    private func edgeBuffer(for id: String, mesh: MeshObject) -> (MTLBuffer, Int)? {
        if let existing = gpuObjects[id]?.edgeBuffer, let count = gpuObjects[id]?.edgeCount {
            return (existing, count)
        }
        // Unique undirected edges of the triangle soup (production
        // builder in SceneHelpers.swift — the CI harness runs it).
        let lines = SceneLineBuilder.meshEdgeLines(vertices: mesh.vertices,
                                                   indices: mesh.indices)
        guard let buffer = device.makeBuffer(bytes: lines,
                                             length: lines.count * LineVertex.bufferStride,
                                             options: .storageModeShared) else { return nil }
        gpuObjects[id]?.edgeBuffer = buffer
        gpuObjects[id]?.edgeCount = lines.count
        return (buffer, lines.count)
    }

    // MARK: Grid + axes (rebuilt only when bounds or visibility change)

    private func rebuildGridIfNeeded() {
        guard let (lo, hi) = store.sceneBounds else { return }
        // The cache key covers EVERYTHING the built buffer depends on:
        // the full bounds (grid extent + arrow length derive from
        // them) and both visibility flags. Pre-v0.2.4 the key held
        // only extent + lo.x/lo.y and the grid was built
        // unconditionally, so `view grid off` changed nothing and
        // toggling axes never rebuilt — the flags are in the key and
        // gate the builders now.
        let key = "\(store.gridVisible)|\(store.axesVisible)|\(lo.x)|\(lo.y)|\(lo.z)|\(hi.x)|\(hi.y)|\(hi.z)"
        if key == gridKey, gridBuffer != nil { return }
        gridKey = key
        var lines: [LineVertex] = []
        if store.gridVisible {
            lines += SceneLineBuilder.gridLines(lo: lo, hi: hi, centre: store.sceneCentre)
        }
        if store.axesVisible {
            // Compact arrows at the origin (v0.2.4), ~20% of the
            // scene diagonal — NOT the old full-length lines, which
            // ran 1.2x the scene extent and crossed the model.
            lines += SceneLineBuilder.axisArrowLines(
                diagonal: SceneLineBuilder.sceneDiagonal(lo: lo, hi: hi))
        }
        gridBuffer = device.makeBuffer(bytes: lines, length: lines.count * LineVertex.bufferStride,
                                       options: .storageModeShared)
        gridCount = lines.count
    }

    // MARK: Drawing

    public func drawScene(encoder: MTLRenderCommandEncoder,
                          viewProjection: float4x4, viewSize: SIMD2<Float>) {
        // Background
        if let backgroundPipeline {
            encoder.setRenderPipelineState(backgroundPipeline)
            encoder.setDepthStencilState(depthStateAlways)
            var bg = BackgroundUniforms(top: store.backgroundTop, bottom: store.backgroundBottom)
            encoder.setVertexBytes(&bg, length: MemoryLayout<BackgroundUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&bg, length: MemoryLayout<BackgroundUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        let mode = store.displayMode
        // Partition visible objects into opaque and transparent passes.
        var opaque: [(String, SceneStore.Entry)] = []
        var transparent: [(String, SceneStore.Entry)] = []
        for id in store.order {
            guard let entry = store.entries[id], entry.props.isVisible,
                  gpuObjects[id] != nil else { continue }
            let effectiveOpacity = mode == .xray ? entry.props.opacity * 0.25
                                                   : entry.props.opacity
            if effectiveOpacity >= 0.999 && mode != .xray {
                opaque.append((id, entry))
            } else {
                transparent.append((id, entry))
            }
        }
        // Transparent pass: back-to-front by centre distance to camera.
        let eye = store.camera.eyePosition
        transparent.sort {
            simd_distance(store.entries[$0.0]?.mesh.centre ?? .zero, eye) >
            simd_distance(store.entries[$1.0]?.mesh.centre ?? .zero, eye)
        }

        func drawObject(id: String, entry: SceneStore.Entry, depthWrite: Bool) {
            guard let gpu = gpuObjects[id] else { return }
            let model = store.modelMatrix(for: id)
            let opacity = mode == .xray ? entry.props.opacity * 0.25 : entry.props.opacity
            var color = entry.props.color
            color.w = opacity
            var plane = SIMD4<Float>(0, 0, 0, 0)
            if let s = store.section, s.isEnabled {
                plane = SIMD4<Float>(s.normal.x, s.normal.y, s.normal.z, s.constant)
            }
            var uniforms = MeshUniforms(
                mvp: viewProjection * model,
                model: model,
                color: color,
                sectionPlane: plane,
                sectionEnabled: (store.section?.isEnabled ?? false) ? 1 : 0)
            encoder.setDepthStencilState(depthWrite ? depthState : depthStateNoWrite)
            encoder.setRenderPipelineState(meshPipeline)
            encoder.setTriangleFillMode(mode == .wireframe ? .lines : .fill)
            encoder.setVertexBuffer(gpu.vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<MeshUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MeshUniforms>.stride, index: 1)
            encoder.drawIndexedPrimitives(type: .triangle,
                                          indexCount: gpu.indexCount,
                                          indexType: .uint32,
                                          indexBuffer: gpu.indexBuffer,
                                          indexBufferOffset: 0)
            if (mode == .shadedWithEdges || entry.props.showEdges) && mode != .wireframe {
                if let (buffer, count) = edgeBuffer(for: id, mesh: entry.mesh) {
                    var lu = LineUniforms(mvp: viewProjection * model)
                    encoder.setRenderPipelineState(linePipeline)
                    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                    encoder.setVertexBytes(&lu, length: MemoryLayout<LineUniforms>.stride, index: 1)
                    encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: count)
                }
            }
        }

        for (id, entry) in opaque { drawObject(id: id, entry: entry, depthWrite: true) }
        for (id, entry) in transparent { drawObject(id: id, entry: entry, depthWrite: false) }

        // Grid + axes + measure lines
        if store.gridVisible || store.axesVisible {
            rebuildGridIfNeeded()
            if let gridBuffer {
                var lu = LineUniforms(mvp: viewProjection)
                encoder.setRenderPipelineState(linePipeline)
                encoder.setDepthStencilState(depthStateNoWrite)
                encoder.setVertexBuffer(gridBuffer, offset: 0, index: 0)
                encoder.setVertexBytes(&lu, length: MemoryLayout<LineUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gridCount)
            }
        }
        if store.measurePoints.count == 2 {
            let yellow = SIMD4<Float>(1, 0.85, 0.2, 1)
            let pts = [LineVertex(store.measurePoints[0], yellow),
                       LineVertex(store.measurePoints[1], yellow)]
            var lu = LineUniforms(mvp: viewProjection)
            encoder.setRenderPipelineState(linePipeline)
            encoder.setDepthStencilState(depthStateNoWrite)
            encoder.setVertexBytes(pts, length: pts.count * LineVertex.bufferStride, index: 0)
            encoder.setVertexBytes(&lu, length: MemoryLayout<LineUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 2)
        }
    }

    // MARK: Screenshot / render to PNG

    public func writeScreenshot(path: String, width: Int, height: Int) {
        let w = max(width, 1), h = max(height, 1)
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        depthDesc.usage = [.renderTarget]
        depthDesc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: texDesc),
              let depth = device.makeTexture(descriptor: depthDesc),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            delegate?.viewer(self, didFailWith: "screenshot: could not allocate render target")
            return
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            delegate?.viewer(self, didFailWith: "screenshot: could not create encoder")
            return
        }
        let aspect = Float(w) / Float(h)
        let vp = store.camera.projectionMatrix(aspect: aspect) * store.camera.viewMatrix()
        drawScene(encoder: encoder, viewProjection: vp,
                  viewSize: SIMD2<Float>(Float(w), Float(h)))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytesPerRow = w * 4
        var raw = [UInt8](repeating: 0, count: bytesPerRow * h)
        texture.getBytes(&raw, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(raw) as CFData),
              let image = CGImage(width: w, height: h,
                                  bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue:
                                    CGImageAlphaInfo.premultipliedFirst.rawValue |
                                    CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
        else {
            delegate?.viewer(self, didFailWith: "screenshot: PNG encode failed")
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) {
            delegate?.viewer(self, didWriteScreenshotTo: path)
        } else {
            delegate?.viewer(self, didFailWith: "screenshot: could not write \(path)")
        }
    }
}

// MARK: - MTKViewDelegate

extension CascadeRenderer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let size = SIMD2<Float>(Float(view.drawableSize.width),
                                Float(view.drawableSize.height))
        let aspect = size.x / max(size.y, 1)
        let vp = store.camera.projectionMatrix(aspect: aspect) * store.camera.viewMatrix()
        drawScene(encoder: encoder, viewProjection: vp, viewSize: size)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        updateFaceLabels(in: view, viewProjection: vp)
        updateEdgeAndAxisLabels(in: view, viewProjection: vp)
    }
}

// MARK: - Face-number labels (v0.2)
//
// CATextLayer chips hosted on the MTKView's layer, repositioned every
// frame from the same view-projection the renderer just drew with, so
// they track orbit/zoom exactly. Anchors come from the MeshObject
// face groups: centroid of the group's vertices, offset along the
// group's mean normal. A label hides when its face points away from
// the camera (dot(normal, viewDir) <= 0.15) or behind the camera.
// Contrast per the user's vision needs: near-black text on a solid
// near-white chip, 14 pt semibold — never small grey text.
//
// macOS port (v0.3.1): the chips were iOS-only through v0.3.0. The
// port is deliberately small — CATextLayer exists on both platforms;
// the only UIKit surface was the font, the colours, the contents
// scale and the layer origin. Those four are shimmed below
// (ChipFont / ChipColor / chipContentsScale / chipFrame). Chip
// centres are produced in the bridge's top-left-origin screen
// convention; UIKit layers share that origin, AppKit layers are
// bottom-left, so chipFrame flips exactly once on macOS — the same
// flip-once convention CascadeMetalView applies to picking.

#if os(iOS) || os(macOS)
import QuartzCore
#if os(iOS)
import UIKit
private typealias ChipFont = UIFont
private typealias ChipColor = UIColor
#else
import AppKit
private typealias ChipFont = NSFont
private typealias ChipColor = NSColor
#endif

/// The layer the chips are hosted on. UIKit's is non-optional;
/// AppKit's is an Optional (an MTKView always has its CAMetalLayer
/// in practice, but the port does not force-unwrap it).
private func chipHostLayer(_ view: MTKView) -> CALayer? {
    view.layer
}

/// Contents scale for text chips: UIKit exposes it on the view;
/// AppKit takes it from the window's backing scale factor.
private func chipContentsScale(_ view: MTKView) -> CGFloat {
    #if os(iOS)
    view.contentScaleFactor
    #else
    view.window?.backingScaleFactor ?? 2.0
    #endif
}

/// Frame for a chip centred on `center` (22 pt tall), flipping the
/// y axis once on macOS (see the section note above).
private func chipFrame(center: CGPoint, width: CGFloat, viewHeight: CGFloat) -> CGRect {
    #if os(iOS)
    CGRect(x: center.x - width / 2, y: center.y - 11, width: width, height: 22)
    #else
    CGRect(x: center.x - width / 2, y: viewHeight - center.y - 11, width: width, height: 22)
    #endif
}

private var faceLabelStorage: [ObjectIdentifier: [String: CATextLayer]] = [:]

extension CascadeRenderer {
    private var labelLayers: [String: CATextLayer] {
        get { faceLabelStorage[ObjectIdentifier(self)] ?? [:] }
        set { faceLabelStorage[ObjectIdentifier(self)] = newValue }
    }

    func updateFaceLabels(in view: MTKView, viewProjection vp: float4x4) {
        var layers = labelLayers
        guard faceLabelsEnabled else {
            for (_, layer) in layers { layer.removeFromSuperlayer() }
            labelLayers = [:]
            return
        }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let host = chipHostLayer(view) else { return }
        let eye = store.camera.eyePosition
        var wanted: [String: (text: String, screen: CGPoint)] = [:]

        for id in store.order {
            guard let entry = store.entries[id], entry.props.isVisible else { continue }
            let mesh = entry.mesh
            let diag = simd_length(mesh.boundingBoxSize)
            let lift = max(0.05, 0.015 * diag)
            for group in mesh.faceGroups where group.vertexCount > 0 {
                let start = Int(group.vertexStart)
                let count = Int(group.vertexCount)
                guard start + count <= mesh.vertices.count else { continue }
                var centroid = SIMD3<Float>.zero
                var normal = SIMD3<Float>.zero
                for i in start..<(start + count) {
                    centroid += mesh.vertices[i].position
                    normal += mesh.vertices[i].normal
                }
                centroid /= Float(count)
                let nlen = simd_length(normal)
                guard nlen > 1e-6 else { continue }
                normal /= nlen
                let anchor = centroid + normal * lift
                let viewDir = eye - anchor
                guard simd_length(viewDir) > 1e-6,
                      simd_dot(normal, simd_normalize(viewDir)) > 0.15 else { continue }
                let clip = vp * SIMD4<Float>(anchor.x, anchor.y, anchor.z, 1)
                guard clip.w > 0 else { continue }
                let ndc = SIMD3<Float>(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
                guard ndc.z <= 1, abs(ndc.x) <= 1.1, abs(ndc.y) <= 1.1 else { continue }
                let screen = CGPoint(x: CGFloat(ndc.x * 0.5 + 0.5) * bounds.width,
                                     y: CGFloat(1 - (ndc.y * 0.5 + 0.5)) * bounds.height)
                wanted["\(id)#\(group.sourceFaceIndex)"] =
                    (text: "\(group.sourceFaceIndex)", screen: screen)
            }
        }

        for (key, layer) in layers where wanted[key] == nil {
            layer.removeFromSuperlayer()
            layers[key] = nil
        }
        let font = ChipFont.systemFont(ofSize: 14, weight: .semibold)
        for (key, item) in wanted {
            let layer = layers[key] ?? {
                let l = CATextLayer()
                l.alignmentMode = .center
                l.cornerRadius = 4
                l.contentsScale = chipContentsScale(view)
                host.addSublayer(l)
                layers[key] = l
                return l
            }()
            layer.string = item.text
            layer.font = font
            layer.fontSize = 14
            layer.foregroundColor = ChipColor.black.cgColor
            layer.backgroundColor = ChipColor.white.withAlphaComponent(0.92).cgColor
            let width = max(22, 12 + 9 * item.text.count)
            layer.frame = chipFrame(center: item.screen,
                                    width: CGFloat(width),
                                    viewHeight: bounds.height)
        }
        labelLayers = layers
    }
}

// MARK: - Edge-number labels + axis letters (v0.2.4)
//
// Same chip mechanism as the face labels, separate layer pool.
// Edge chips: black text on near-white, anchored at each census
// edge's midpoint (MeshObject.edges — the backend's own census from
// ccgeom_edge_list, so the number IS the `edges i,j,...` index).
// Facing: an edge has no single normal in the view data, so the test
// is radial — the chip shows when the midpoint's direction from the
// object's centre faces the camera (dot > 0.05). That is an
// approximation (a long edge can straddle the silhouette); it is the
// honest limit of endpoint-only data and is recorded in FIXLOG.
// Anchors are mesh-space, like the face labels (exact at explode 0).
// Axis chips: the letters X / Y / Z at the arrow tips, black text on
// the axis colour, shown whenever the arrows are (view axes on).

private var edgeLabelStorage: [ObjectIdentifier: [String: CATextLayer]] = [:]

extension CascadeRenderer {
    private var edgeLabelLayers: [String: CATextLayer] {
        get { edgeLabelStorage[ObjectIdentifier(self)] ?? [:] }
        set { edgeLabelStorage[ObjectIdentifier(self)] = newValue }
    }

    func updateEdgeAndAxisLabels(in view: MTKView, viewProjection vp: float4x4) {
        var layers = edgeLabelLayers
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let host = chipHostLayer(view) else { return }
        let eye = store.camera.eyePosition
        var wanted: [String: (text: String, screen: CGPoint, bg: CGColor)] = [:]

        func project(_ anchor: SIMD3<Float>) -> CGPoint? {
            let clip = vp * SIMD4<Float>(anchor.x, anchor.y, anchor.z, 1)
            guard clip.w > 0 else { return nil }
            let ndc = SIMD3<Float>(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
            guard ndc.z <= 1, abs(ndc.x) <= 1.1, abs(ndc.y) <= 1.1 else { return nil }
            return CGPoint(x: CGFloat(ndc.x * 0.5 + 0.5) * bounds.width,
                           y: CGFloat(1 - (ndc.y * 0.5 + 0.5)) * bounds.height)
        }

        if edgeLabelsEnabled {
            for id in store.order {
                guard let entry = store.entries[id], entry.props.isVisible else { continue }
                let mesh = entry.mesh
                for edge in mesh.edges {
                    let anchor = (edge.start + edge.end) / 2
                    let outward = anchor - mesh.centre
                    let viewDir = eye - anchor
                    guard simd_length(outward) > 1e-6, simd_length(viewDir) > 1e-6,
                          simd_dot(simd_normalize(outward), simd_normalize(viewDir)) > 0.05
                    else { continue }
                    guard let screen = project(anchor) else { continue }
                    wanted["\(id)#e\(edge.edgeIndex)"] =
                        (text: "\(edge.edgeIndex)", screen: screen,
                         bg: ChipColor.white.withAlphaComponent(0.92).cgColor)
                }
            }
        }

        if store.axesVisible, let (lo, hi) = store.sceneBounds {
            let diagonal = SceneLineBuilder.sceneDiagonal(lo: lo, hi: hi)
            for tipInfo in SceneLineBuilder.axisArrowTips(diagonal: diagonal) {
                guard let screen = project(tipInfo.tip) else { continue }
                let c = tipInfo.color
                wanted["axis:\(tipInfo.label)"] =
                    (text: tipInfo.label, screen: screen,
                     bg: ChipColor(red: CGFloat(c.x), green: CGFloat(c.y),
                                 blue: CGFloat(c.z), alpha: 0.95).cgColor)
            }
        }

        for (key, layer) in layers where wanted[key] == nil {
            layer.removeFromSuperlayer()
            layers[key] = nil
        }
        let font = ChipFont.systemFont(ofSize: 14, weight: .semibold)
        for (key, item) in wanted {
            let layer = layers[key] ?? {
                let l = CATextLayer()
                l.alignmentMode = .center
                l.cornerRadius = 4
                l.contentsScale = chipContentsScale(view)
                host.addSublayer(l)
                layers[key] = l
                return l
            }()
            layer.string = item.text
            layer.font = font
            layer.fontSize = 14
            layer.foregroundColor = ChipColor.black.cgColor
            layer.backgroundColor = item.bg
            let width = max(22, 12 + 9 * item.text.count)
            layer.frame = chipFrame(center: item.screen,
                                    width: CGFloat(width),
                                    viewHeight: bounds.height)
        }
        edgeLabelLayers = layers
    }
}
#endif
