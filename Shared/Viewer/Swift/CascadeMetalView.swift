//
//  CascadeMetalView.swift
//  Cascade Console - Viewer
//
//  The one platform-specific file. Everything else (renderer, camera,
//  scene, commands) is shared verbatim between macOS and iOS.
//
//  Controls (identical mental model on both platforms):
//    orbit : left-drag (mouse)        / one-finger drag (touch, Pencil)
//    pan   : right-drag or Cmd-drag   / two-finger drag
//    zoom  : scroll wheel, trackpad pinch (magnify) / pinch
//    pick  : click / tap - used by measure mode and selection; a press
//            that moves less than 3 points counts as a click, not a drag
//
//  Apple Pencil is deliberately just another one-finger pointer for
//  orbit/pick: no Pencil-only modes, so the iPad app behaves the same
//  with a finger. (Pencil hover is not used - it is unavailable on the
//  Mac side and the bridge must behave identically on both.)
//

import MetalKit
import simd

#if os(macOS)
import AppKit
#else
import UIKit
#endif

public final class CascadeMetalView: MTKView {
    public let cascadeRenderer: CascadeRenderer

    private var dragStartPoint: SIMD2<Float>?
    private var dragMoved: Float = 0
    private var isPanning = false

    public convenience init() {
        guard let renderer = CascadeRenderer() else {
            fatalError("Cascade Console viewer requires a Metal-capable GPU")
        }
        self.init(renderer: renderer)
    }

    public init(renderer: CascadeRenderer) {
        self.cascadeRenderer = renderer
        super.init(frame: .zero, device: renderer.metalDevice)
        commonInit()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func commonInit() {
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        clearColor = MTLClearColorMake(0.05, 0.05, 0.06, 1)
        enableSetNeedsDisplay = false
        isPaused = false
        preferredFramesPerSecond = 60
        delegate = cascadeRenderer
        #if os(iOS)
        installTouchGestures()
        #endif
    }

    // MARK: Shared gesture maths (points -> camera)

    private func orbitBy(dx: Float, dy: Float) {
        cascadeRenderer.store.camera.orbit(azimuthDelta: dx * 0.01,
                                           elevationDelta: dy * 0.01)
        cascadeRenderer.notifyCameraChanged()
    }

    private func panBy(dx: Float, dy: Float) {
        let scale = cascadeRenderer.store.camera
            .worldPerPoint(viewHeightPoints: Float(bounds.height))
        // Screen y grows downward; dragging right should move the scene
        // right, i.e. the camera target moves left in camera space.
        cascadeRenderer.store.camera.pan(right: dx, up: dy, scale: scale)
        cascadeRenderer.notifyCameraChanged()
    }

    private func zoomBy(factor: Float) {
        cascadeRenderer.store.camera.zoom(by: factor)
        cascadeRenderer.notifyCameraChanged()
    }

    private func pickAt(_ point: CGPoint) {
        var y = Float(point.y)
        #if os(macOS)
        // AppKit view coordinates are bottom-left origin; the bridge
        // contract is top-left origin, so flip exactly once, here.
        y = Float(bounds.height) - y
        #endif
        _ = cascadeRenderer.pick(
            at: SIMD2<Float>(Float(point.x), y),
            viewSize: SIMD2<Float>(Float(bounds.width), Float(bounds.height)))
    }

    #if os(macOS)
    // MARK: macOS input

    public override func mouseDown(with event: NSEvent) {
        dragStartPoint = SIMD2<Float>(Float(event.locationInWindow.x),
                                      Float(event.locationInWindow.y))
        dragMoved = 0
        isPanning = event.modifierFlags.contains(.command)
    }

    public override func mouseDragged(with event: NSEvent) {
        let dx = Float(event.deltaX), dy = Float(event.deltaY)
        dragMoved += abs(dx) + abs(dy)
        if isPanning { panBy(dx: dx, dy: dy) } else { orbitBy(dx: dx, dy: dy) }
    }

    public override func rightMouseDragged(with event: NSEvent) {
        dragMoved += abs(Float(event.deltaX)) + abs(Float(event.deltaY))
        panBy(dx: Float(event.deltaX), dy: Float(event.deltaY))
    }

    public override func mouseUp(with event: NSEvent) {
        if dragMoved < 3 {
            pickAt(convert(event.locationInWindow, from: nil))
        }
        dragStartPoint = nil
    }

    public override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.scrollingDeltaY)
        if delta != 0 { zoomBy(factor: exp(delta * 0.01)) }
    }

    public override func magnify(with event: NSEvent) {
        zoomBy(factor: 1 + Float(event.magnification))
    }

    public override var acceptsFirstResponder: Bool { true }

    #else
    // MARK: iOS / iPadOS input

    private func installTouchGestures() {
        let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.maximumNumberOfTouches = 1
        addGestureRecognizer(orbit)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @objc private func handleOrbit(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        if g.state == .changed {
            orbitBy(dx: Float(t.x), dy: Float(t.y))
            g.setTranslation(.zero, in: self)
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        if g.state == .changed {
            panBy(dx: Float(t.x), dy: Float(t.y))
            g.setTranslation(.zero, in: self)
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .changed {
            zoomBy(factor: Float(g.scale))
            g.scale = 1
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        pickAt(g.location(in: self))
    }
    #endif
}

// MARK: - Renderer helpers used by the view

public extension CascadeRenderer {
    func notifyCameraChanged() {
        delegate?.viewerDidChangeCamera(self)
    }
}

// MARK: - SwiftUI hosting (both apps embed the viewer this way)

#if os(macOS)
import SwiftUI
public struct CascadeViewerRepresentable: NSViewRepresentable {
    public let renderer: CascadeRenderer
    public init(renderer: CascadeRenderer) { self.renderer = renderer }
    public func makeNSView(context: Context) -> CascadeMetalView {
        CascadeMetalView(renderer: renderer)
    }
    public func updateNSView(_ view: CascadeMetalView, context: Context) {}
}
#else
import SwiftUI
public struct CascadeViewerRepresentable: UIViewRepresentable {
    public let renderer: CascadeRenderer
    public init(renderer: CascadeRenderer) { self.renderer = renderer }
    public func makeUIView(context: Context) -> CascadeMetalView {
        CascadeMetalView(renderer: renderer)
    }
    public func updateUIView(_ view: CascadeMetalView, context: Context) {}
}
#endif
