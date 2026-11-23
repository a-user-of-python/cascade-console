import SwiftUI
import AppKit

// MARK: - Viewer bridge ADAPTER (INTEGRATION — resolution (e))
//
// The NORMATIVE viewer bridge is Agent 5's, included ONCE at
// Shared/Viewer/Swift/ViewerBridge.swift: protocol `ViewerBridge`,
// implemented by `CascadeRenderer`, fed pre-tessellated MeshObjects,
// driven by `ViewerCommand` / `ViewCommandParser`.
//
// This Mac scaffold originally defined its OWN protocol also named
// `ViewerBridge` (render(objects:) / fitAll() / clearScene()). That
// definition is REMOVED — the name now belongs to Agent 5's protocol
// alone, so both files can live in one target without a collision.
//
// What remains here is only the placeholder class the scaffold's
// AppState constructs today, with its original call surface.
//
// TODO (first device build, see INTEGRATION-NOTES.md (e)):
//   1. AppState.swift: change `let viewer: ViewerBridge` and the
//      `viewer: ViewerBridge = PlaceholderViewerBridge()` default to
//      the real renderer (`CascadeRenderer` from Shared/Viewer).
//   2. ContentView.swift: replace `ViewportPlaceholderView` below with
//      `CascadeViewerRepresentable(renderer:)` from Shared/Viewer.
//   3. Delete this placeholder class and the placeholder view.

/// Placeholder bridge used until Agent 5's viewer lands. Stores the last
/// request so state code can be exercised; draws nothing itself.
final class PlaceholderViewerBridge {
    private(set) var lastRendered: [SceneObjectSnapshot] = []
    private(set) var fitAllCount = 0
    private(set) var clearCount = 0

    func render(objects: [SceneObjectSnapshot]) {
        lastRendered = objects
    }

    func fitAll() {
        fitAllCount += 1
    }

    func clearScene() {
        clearCount += 1
        lastRendered = []
    }
}

// MARK: - Placeholder viewer view
//
// A calm, high-contrast stand-in panel: it states plainly that it is a
// placeholder, and lists what the Metal viewer will draw. No fake 3D, no
// pretend geometry — honest scaffolding.

struct ViewportPlaceholderView: NSViewRepresentable {
    var objects: [SceneObjectSnapshot]
    /// Changing this value asks the placeholder to note a "fit all" request.
    var fitAllToken: UUID

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.tag = 1001
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
        ])
        updateLabel(in: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateLabel(in: nsView)
    }

    private func updateLabel(in view: NSView) {
        guard let label = view.viewWithTag(1001) as? NSTextField else { return }
        let visible = objects.filter { $0.isVisible }
        if visible.isEmpty {
            label.stringValue = "3D view\n\nThe Metal viewer plugs in here (Shared/Viewer, ViewerBridge).\nCreate an object — try:  box base"
        } else {
            let names = visible.map { $0.name }.joined(separator: ", ")
            label.stringValue = "3D view (placeholder)\n\nWill draw: \(names)"
        }
    }
}
