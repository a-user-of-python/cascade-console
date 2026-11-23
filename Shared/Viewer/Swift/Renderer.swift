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

private struct LineVertex {
    var position: SIMD3<Float>
    var padding: Float = 0          // keep colour at offset 16, stride 32
    var color: SIMD4<Float>
    init(_ p: SIMD3<Float>, _ c: SIMD4<Float>) { position = p; color = c }
}

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
        meshDesc.attributes[1].offset = 12
        meshDesc.attributes[1].bufferIndex = 0
        meshDesc.layouts[0].stride = MeshVertex.stride
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
        lineDesc.attributes[1].offset = 16
        lineDesc.attributes[1].bufferIndex = 0
        lineDesc.layouts[0].stride = 32
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
    /// number @face <n> accepts). Default off. Overlay rendering is
    /// iOS-only for now (see updateFaceLabels); the flag and command
    /// work on both platforms.
    public var faceLabelsEnabled: Bool = false

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
        // pass each array's raw base address straight through.
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
        // Unique undirected edges of the triangle soup.
        var seen = Set<UInt64>()
        var lines: [LineVertex] = []
        let edgeColor = SIMD4<Float>(0.08, 0.08, 0.09, 1)
        var i = 0
        while i + 2 < mesh.indices.count {
            let tri = (mesh.indices[i], mesh.indices[i + 1], mesh.indices[i + 2])
            for (a, b) in [(tri.0, tri.1), (tri.1, tri.2), (tri.2, tri.0)] {
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                if seen.insert(key).inserted {
                    lines.append(LineVertex(mesh.vertices[Int(a)].position, edgeColor))
                    lines.append(LineVertex(mesh.vertices[Int(b)].position, edgeColor))
                }
            }
            i += 3
        }
        guard let buffer = device.makeBuffer(bytes: lines,
                                             length: lines.count * 32,
                                             options: .storageModeShared) else { return nil }
        gpuObjects[id]?.edgeBuffer = buffer
        gpuObjects[id]?.edgeCount = lines.count
        return (buffer, lines.count)
    }

    // MARK: Grid + axes (rebuilt only when scene bounds change)

    private func rebuildGridIfNeeded() {
        guard let (lo, hi) = store.sceneBounds else { return }
        let size = hi - lo
        let extent = max(size.x, size.y, 10)
        let key = "\(Int(extent))|\(Int(lo.x))|\(Int(lo.y))"
        if key == gridKey, gridBuffer != nil { return }
        gridKey = key
        let step: Float = pow(10, floor(log10(extent / 5)))
        let half = (extent * 1.2 / step).rounded() * step
        let centre = store.sceneCentre
        let gridGrey = SIMD4<Float>(0.35, 0.37, 0.40, 1)
        var lines: [LineVertex] = []
        var v = -half
        while v <= half {
            lines.append(LineVertex(SIMD3<Float>(centre.x - half, centre.y + v, 0), gridGrey))
            lines.append(LineVertex(SIMD3<Float>(centre.x + half, centre.y + v, 0), gridGrey))
            lines.append(LineVertex(SIMD3<Float>(centre.x + v, centre.y - half, 0), gridGrey))
            lines.append(LineVertex(SIMD3<Float>(centre.x + v, centre.y + half, 0), gridGrey))
            v += step
        }
        if store.axesVisible {
            let len = half
            let origin = SIMD3<Float>.zero
            lines.append(LineVertex(origin, SIMD4<Float>(0.9, 0.25, 0.25, 1)))
            lines.append(LineVertex(SIMD3<Float>(len, 0, 0), SIMD4<Float>(0.9, 0.25, 0.25, 1)))
            lines.append(LineVertex(origin, SIMD4<Float>(0.25, 0.85, 0.35, 1)))
            lines.append(LineVertex(SIMD3<Float>(0, len, 0), SIMD4<Float>(0.25, 0.85, 0.35, 1)))
            lines.append(LineVertex(origin, SIMD4<Float>(0.3, 0.45, 0.95, 1)))
            lines.append(LineVertex(SIMD3<Float>(0, 0, len), SIMD4<Float>(0.3, 0.45, 0.95, 1)))
        }
        gridBuffer = device.makeBuffer(bytes: lines, length: lines.count * 32,
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
            encoder.setVertexBytes(pts, length: pts.count * 32, index: 0)
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
// iOS only in this pass: on macOS the flag/command exist but no chips
// are drawn (the Mac app does not use this renderer yet — see FIXLOG).

#if os(iOS)
import QuartzCore
import UIKit

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
        let host = view.layer
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
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        for (key, item) in wanted {
            let layer = layers[key] ?? {
                let l = CATextLayer()
                l.alignmentMode = .center
                l.cornerRadius = 4
                l.contentsScale = view.contentScaleFactor
                host.addSublayer(l)
                layers[key] = l
                return l
            }()
            layer.string = item.text
            layer.font = font
            layer.fontSize = 14
            layer.foregroundColor = UIColor.black.cgColor
            layer.backgroundColor = UIColor.white.withAlphaComponent(0.92).cgColor
            let width = max(22, 12 + 9 * item.text.count)
            layer.frame = CGRect(x: item.screen.x - CGFloat(width) / 2,
                                 y: item.screen.y - 11,
                                 width: CGFloat(width), height: 22)
        }
        labelLayers = layers
    }
}
#endif
