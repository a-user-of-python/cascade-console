import SwiftUI

/// The real 3D viewport (v0.2): Agent 5's CascadeMetalView hosted via
/// CascadeViewerRepresentable, fed by AppState's viewer feed
/// (engine cc_view_data -> CCM1 -> MeshObject -> CascadeRenderer).
/// The Fit / display-mode chips drive the renderer through the
/// normative ViewerBridge commands, as the placeholder's chips did.
struct ViewportView: View {
    let renderer: CascadeRenderer?
    /// Objects actually loaded in the viewer, from AppState's
    /// published count (updated after each scene load). Reading the
    /// renderer's list directly from this body showed a stale 0 —
    /// see AppState.viewerObjectCount (FIXLOG v0.2.3).
    let objectCount: Int
    @State private var isWireframe = false

    var body: some View {
        ZStack {
            if let renderer {
                CascadeViewerRepresentable(renderer: renderer)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("3D view unavailable — this device has no Metal device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    GlassChipButton(title: "Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                        renderer?.apply(.fit)
                    }
                    GlassChipButton(
                        title: isWireframe ? "Shaded" : "Wireframe",
                        systemImage: "grid") {
                        isWireframe.toggle()
                        renderer?.apply(.displayMode(isWireframe ? .wireframe : .shaded))
                    }
                    Spacer()
                    Text("\(objectCount) object(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
        }
        .accessibilityLabel("3D viewport")
    }
}
