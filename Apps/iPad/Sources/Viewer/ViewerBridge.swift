import Foundation

// MARK: - Viewer bridge ADAPTER (INTEGRATION — resolution (e))
//
// The NORMATIVE viewer bridge is Agent 5's, included ONCE at
// Shared/Viewer/Swift/ViewerBridge.swift: protocol `ViewerBridge`,
// implemented by `CascadeRenderer`, fed pre-tessellated MeshObjects,
// driven by `ViewerCommand` / `ViewCommandParser`.
//
// This iPad scaffold originally defined its own protocol
// `CascadeViewerBridging` (displayObject / fitAll / setWireframe).
// That definition is REMOVED so Agent 5's protocol is the only viewer
// protocol in the combined target. The placeholder class below keeps
// its original call surface so AppState / ViewportPlaceholderView keep
// working until the real viewer is swapped in.
//
// TODO (first device build, see INTEGRATION-NOTES.md (e)):
//   1. AppState: replace `PlaceholderViewerBridge` with
//      `CascadeRenderer` (Shared/Viewer) and forward picks through
//      `ViewerBridgeDelegate` instead of `onObjectPicked`.
//   2. ContentView: replace `ViewportPlaceholderView` with
//      `CascadeViewerRepresentable(renderer:)`.

/// Non-rendering bridge used by the placeholder viewport. It records
/// what it was asked to show so the UI (counts, names, wireframe state)
/// is fully testable before the Metal viewer lands.
final class PlaceholderViewerBridge: ObservableObject {

    var onObjectPicked: ((String) -> Void)?

    @Published private(set) var displayedNames: [String] = []
    @Published private(set) var isWireframe: Bool = false
    @Published private(set) var fitCount: Int = 0

    private var displayedIDs: [UUID] = []

    func displayObject(id: UUID, name: String) {
        if !displayedIDs.contains(id) {
            displayedIDs.append(id)
            displayedNames.append(name)
        }
    }

    func removeObject(id: UUID) {
        if let index = displayedIDs.firstIndex(of: id) {
            displayedIDs.remove(at: index)
            if index < displayedNames.count {
                displayedNames.remove(at: index)
            }
        }
    }

    func clearScene() {
        displayedIDs.removeAll()
        displayedNames.removeAll()
    }

    func fitAll() {
        fitCount += 1
    }

    func setWireframe(_ enabled: Bool) {
        isWireframe = enabled
    }
}
